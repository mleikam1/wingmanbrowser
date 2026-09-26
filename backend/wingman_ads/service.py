"""Finite contextual serving and transactional event settlement; no network I/O."""
import json
from pathlib import Path
import re
import secrets
import threading
from urllib.parse import urlsplit

from .common import AdsError, INTENTS, SECTIONS, PLACEMENTS, TTL, Tokens, day, integer, iso, experiment_approval
from .store import AdsStore
from .demand import CandidateChain

class AdsService:
    def __init__(self, store, signing_key=None, *, environment='local', live_authorized=False, sweep=True, experiment_path=None, demand_chain=None):
        if ((store.mode=='test' and (environment!='local' or live_authorized))
                or (store.mode=='live' and (environment!='single-durable-host' or not live_authorized))):
            raise AdsError('live-ads-and-finance-not-authorized')
        store.authorize_live()
        self.store, self.clock = store, store.clock
        self.tokens = Tokens(signing_key or store.signing_key, self.clock)
        self.fixture = store.mode=='test'
        self.experiment_path=experiment_path
        self.demand_chain=demand_chain or CandidateChain()
        store.purge_expired()
        self._stop=threading.Event()
        self._sweeper=None
        if sweep:
            def sweep_expired():
                while not self._stop.wait(60):
                    try:
                        store.purge_expired()
                    except AdsError:
                        pass  # Serving still fails closed if storage is unavailable.
            self._sweeper=threading.Thread(target=sweep_expired,name='wingman-ad-token-expiry',daemon=True)
            self._sweeper.start()

    def close(self):
        self._stop.set()
        if self._sweeper:
            self._sweeper.join(timeout=2)

    def experiment(self):
        if not self.experiment_path: return {'secondSearchAdEnabled':False,'explorationEnabled':False}
        value=experiment_approval(self.experiment_path,self.clock)
        if not self.fixture and value['secondSearchAdEnabled'] and not self.store.authorize_live()['secondSearchAdEnabled']:
            raise AdsError('experiment-authorization-required')
        return value

    def issue_context(self, *, intent, country='US', language='en', context='normal', fixture=False, organic_count=0):
        # A fixture service must never monetize a live provider result.
        self.store.authorize_live()
        if context != 'normal' or intent not in INTENTS or fixture != self.fixture:
            return None
        from wingman_search.contracts import LOCALES
        if country not in LOCALES or LOCALES[country][0] != language:
            return None
        now = self.clock()
        second=self.experiment()['secondSearchAdEnabled'] and integer(organic_count,0,100)>=3
        token = self.tokens.sign('context', dict(id=secrets.token_hex(16),iat=now,exp=now+TTL,
            intent=intent,country=country,language=language,placement='search',fixture=self.fixture,secondSlotAllowed=second))
        return {'token':token,'expiresAt':iso(now+TTL),'secondSlotAllowed':second}

    def nofill(self, reason):
        return {'schemaVersion':1,'status':'no-fill','fixture':self.fixture,'noFillReason':reason,'ad':None}

    def decision(self, raw):
        self.store.authorize_live()
        if not isinstance(raw, dict):
            raise AdsError('invalid-ad-request')
        placement = raw.get('placement')
        if placement not in PLACEMENTS:
            raise AdsError('invalid-placement')
        if raw.get('context') != 'normal' or raw.get('foreground') is not True:
            return self.nofill('protected-context')
        now = self.clock()
        if placement == 'search':
            if set(raw) not in ({'placement','context','contextToken','foreground'}, {'placement','context','contextToken','foreground','slotIndex'}):
                raise AdsError('unsupported-ad-parameters')
            grant = self.tokens.read(raw['contextToken'], 'context')
            if (grant.get('fixture') is not self.fixture or grant.get('intent') not in INTENTS
                    or grant.get('placement') != 'search'):
                raise AdsError('invalid-ad-context')
            page, slot, expires = grant['id'], integer(raw.get('slotIndex',0),0,1), grant['exp']
            if slot and (grant.get('secondSlotAllowed') is not True or not self.experiment()['secondSearchAdEnabled']):
                return self.nofill('density-limit')
            target, country, language = grant['intent'],grant['country'],grant['language']
        else:
            fields = {'placement','context','foreground','pageId','country','language','section',
                      'organicCount','sponsoredCount','slotIndex'}
            if set(raw) != fields or not isinstance(raw.get('pageId'),str) or not re.fullmatch(r'[a-f0-9]{32}',raw['pageId']):
                raise AdsError('unsupported-ad-parameters')
            page, slot = raw['pageId'],integer(raw['slotIndex'],0,1)
            expires = now+TTL
            target,country,language = raw['section'],raw['country'],raw['language']
            organic = integer(raw['organicCount'],0,10000)
            sponsored = integer(raw['sponsoredCount'],0,10000)
            if target not in SECTIONS:
                return self.nofill('sensitive-or-unreviewed-section')
            if placement == 'newtab' and (target != 'untargeted' or slot != 0 or sponsored):
                return self.nofill('density-limit')
            if placement == 'news' and (target == 'untargeted' or organic < 6*(slot+1) or sponsored >= 2):
                return self.nofill('density-limit')
            from wingman_search.contracts import LOCALES
            if country not in LOCALES or LOCALES[country][0] != language:
                raise AdsError('invalid-locale')
        with self.store.transaction() as db:
            self.store.authorize_live()
            now=self.clock()
            if placement=='search':
                self.tokens.read(raw['contextToken'],'context')
                if slot and not self.experiment()['secondSearchAdEnabled']: return self.nofill('density-limit')
            else:
                expires=now+TTL
            self.store.cleanup(db)
            previous = db.execute('SELECT * FROM opportunities WHERE page_id=? AND slot=?',(page,slot)).fetchone()
            if previous:
                if previous['placement'] != placement:
                    return self.nofill('density-limit')
                delivery = db.execute('SELECT * FROM deliveries WHERE page_id=? AND slot=?',(page,slot)).fetchone()
                if delivery:
                    campaign = self.store.campaign(db,delivery['campaign_id'])
                    if self._active(campaign,now) and campaign['version'] == delivery['version']:
                        return self._filled(campaign,delivery)
                    return self.nofill('campaign-unavailable')
                return self.nofill(previous['reason'])
            ceiling=2 if placement=='news' or (placement=='search' and grant.get('secondSlotAllowed') is True) else 1
            page_opportunities=db.execute('SELECT COUNT(*) FROM opportunities WHERE page_id=?',(page,)).fetchone()[0]
            if page_opportunities >= ceiling:
                return self.nofill('density-limit')
            if placement=='search' and page_opportunities==0:
                self.store.count(db,'-',placement,'eligible-page')
            self.store.count(db,'-',placement,'opportunity')
            self.store.count(db,'-',placement,'eligible')
            candidates, reasons = [], set()
            rows = list(db.execute('SELECT id FROM campaigns'))
            for row in rows:
                c = self.store.campaign(db,row['id'])
                cfg = c['config']
                if not self.store.policy.allows_result(cfg['headline'],cfg['body'],cfg['landingUrl']):
                    if c['status']=='active':
                        self.store.release(db,c['id'])
                        db.execute("UPDATE campaigns SET status='paused',version=version+1 WHERE id=?",(c['id'],))
                    reasons.add('policy-rejection')
                    continue
                if not self._active(c,now):
                    reasons.add('campaign-unavailable')
                    continue
                if (placement not in cfg['placements'] or country != cfg['country'] or language != cfg['language']
                        or target not in cfg['targets'] or target in cfg['negativeTargets']):
                    reasons.add('context-mismatch')
                    continue
                price = cfg['rateMicros'] if cfg['billingType']=='cpc' else cfg['rateMicros']//1000
                available = c['cash_received']-c['cash_refunded']-c['spent']+c['credits']-c['reserved']
                spent_today = db.execute("SELECT COALESCE(SUM(value),0) FROM aggregates WHERE day=? AND campaign_id=? AND metric='earned-micros'",
                                        (day(now),c['id'])).fetchone()[0]
                pending_views = db.execute('SELECT COUNT(*) FROM deliveries WHERE campaign_id=? AND viewed=0',(c['id'],)).fetchone()[0]
                pending_clicks = db.execute('SELECT COUNT(*) FROM deliveries WHERE campaign_id=? AND clicked=0',(c['id'],)).fetchone()[0]
                if (min(available,cfg['budgetMicros']-c['spent']-c['reserved'],cfg['dailyBudgetMicros']-spent_today-c['reserved']) < price
                        or c['views']+pending_views >= cfg['impressionCap'] or c['clicks']+pending_clicks >= cfg['clickCap']):
                    reasons.add('budget-or-cap-exhausted')
                    continue
                if db.execute('SELECT COUNT(*) FROM deliveries WHERE campaign_id=? AND issued>?',(c['id'],now-60)).fetchone()[0] >= 100:
                    reasons.add('risk-limit')
                    continue
                elapsed = max(0,min(1,(now-cfg['startsAt'])/(cfg['endsAt']-cfg['startsAt'])))
                behind = c['views'] < int(cfg['guaranteedImpressions']*elapsed)
                metrics = dict(db.execute("SELECT metric,SUM(value) FROM aggregates WHERE campaign_id=? AND placement=? GROUP BY metric",(c['id'],placement)).fetchall())
                fills=metrics.get('fill',0)
                # Both models estimate earnings per delivered opportunity. Prior
                # click=1% and qualified-view=25% are conservative assumptions,
                # not measured performance; smoothing only begins at 20 fills.
                probability=(min(1,(metrics.get('click',0)+1)/(fills+100)) if fills>=20 else .01) if cfg['billingType']=='cpc' else (min(1,(metrics.get('view',0)+25)/(fills+100)) if fills>=20 else .25)
                fees = db.execute("SELECT COALESCE(SUM(amount),0) FROM business_entries WHERE campaign_id=? AND kind IN ('payment-fee','partner-share')",(c['id'],)).fetchone()[0]
                net = max(0,1-fees/max(1,c['cash_received']))
                expected = price*probability*net
                candidates.append((cfg['qualityScore'],behind,expected,c,price))
            candidates.sort(key=lambda v:v[:3],reverse=True)
            # Live bootstrap currently authorizes direct campaigns only. A
            # supplied test adapter cannot convert that approval into partner or
            # merchant permission; a real integration needs a separate review.
            chain=self.demand_chain if self.fixture else CandidateChain()
            best,extension_reasons=chain.choose(candidates,
                dict(placement=placement,country=country,language=language,target=target),now)
            if best is None:
                for extension_reason in extension_reasons:
                    self.store.count(db,'-',placement,'demand-'+extension_reason)
                reason='no-contracts' if not rows else next((r for r in ('policy-rejection','budget-or-cap-exhausted','context-mismatch','risk-limit','campaign-unavailable') if r in reasons),'no-approved-demand')
                db.execute('INSERT INTO opportunities VALUES(?,?,?,?,?)',(page,slot,expires,placement,reason))
                self.store.count(db,'-',placement,'no-fill-'+reason)
                return self.nofill(reason)
            # Quality and contractual pacing precede estimates. Exploration is
            # owner-disabled unless a separately reviewed evidence file permits it.
            eligible = [c for c in candidates if c[:2]==best[:2] and c[3]['config'].get('demandSource','direct')==best[3]['config'].get('demandSource','direct')]
            if len(eligible)>1 and self.experiment()['explorationEnabled'] and secrets.randbelow(10)==0:
                best = secrets.choice(eligible)
            c,price = best[3],best[4]
            if placement=='search' and not db.execute('SELECT 1 FROM deliveries WHERE page_id=?',(page,)).fetchone():
                self.store.count(db,'-',placement,'filled-page')
            delivery = dict(id=secrets.token_hex(16),page_id=page,slot=slot,campaign_id=c['id'],version=c['version'],
                            placement=placement,price=price,reserved=price,issued=now,expires=expires)
            db.execute('INSERT INTO deliveries(id,page_id,slot,campaign_id,version,placement,price,reserved,issued,expires) '
                       'VALUES(:id,:page_id,:slot,:campaign_id,:version,:placement,:price,:reserved,:issued,:expires)',delivery)
            db.execute('UPDATE campaigns SET reserved=reserved+? WHERE id=?',(price,c['id']))
            db.execute('INSERT INTO opportunities VALUES(?,?,?,?,?)',(page,slot,expires,placement,'filled'))
            self.store.count(db,c['id'],placement,'fill')
            return self._filled(c,delivery)

    def _active(self,c,now):
        cfg = c['config']
        return (c['status']=='active' and c['advertiser_approved'] and cfg['startsAt']<=now<cfg['endsAt']
                and now<c['reviewed_until'] and self.store.policy.allows_result(cfg['headline'],cfg['body'],cfg['landingUrl']))

    def _filled(self,c,d):
        cfg = c['config']
        # Delivery TTL is always <=15 minutes, even when its page grant expires sooner.
        token = self.tokens.sign('delivery',dict(id=d['id'],campaign=c['id'],creative=c['creative_id'],version=d['version'],
            placement=d['placement'],price=d['price'],iat=d['expires']-TTL,exp=d['expires'],fixture=self.fixture))
        return {'schemaVersion':1,'status':'filled','fixture':self.fixture,'noFillReason':None,'ad':{
            'id':d['id'],'campaignId':c['id'],'creativeId':c['creative_id'],'placement':d['placement'],
            'label':'Sponsored','advertiser':c['advertiser'],'headline':cfg['headline'],'body':cfg['body'],
            'displayDomain':urlsplit(cfg['landingUrl']).hostname,'landingId':c['landing_id'],'deliveryToken':token,
            'expiresAt':iso(d['expires']),'whyThisAd':'Selected from this current nonsensitive context or untargeted rotation. No browsing history or advertising profile is used. Visiting the advertiser shares ordinary website connection information.',
            'imagePath':'/v1/ads/assets/'+cfg['assetId']+'.png' if cfg['assetId'] else None}}

    def event(self,raw):
        self.store.authorize_live()
        fields = {'deliveryToken','kind','foreground','visiblePermille','visibleMs','explicitAction'}
        if not isinstance(raw,dict) or set(raw)!=fields or raw.get('kind') not in {'render','view','click'}:
            raise AdsError('invalid-event')
        if type(raw['foreground']) is not bool or type(raw['explicitAction']) is not bool:
            raise AdsError('invalid-event')
        visible = integer(raw['visiblePermille'],0,1000)
        duration = integer(raw['visibleMs'],0,TTL*1000)
        payload = self.tokens.read(raw['deliveryToken'],'delivery')
        now,kind = self.clock(),raw['kind']
        result = {'schemaVersion':1,'status':'rejected','fixture':self.fixture,'billable':False,'chargedMicros':0,
                  'testChargedMicros':0,'landingUrl':None,'errorCode':None}
        with self.store.transaction() as db:
            self.store.authorize_live()
            now=self.clock()
            self.tokens.read(raw['deliveryToken'],'delivery')
            self.store.cleanup(db)
            d = db.execute('SELECT * FROM deliveries WHERE id=?',(payload['id'],)).fetchone()
            if d is None:
                result['errorCode']='delivery-unavailable'
                return result
            c = self.store.campaign(db,d['campaign_id'])
            if (payload.get('fixture') is not self.fixture or payload['campaign']!=c['id'] or payload['creative']!=c['creative_id']
                    or payload['placement']!=d['placement'] or payload['price']!=d['price'] or payload['version']!=d['version']
                    or d['version']!=c['version'] or not self._active(c,now)):
                if c['status']=='active' and not self._active(c,now):
                    self.store.release(db,c['id'])
                    db.execute("UPDATE campaigns SET status='paused',version=version+1 WHERE id=?",(c['id'],))
                elif d['reserved']:
                    db.execute('UPDATE campaigns SET reserved=reserved-? WHERE id=?',(d['reserved'],c['id']))
                    db.execute('UPDATE deliveries SET reserved=0 WHERE id=?',(d['id'],))
                self.store.count(db,c['id'],d['placement'],'rejected')
                result['errorCode']='campaign-unavailable'
                return result
            column={'render':'rendered','view':'viewed','click':'clicked'}[kind]
            if d[column]:
                result['status']='duplicate'
                return result
            valid = raw['foreground'] and visible>0
            if kind=='view':
                valid = valid and visible>=500 and duration>=1000 and now-d['issued']>=1
            elif kind=='click':
                valid = valid and raw['explicitAction']
            if not valid:
                self.store.count(db,c['id'],d['placement'],'rejected')
                result['errorCode']='event-not-qualified'
                return result
            cfg=c['config']
            bill = (kind=='click' and cfg['billingType']=='cpc') or (kind=='view' and cfg['billingType']=='cpm')
            if (kind=='view' and c['views']>=cfg['impressionCap']) or (kind=='click' and c['clicks']>=cfg['clickCap']):
                result['errorCode']='cap-exhausted'
                return result
            if bill and not d['charged']:
                if d['reserved']!=d['price'] or c['reserved']<d['price']:
                    raise AdsError('reservation-unavailable')
                db.execute('UPDATE campaigns SET reserved=reserved-?,spent=spent+? WHERE id=?',(d['price'],d['price'],c['id']))
                db.execute('UPDATE deliveries SET reserved=0,charged=1 WHERE id=?',(d['id'],))
                self.store.count(db,c['id'],d['placement'],'earned-micros',d['price'])
                self.store.count(db,c['id'],d['placement'],'billable-test-event' if self.fixture else 'billable-event')
                result['testChargedMicros' if self.fixture else 'chargedMicros']=d['price']
                result['billable']=not self.fixture
            db.execute('UPDATE deliveries SET '+column+'=1 WHERE id=?',(d['id'],))
            if kind in {'view','click'}:
                counter='views' if kind=='view' else 'clicks'
                db.execute('UPDATE campaigns SET '+counter+'='+counter+'+1 WHERE id=?',(c['id'],))
            self.store.count(db,c['id'],d['placement'],kind)
            result['status']='accepted'
            if kind=='click':
                result['landingUrl']=cfg['landingUrl']
            return result

    def asset(self,asset_id):
        self.store.authorize_live()
        if not re.fullmatch(r'[a-f0-9]{64}',asset_id or ''):
            raise AdsError('asset-unavailable')
        with self.store.transaction() as db:
            self.store.authorize_live()
            now=self.clock()
            approved = any(c['config'].get('assetId')==asset_id and self._active(c,now) for c in
                [self.store.campaign(db,row[0]) for row in db.execute('SELECT id FROM campaigns')])
            row = db.execute('SELECT body,mime FROM assets WHERE id=?',(asset_id,)).fetchone()
            if not approved or row is None:
                raise AdsError('asset-unavailable')
            return bytes(row['body']),row['mime']


