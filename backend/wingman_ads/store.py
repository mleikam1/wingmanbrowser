"""One durable local finance host; never use a per-instance cloud SQLite file.

BEGIN IMMEDIATE serializes cash, budgets, event reservations and settlement.
Business records are separate from short-lived random delivery state. There is
no consumer identifier/query/address column. Missing files never auto-initialize.
"""
from contextlib import contextmanager
import hashlib
import io
import json
import os
from pathlib import Path
import secrets
import sqlite3
from urllib.parse import urlsplit

from wingman_search.policy import SearchPolicy, query_allowed
from wingman_search.secrets import validate_local_path, SecretError
from .common import AdsError, TTL, TARGETS, PLACEMENTS, day, encode, identifier, integer, now_seconds, text, live_approval


class AdsStore:
    def __init__(self, path, *, policy=None, clock=now_seconds):
        self.path = Path(path).absolute()
        self.marker = self.path.with_name(self.path.name + '.initialized')
        self.policy, self.clock = policy or SearchPolicy(), clock
        with self.transaction() as db:
            state = db.execute('SELECT * FROM state WHERE id=1').fetchone()
            self.mode = state['mode']
            self.signing_key = bytes.fromhex(state['signing_key'])
            self.authorization_path = state['authorization_path']

    @classmethod
    def initialize(cls, path, *, mode='test', policy=None, clock=now_seconds):
        if mode != 'test':
            raise AdsError('live-finance-not-authorized')
        return cls._initialize(path,mode='test',policy=policy,clock=clock)

    @classmethod
    def initialize_approved_live(cls,path,*,authorization_path,policy=None,clock=now_seconds):
        live_approval(authorization_path,path,clock)
        return cls._initialize(path,mode='live',authorization_path=str(Path(authorization_path).absolute()),policy=policy,clock=clock)

    @classmethod
    def _initialize(cls,path,*,mode,authorization_path=None,policy=None,clock=now_seconds):
        path = Path(path).absolute()
        marker = path.with_name(path.name + '.initialized')
        identity = secrets.token_hex(16)
        try:
            if not path.parent.exists():
                validate_local_path(path.parent.parent / 'unused', require_file=False)
                path.parent.mkdir(mode=0o700)
            validate_local_path(path)
            validate_local_path(marker)
            fd = os.open(marker, os.O_CREAT | os.O_EXCL | os.O_WRONLY | os.O_NOFOLLOW, 0o600)
            with os.fdopen(fd, 'w') as stream:
                stream.write(identity)
                stream.flush()
                os.fsync(stream.fileno())
            fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY | os.O_NOFOLLOW, 0o600)
            os.close(fd)
            db = sqlite3.connect(path)
            try:
                db.execute('PRAGMA synchronous=FULL')
                db.execute('PRAGMA secure_delete=ON')
                db.executescript('''
                    CREATE TABLE state(id INTEGER PRIMARY KEY CHECK(id=1), version INTEGER NOT NULL,
                        identity TEXT NOT NULL, mode TEXT NOT NULL CHECK(mode IN ('test','live')), signing_key TEXT NOT NULL,
                        authorization_path TEXT);
                    CREATE TABLE advertisers(id TEXT PRIMARY KEY, name TEXT NOT NULL, domain TEXT NOT NULL,
                        contact TEXT NOT NULL, approved INTEGER NOT NULL DEFAULT 0);
                    CREATE TABLE applications(id TEXT PRIMARY KEY, name TEXT NOT NULL, domain TEXT NOT NULL,
                        contact TEXT NOT NULL, offer TEXT NOT NULL, created INTEGER NOT NULL, status TEXT NOT NULL);
                    CREATE TABLE campaigns(id TEXT PRIMARY KEY, advertiser_id TEXT NOT NULL REFERENCES advertisers(id),
                        creative_id TEXT NOT NULL, landing_id TEXT NOT NULL, version INTEGER NOT NULL,
                        status TEXT NOT NULL, config TEXT NOT NULL, reviewed_until INTEGER NOT NULL DEFAULT 0,
                        cash_received INTEGER NOT NULL DEFAULT 0 CHECK(cash_received>=0),
                        cash_refunded INTEGER NOT NULL DEFAULT 0 CHECK(cash_refunded>=0),
                        spent INTEGER NOT NULL DEFAULT 0 CHECK(spent>=0),
                        credits INTEGER NOT NULL DEFAULT 0 CHECK(credits>=0),
                        reserved INTEGER NOT NULL DEFAULT 0 CHECK(reserved>=0),
                        views INTEGER NOT NULL DEFAULT 0, clicks INTEGER NOT NULL DEFAULT 0);
                    CREATE TABLE business_entries(id INTEGER PRIMARY KEY, operation_key TEXT UNIQUE NOT NULL,
                        campaign_id TEXT NOT NULL REFERENCES campaigns(id), kind TEXT NOT NULL,
                        amount INTEGER NOT NULL CHECK(amount>0), reference TEXT NOT NULL, created INTEGER NOT NULL);
                    CREATE TABLE audit(id INTEGER PRIMARY KEY, operator TEXT NOT NULL, action TEXT NOT NULL,
                        entity TEXT NOT NULL, created INTEGER NOT NULL);
                    CREATE TABLE deliveries(id TEXT PRIMARY KEY, page_id TEXT NOT NULL, slot INTEGER NOT NULL,
                        campaign_id TEXT NOT NULL REFERENCES campaigns(id), version INTEGER NOT NULL,
                        placement TEXT NOT NULL, price INTEGER NOT NULL, reserved INTEGER NOT NULL,
                        issued INTEGER NOT NULL, expires INTEGER NOT NULL, rendered INTEGER NOT NULL DEFAULT 0,
                        viewed INTEGER NOT NULL DEFAULT 0, clicked INTEGER NOT NULL DEFAULT 0,
                        charged INTEGER NOT NULL DEFAULT 0, UNIQUE(page_id,slot));
                    CREATE TABLE opportunities(page_id TEXT NOT NULL, slot INTEGER NOT NULL, expires INTEGER NOT NULL,
                        placement TEXT NOT NULL, reason TEXT NOT NULL, PRIMARY KEY(page_id,slot));
                    CREATE TABLE aggregates(day TEXT NOT NULL,campaign_id TEXT NOT NULL,placement TEXT NOT NULL,
                        metric TEXT NOT NULL,value INTEGER NOT NULL,PRIMARY KEY(day,campaign_id,placement,metric));
                    CREATE TABLE assets(id TEXT PRIMARY KEY, body BLOB NOT NULL, mime TEXT NOT NULL);
                    CREATE TABLE operator_auth(id INTEGER PRIMARY KEY CHECK(id=1), salt TEXT NOT NULL, digest TEXT NOT NULL);
                ''')
                db.execute('INSERT INTO state VALUES(1,1,?,?,?,?)', (identity, mode, secrets.token_hex(32),authorization_path))
                db.commit()
            finally:
                db.close()
        except (OSError, sqlite3.Error, SecretError):
            raise AdsError('initialization-refused-preserve-existing-ledger') from None
        return cls(path, policy=policy, clock=clock)

    @contextmanager
    def transaction(self):
        db = None
        try:
            validate_local_path(self.path, require_file=True)
            validate_local_path(self.marker, require_file=True)
            db = sqlite3.connect(self.path.as_uri() + '?mode=rw', uri=True, timeout=5)
            db.row_factory = sqlite3.Row
            db.execute('PRAGMA foreign_keys=ON')
            db.execute('PRAGMA synchronous=FULL')
            db.execute('PRAGMA secure_delete=ON')
            db.execute('BEGIN IMMEDIATE')
            state = db.execute('SELECT * FROM state WHERE id=1').fetchone()
            if (state is None or state['version'] != 1 or state['mode'] not in {'test','live'}
                    or state['identity'] != self.marker.read_text()
                    or len(bytes.fromhex(state['signing_key'])) != 32
                    or db.execute('PRAGMA quick_check').fetchone()[0] != 'ok'):
                raise AdsError('finance-ledger-corrupt')
            yield db
            db.commit()
        except AdsError:
            if db is not None:
                db.rollback()
            raise
        except (OSError, sqlite3.Error, SecretError, ValueError, TypeError, KeyError):
            if db is not None:
                db.rollback()
            raise AdsError('finance-ledger-unavailable') from None
        finally:
            if db is not None:
                db.close()

    def audit(self, db, operator, action, entity):
        db.execute('INSERT INTO audit(operator,action,entity,created) VALUES(?,?,?,?)',
                   (identifier(operator), identifier(action), identifier(entity), self.clock()))

    def authorize_live(self):
        if self.mode=='live':
            return live_approval(self.authorization_path,self.path,self.clock)
        return None

    def count(self, db, campaign, placement, metric, amount=1):
        db.execute('INSERT INTO aggregates VALUES(?,?,?,?,?) ON CONFLICT(day,campaign_id,placement,metric) '
                   'DO UPDATE SET value=value+excluded.value', (day(self.clock()), campaign, placement, metric, amount))

    def cleanup(self, db):
        now = self.clock()
        for row in db.execute('SELECT campaign_id,SUM(reserved) amount FROM deliveries WHERE expires<=? GROUP BY campaign_id', (now,)):
            db.execute('UPDATE campaigns SET reserved=reserved-? WHERE id=?', (row['amount'], row['campaign_id']))
        db.execute('DELETE FROM deliveries WHERE expires<=?', (now,))
        db.execute('DELETE FROM opportunities WHERE expires<=?', (now,))

    def purge_expired(self):
        with self.transaction() as db:
            self.cleanup(db)

    def apply(self, *, name, domain, contact, offer):
        name, contact, offer = text(name, 80), text(contact, 160), text(offer, 1000)
        domain = self.domain(domain)
        with self.transaction() as db:
            # Global bounded intake; no IP/contact-derived rate profiles.
            if db.execute('SELECT COUNT(*) FROM applications WHERE created>?', (self.clock()-86400,)).fetchone()[0] >= 100:
                raise AdsError('application-capacity')
            entity = secrets.token_hex(16)
            db.execute('INSERT INTO applications VALUES(?,?,?,?,?,?,?)',
                       (entity, name, domain, contact, offer, self.clock(), 'pending'))
            return entity

    def domain(self, value):
        domain = text(value, 253).lower()
        if (urlsplit('https://' + domain).hostname != domain or '/' in domain
                or not self.policy.allows_url('https://' + domain + '/')):
            raise AdsError('invalid-domain')
        return domain

    def review_application(self,entity,*,approve,operator='owner'):
        self.authorize_live()
        with self.transaction() as db:
            row=db.execute('SELECT * FROM applications WHERE id=?',(identifier(entity),)).fetchone()
            if row is None or row['status']!='pending': raise AdsError('application-not-pending')
            advertiser=None
            if approve:
                if self.mode=='live' and any('fixture' in row[k].lower() for k in ('name','domain','contact')):
                    raise AdsError('fixture-cannot-be-live')
                advertiser=secrets.token_hex(16)
                db.execute('INSERT INTO advertisers VALUES(?,?,?,?,0)',(advertiser,row['name'],self.domain(row['domain']),row['contact']))
            db.execute('UPDATE applications SET status=? WHERE id=?',('accepted' if approve else 'declined',entity))
            self.audit(db,operator,'application-accepted' if approve else 'application-declined',entity)
            return advertiser

    def create_advertiser(self, *, name, domain, contact, operator='owner'):
        self.authorize_live()
        name, domain, contact = text(name, 80), self.domain(domain), text(contact, 160)
        if self.mode=='live' and any('fixture' in v.lower() for v in (name,domain,contact)):
            raise AdsError('fixture-cannot-be-live')
        entity = secrets.token_hex(16)
        with self.transaction() as db:
            db.execute('INSERT INTO advertisers VALUES(?,?,?,?,0)', (entity, name, domain, contact))
            self.audit(db, operator, 'advertiser-created', entity)
        return entity

    def approve_advertiser(self, entity, *, operator='owner'):
        self.authorize_live()
        with self.transaction() as db:
            row = db.execute('SELECT * FROM advertisers WHERE id=?', (identifier(entity),)).fetchone()
            if row is None:
                raise AdsError('advertiser-not-found')
            self.domain(row['domain'])
            db.execute('UPDATE advertisers SET approved=1 WHERE id=?', (entity,))
            self.audit(db, operator, 'advertiser-approved', entity)

    def validate_campaign(self, raw, advertiser):
        fields = {'headline','body','landingUrl','placements','country','language','targets','negativeTargets',
                  'startsAt','endsAt','billingType','rateMicros','budgetMicros','dailyBudgetMicros',
                  'impressionCap','clickCap','agreementReference','guaranteedImpressions','exclusive',
                  'assetId','qualityScore','currency'}
        if not isinstance(raw, dict) or set(raw) not in (fields,fields|{'demandSource'}):
            raise AdsError('campaign-fields-required')
        c = dict(raw)
        c.setdefault('demandSource','direct')
        if c['demandSource'] not in {'direct','partner','merchant'}:
            raise AdsError('unsupported-demand-source')
        if c['currency']!='USD':
            raise AdsError('unsupported-currency')
        c['headline'], c['body'] = text(c['headline'], 120), text(c['body'], 300, empty=True)
        c['landingUrl'] = text(c['landingUrl'], 2048)
        destination = urlsplit(c['landingUrl'])
        if (not self.policy.allows_result(c['headline'], c['body'], c['landingUrl'])
                or destination.hostname != advertiser['domain'] or destination.query or destination.fragment
                or not query_allowed(c['headline'] + ' ' + c['body'])):
            raise AdsError('creative-or-destination-policy')
        for name, choices in (('placements', PLACEMENTS), ('targets', TARGETS), ('negativeTargets', TARGETS)):
            values = c[name]
            if (not isinstance(values, list) or len(values) > len(choices) or len(set(values)) != len(values)
                    or any(not isinstance(v, str) or v not in choices for v in values)
                    or (name != 'negativeTargets' and not values)):
                raise AdsError('invalid-targeting')
        if c['country'] not in {'US','GB','CA','AU','DE','FR','ES'} or c['language'] not in {'en','de','fr','es'}:
            raise AdsError('invalid-locale')
        from wingman_search.contracts import LOCALES
        if LOCALES[c['country']][0] != c['language']:
            raise AdsError('invalid-locale')
        integer(c['startsAt'], 0, 4102444800)
        integer(c['endsAt'], c['startsAt']+1, min(4102444800, c['startsAt']+366*86400))
        if c['billingType'] not in {'cpc','cpm'}:
            raise AdsError('unsupported-billing')
        for name in ('rateMicros','budgetMicros','dailyBudgetMicros','impressionCap','clickCap'):
            integer(c[name], 1)
        if c['billingType'] == 'cpm' and c['rateMicros'] % 1000:
            raise AdsError('cpm-must-have-exact-micro-per-impression')
        if c['dailyBudgetMicros'] > c['budgetMicros']:
            raise AdsError('invalid-daily-budget')
        identifier(c['agreementReference'])
        if self.mode=='live' and any('fixture' in str(c[name]).lower() for name in ('headline','body','agreementReference')):
            raise AdsError('fixture-cannot-be-live')
        integer(c['guaranteedImpressions'])
        if (c['guaranteedImpressions']>c['impressionCap'] or (c['guaranteedImpressions'] and
                (c['billingType']!='cpm' or c['guaranteedImpressions']*(c['rateMicros']//1000)>c['budgetMicros']))):
            raise AdsError('guarantee-exceeds-authorized-inventory')
        integer(c['qualityScore'], 1, 3)
        if type(c['exclusive']) is not bool:
            raise AdsError('invalid-exclusivity')
        if c['assetId'] is not None:
            identifier(c['assetId'])
        return c

    def create_campaign(self, advertiser_id, raw, *, operator='owner'):
        self.authorize_live()
        with self.transaction() as db:
            advertiser = db.execute('SELECT * FROM advertisers WHERE id=?', (identifier(advertiser_id),)).fetchone()
            if advertiser is None:
                raise AdsError('advertiser-not-found')
            c = self.validate_campaign(raw, advertiser)
            entity = secrets.token_hex(16)
            db.execute('INSERT INTO campaigns(id,advertiser_id,creative_id,landing_id,version,status,config) VALUES(?,?,?,?,1,?,?)',
                       (entity, advertiser_id, secrets.token_hex(16), secrets.token_hex(16), 'draft', encode(c)))
            self.audit(db, operator, 'campaign-created', entity)
            return entity

    def campaign(self, db, entity):
        row = db.execute('SELECT c.*,a.name advertiser,a.domain,a.approved advertiser_approved FROM campaigns c '
                         'JOIN advertisers a ON a.id=c.advertiser_id WHERE c.id=?', (identifier(entity),)).fetchone()
        if row is None:
            raise AdsError('campaign-not-found')
        result = dict(row)
        result['config'] = json.loads(result['config'])
        return result

    def release(self, db, entity):
        db.execute('UPDATE deliveries SET reserved=0 WHERE campaign_id=?', (entity,))
        db.execute('UPDATE campaigns SET reserved=0 WHERE id=?', (entity,))

    def update_campaign(self, entity, raw, *, operator='owner'):
        self.authorize_live()
        with self.transaction() as db:
            row = self.campaign(db, entity)
            c = self.validate_campaign(raw, row)
            if c['budgetMicros'] < row['spent']:
                raise AdsError('budget-below-earned-delivery')
            self.release(db, entity)
            db.execute("UPDATE campaigns SET config=?,version=version+1,status='draft',reviewed_until=0,creative_id=?,landing_id=? WHERE id=?",
                       (encode(c), secrets.token_hex(16), secrets.token_hex(16), entity))
            self.audit(db, operator, 'campaign-edited-review-required', entity)

    def approve_campaign(self, entity, *, review_reference, operator='owner'):
        self.authorize_live()
        identifier(review_reference)
        with self.transaction() as db:
            self.authorize_live()
            self.cleanup(db)
            row = self.campaign(db, entity)
            c = self.validate_campaign(row['config'], row)
            if not row['advertiser_approved'] or row['cash_received']-row['cash_refunded'] <= 0:
                raise AdsError('identity-and-reconciled-funding-required')
            if c['guaranteedImpressions']*(c['rateMicros']//1000)>row['cash_received']-row['cash_refunded']:
                raise AdsError('guarantee-requires-reconciled-prepayment')
            if c['assetId'] and not db.execute('SELECT 1 FROM assets WHERE id=?', (c['assetId'],)).fetchone():
                raise AdsError('approved-asset-required')
            # An exclusive contract cannot sell intersecting inventory twice.
            for other in db.execute("SELECT id,config FROM campaigns WHERE status='active' AND id<>?", (entity,)):
                other = json.loads(other['config'])
                if ((c['exclusive'] or other['exclusive']) and set(c['placements']) & set(other['placements'])
                        and c['country'] == other['country'] and c['language'] == other['language']
                        and c['startsAt'] < other['endsAt'] and other['startsAt'] < c['endsAt']):
                    raise AdsError('exclusive-inventory-already-committed')
            db.execute("UPDATE campaigns SET status='active',reviewed_until=? WHERE id=?", (self.clock()+86400, entity))
            self.audit(db, operator, 'campaign-approved-' + review_reference[:40], entity)

    def pause_campaign(self, entity, *, operator='owner'):
        with self.transaction() as db:
            self.campaign(db, entity)
            self.release(db, entity)
            db.execute("UPDATE campaigns SET status='paused',version=version+1 WHERE id=?", (entity,))
            self.audit(db, operator, 'campaign-paused', entity)

    def business_entry(self, entity, *, kind, amount_micros, operation_key, reference, operator='owner'):
        self.authorize_live()
        integer(amount_micros, 1)
        identifier(operation_key)
        identifier(reference)
        if self.mode=='live' and ('fixture' in reference.lower() or 'fixture' in operation_key.lower()):
            raise AdsError('fixture-cannot-be-live')
        if kind not in {'invoice','receipt','refund','credit','payment-fee','partner-share','chargeback'}:
            raise AdsError('invalid-financial-operation')
        with self.transaction() as db:
            self.cleanup(db)
            prior = db.execute('SELECT * FROM business_entries WHERE operation_key=?', (operation_key,)).fetchone()
            if prior:
                if (prior['campaign_id'],prior['kind'],prior['amount'],prior['reference']) != (entity,kind,amount_micros,reference):
                    raise AdsError('idempotency-conflict')
                return False
            row = self.campaign(db, entity)
            liability = row['cash_received']-row['cash_refunded']-row['spent']+row['credits']
            if kind=='receipt' and row['cash_received']+amount_micros>10**12:
                raise AdsError('campaign-cash-cap-exceeded')
            if kind=='refund' and amount_micros > liability-row['reserved']:
                raise AdsError('funds-reserved-or-already-earned')
            if kind=='chargeback' and amount_micros>row['cash_received']-row['cash_refunded']:
                raise AdsError('reversal-exceeds-collected-cash')
            if kind == 'credit' and amount_micros > row['spent']-row['credits']:
                raise AdsError('credit-exceeds-earned-delivery')
            column = {'receipt':'cash_received','refund':'cash_refunded','chargeback':'cash_refunded','credit':'credits'}.get(kind)
            if column:
                db.execute('UPDATE campaigns SET '+column+'='+column+'+? WHERE id=?', (amount_micros,entity))
            db.execute('INSERT INTO business_entries(operation_key,campaign_id,kind,amount,reference,created) VALUES(?,?,?,?,?,?)',
                       (operation_key,entity,kind,amount_micros,reference,self.clock()))
            if kind == 'chargeback':
                self.release(db, entity)
                db.execute("UPDATE campaigns SET status='paused',version=version+1 WHERE id=?", (entity,))
            self.audit(db, operator, 'finance-'+kind, entity)
            return True

    def add_asset(self, body, *, operator='owner'):
        if not isinstance(body, bytes) or len(body) > 256000:
            raise AdsError('invalid-raster')
        try:
            from PIL import Image
            with Image.open(io.BytesIO(body)) as image:
                if image.format not in {'PNG','JPEG'} or image.width > 1200 or image.height > 600 or getattr(image,'n_frames',1) != 1:
                    raise ValueError()
                image.load()
                output = io.BytesIO()
                image.convert('RGB').save(output, format='PNG')
                sanitized = output.getvalue()
            if len(sanitized) > 512000:
                raise ValueError()
        except Exception:
            raise AdsError('invalid-raster') from None
        asset = hashlib.sha256(sanitized).hexdigest()
        with self.transaction() as db:
            db.execute('INSERT OR IGNORE INTO assets VALUES(?,?,?)', (asset,sanitized,'image/png'))
            self.audit(db, operator, 'raster-added-review-required', asset)
        return asset

    def dashboard(self):
        with self.transaction() as db:
            self.cleanup(db)
            campaigns = [self.campaign(db, row[0]) for row in db.execute('SELECT id FROM campaigns')]
            cash = sum(c['cash_received'] for c in campaigns)
            refunds = sum(c['cash_refunded'] for c in campaigns)
            gross = sum(c['spent'] for c in campaigns)
            credits = sum(c['credits'] for c in campaigns)
            earned = gross-credits
            fees = db.execute("SELECT COALESCE(SUM(amount),0) FROM business_entries WHERE kind IN ('payment-fee','partner-share')").fetchone()[0]
            payment_fees = db.execute("SELECT COALESCE(SUM(amount),0) FROM business_entries WHERE kind='payment-fee'").fetchone()[0]
            partner_share = db.execute("SELECT COALESCE(SUM(amount),0) FROM business_entries WHERE kind='partner-share'").fetchone()[0]
            invoiced = db.execute("SELECT COALESCE(SUM(amount),0) FROM business_entries WHERE kind='invoice'").fetchone()[0]
            aggregate = [dict(r) for r in db.execute('SELECT * FROM aggregates ORDER BY day,campaign_id,placement,metric')]
            prefix='test' if self.mode=='test' else 'live'
            return {'mode':self.mode,'commercialRevenueMicros':earned if self.mode=='live' else 0,
                    'commercialCashMicros':cash if self.mode=='live' else 0,
                    prefix+'CashCollectedMicros':cash,prefix+'InvoicedMicros':invoiced,prefix+'GrossEarnedMicros':gross,prefix+'CreditsMicros':credits,
                    prefix+'EarnedMicros':earned,prefix+'RefundedMicros':refunds,
                    prefix+'PrepaidLiabilityMicros':sum(max(0,c['cash_received']-c['cash_refunded']-c['spent']+c['credits']) for c in campaigns),
                    prefix+'DisputedReceivableMicros':sum(max(0,c['spent']-c['credits']-c['cash_received']+c['cash_refunded']) for c in campaigns),
                    prefix+'ReservedMicros':sum(c['reserved'] for c in campaigns),prefix+'FeesAndSharesMicros':fees,
                    prefix+'PaymentFeesMicros':payment_fees,prefix+'PartnerShareMicros':partner_share,
                    prefix+'NetEarnedMicros':earned-fees,'currency':'USD','campaigns':campaigns,'aggregates':aggregate,
                    'providerCostMicros':None,'otherVariableCostMicros':None,'fullyLoadedResultMicros':None,
                    'trafficVerified':False,'partnerDemandEnabled':False,'secondSearchAdEnabled':False}

    def export_report(self, minimum_events=20, campaign_id=None):
        """Advertiser export excludes small buckets; the owner retains finance totals."""
        report = self.dashboard()
        if campaign_id is not None:
            identifier(campaign_id)
            selected=[c for c in report['campaigns'] if c['id']==campaign_id]
            if not selected: raise AdsError('campaign-not-found')
            report['commercialRevenueMicros']=sum(c['spent']-c['credits'] for c in selected) if self.mode=='live' else 0
        buckets = {}
        for row in report['aggregates']:
            if campaign_id is not None and row['campaign_id']!=campaign_id: continue
            key = (row['day'],row['campaign_id'],row['placement'])
            buckets.setdefault(key,{})[row['metric']] = row['value']
        rows = [dict(day=d,campaignId=c,placement=p,counts=counts) for (d,c,p),counts in buckets.items()
                if c != '-' and counts.get('render',0) >= max(20,minimum_events)]
        return {'fixture':self.mode=='test','campaignId':campaign_id,'commercialRevenueMicros':report['commercialRevenueMicros'],'minimumBucketSize':max(20,minimum_events),
                'suppressedBuckets':len(buckets)-len(rows),'rows':rows}