def initialize_fixture_store(path):
    store = AdsStore.initialize(path)
    advertiser = store.create_advertiser(name='Fixture Sponsor',domain='example.org',contact='fixture@example.org')
    store.approve_advertiser(advertiser)
    now = store.clock()
    config = dict(headline='Fixture: useful everyday tools',body='Synthetic sponsored example. Test money only.',
        landingUrl='https://example.org/',placements=['search','newtab','news'],country='US',language='en',
        targets=sorted(INTENTS|SECTIONS),negativeTargets=[],startsAt=now-1,endsAt=now+7*86400,billingType='cpc',
        rateMicros=500_000,budgetMicros=500_000_000,dailyBudgetMicros=500_000_000,impressionCap=1000,
        clickCap=1000,agreementReference='fixture-only-not-a-contract',guaranteedImpressions=0,
        exclusive=False,assetId=None,qualityScore=2,currency='USD')
    campaign = store.create_campaign(advertiser,config)
    store.business_entry(campaign,kind='receipt',amount_micros=500_000_000,
                         operation_key='fixture-initial-receipt',reference='fixture-only-test-money')
    store.approve_campaign(campaign,review_reference='fixture-review')
    return AdsService(store)

def open_fixture_service(path):
    return AdsService(AdsStore(path))

def open_approved_live_service(path):
    return AdsService(AdsStore(path),environment='single-durable-host',live_authorized=True)
