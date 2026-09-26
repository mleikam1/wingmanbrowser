"""Separate first-party advertiser/operator UI; no consumer gateway admin routes."""
from datetime import datetime,timezone
from decimal import Decimal,InvalidOperation
import base64
import hashlib
import hmac
from html import escape
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
import json
import re
import secrets
import threading
from urllib.parse import parse_qs,urlsplit

from .common import AdsError,encode,identifier,integer,now_seconds,text

COOKIE='wingman_operator_session'

def set_password(store,password):
    if not isinstance(password,str) or not 16<=len(password)<=256: raise AdsError('password-must-be-16-to-256-characters')
    salt=secrets.token_bytes(32)
    digest=hashlib.scrypt(password.encode(),salt=salt,n=16384,r=8,p=1)
    with store.transaction() as db:
        db.execute('INSERT INTO operator_auth VALUES(1,?,?) ON CONFLICT(id) DO UPDATE SET salt=excluded.salt,digest=excluded.digest',
            (salt.hex(),digest.hex()))
        store.audit(db,'owner','operator-password-set','owner')

def dollars(value):
    try:
        value=Decimal(value)
        micros=value*1000000
        if not value.is_finite() or value<=0 or micros!=micros.to_integral_value(): raise ValueError()
        return integer(int(micros),1)
    except (InvalidOperation,ValueError,TypeError): raise AdsError('enter-positive-usd-with-at-most-six-decimals') from None

def money(value): return '$'+format(Decimal(value)/1000000,'.6f').rstrip('0').rstrip('.')
def e(value): return escape(str(value),quote=True)
def field(name,label,value='',kind='text',required=True):
    return f'<label>{e(label)}<input name="{e(name)}" type="{e(kind)}" value="{e(value)}" '+('required ' if required else '')+'maxlength="2048"></label>'
def hidden(name,value): return f'<input type="hidden" name="{e(name)}" value="{e(value)}">'
def select(name,label,choices,selected=''):
    return f'<label>{e(label)}<select name="{e(name)}">'+''.join(f'<option value="{e(value)}" '+('selected ' if value==selected else '')+f'>{e(label)}</option>' for value,label in choices)+'</select></label>'

def readable_report(value):
    def label(key): return re.sub(r'(?<!^)(?=[A-Z])',' ',str(key)).replace('Micros','USD').replace('_',' ').capitalize()
    if isinstance(value,dict):
        scalar={k:v for k,v in value.items() if not isinstance(v,(dict,list))}
        result='<table><tr><th>Measure</th><th>Value</th></tr>'
        for key,item in scalar.items():
            shown='Not supplied / unverified' if item is None else ('Yes' if item else 'No') if type(item) is bool else money(Decimal(str(item))) if key.endswith('Micros') else str(item)
            result+='<tr><td>'+e(label(key))+'</td><td>'+e(shown)+'</td></tr>'
        result+='</table>'
        for key,item in value.items():
            if isinstance(item,(dict,list)): result+='<details><summary>'+e(label(key))+'</summary>'+readable_report(item)+'</details>'
        return result
    if isinstance(value,list): return '<ul>'+''.join('<li>'+readable_report(v)+'</li>' for v in value)+'</ul>'
    return e(value)

class OperatorApp:
    def __init__(self,service,origin,*,search_report=None,costs=None,finance_summary=None,clock=now_seconds):
        self.service,self.store,self.origin=service,service.store,origin.rstrip('/')
        parsed=urlsplit(self.origin)
        if parsed.path or parsed.query or parsed.fragment or parsed.username or parsed.password: raise AdsError('invalid-operator-origin')
        if self.store.mode=='test':
            if parsed.scheme!='http' or parsed.hostname!='127.0.0.1': raise AdsError('fixture-operator-is-loopback-only')
        elif self.store.authorize_live()['productionOrigin']!=self.origin: raise AdsError('operator-origin-not-approved')
        self.host=parsed.netloc
        self.secure=parsed.scheme=='https'
        self.clock,self.search_report,self.costs=clock,search_report,costs
        self.finance_summary=finance_summary
        self.sessions={}
        self.login_attempts=[]
        self.lock=threading.Lock()

    def session(self,cookie,create=False):
        now=self.clock()
        with self.lock:
            self.sessions={key:value for key,value in self.sessions.items() if value['expires']>now}
            try:
                parsed=SimpleCookie();parsed.load(cookie or '')
                sid=parsed[COOKIE].value if COOKIE in parsed else None
            except Exception: sid=None
            if sid in self.sessions: return sid,self.sessions[sid]
            if not create: return None,None
            if len(self.sessions)>=128: raise AdsError('operator-session-capacity')
            sid=secrets.token_hex(32)
            value={'csrf':secrets.token_hex(32),'authenticated':False,'expires':now+900}
            self.sessions[sid]=value
            return sid,value

    def authenticate(self,sid,password):
        now=self.clock()
        with self.lock:
            self.login_attempts=[v for v in self.login_attempts if v>now-60]
            if len(self.login_attempts)>=10: raise AdsError('login-rate-limit')
            self.login_attempts.append(now)
        if not isinstance(password,str) or len(password)>256: raise AdsError('login-failed')
        with self.store.transaction() as db:
            row=db.execute('SELECT * FROM operator_auth WHERE id=1').fetchone()
            salt=bytes.fromhex(row['salt']) if row else b'\0'*32
            expected=bytes.fromhex(row['digest']) if row else b'\0'*64
            actual=hashlib.scrypt(password.encode(),salt=salt,n=16384,r=8,p=1)
            if row is None or not hmac.compare_digest(actual,expected): raise AdsError('login-failed')
            self.store.audit(db,'owner','operator-login','owner')
        with self.lock:
            self.sessions.pop(sid,None)
            new=secrets.token_hex(32)
            value={'csrf':secrets.token_hex(32),'authenticated':True,'expires':now+900,'credentialVersion':row['salt']}
            self.sessions[new]=value
            return new,value

    def form(self,csrf,action,body,label):
        return '<form method="post" action="/admin/action">'+hidden('csrf',csrf)+hidden('action',action)+body+f'<button>{e(label)}</button></form>'

    def page(self,title,body,session):
        auth=session and session['authenticated']
        nav='<a href="/">Advertise</a> <a href="/admin">Operator</a> <a href="/calculator">Scenarios</a>'
        if auth: nav+='<form method="post" action="/logout">'+hidden('csrf',session['csrf'])+'<button>Log out</button></form>'
        mode='FIXTURE · test money only · commercial revenue $0' if self.store.mode=='test' else 'Approved direct pilot · manual reconciliation required'
        return ('<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
            f'<title>{e(title)} · Wingman</title><style>body{{font:16px system-ui;margin:auto;max-width:1050px;padding:24px;background:#f5f6fa;color:#182635}}'
            'nav{display:flex;gap:20px;align-items:center;flex-wrap:wrap}a{color:#175579}h1{font-size:36px}h2{margin-top:32px}section,article,form{background:white;border:1px solid #cad3df;border-radius:10px;padding:18px;margin:16px 0}'
            'nav form{padding:0;margin:0;border:0;background:none}label{display:block;margin:12px 0;font-weight:600}input,select,textarea{display:block;width:100%;box-sizing:border-box;padding:10px;margin:5px 0;border:1px solid #9baabc;border-radius:5px;font:inherit}input[type=checkbox]{width:auto;display:inline}'
            'button{background:#175579;color:white;border:0;border-radius:6px;padding:12px 18px;font:inherit;cursor:pointer}table{width:100%;border-collapse:collapse}td,th{text-align:left;border-bottom:1px solid #dae0e8;padding:10px}.badge{font-size:13px;font-weight:700}.muted{color:#536171}pre{white-space:pre-wrap;overflow-wrap:anywhere}.error{color:#9b2525}img{max-width:100%;max-height:250px}small{display:block}</style>'
            f'<body><nav>{nav}</nav><p class="badge">{e(mode)}</p><h1>{e(title)}</h1>{body}<footer><p class="muted">No consumer queries, browsing histories, IP profiles or cross-site identifiers appear in these records.</p></footer></body></html>')

    def public(self,session):
        return self.page('Sponsor useful moments in Wingman',
            '<p>Contextual sponsored search, a static New Tab sponsor, and limited Sponsored news cards. No behavioral profiles, third-party tracking pixels or advertiser scripts.</p>'
            '<section><h2>The paid pilot is not yet open</h2><p>Verified traffic and available inventory have not been established. No audience size, delivery date, conversion performance or unique reach is promised.</p></section>'
            '<h2>How review works</h2><p>We review advertiser identity, destination, creative, content category, contract and funding before any delivery. Private, student, managed, sensitive-help, health and financial-distress contexts are excluded. Organic ranking and browser protection cannot be purchased.</p>'
            '<p>Reporting covers aggregate delivered impressions, valid deliberate clicks and earned charges. Small buckets are withheld. We do not provide queries, individual conversions, device IDs or browsing paths.</p>'
            '<h2>Register an inquiry</h2><p>This form creates a business inquiry, not an agreement or payment. Provide business contact information only; do not include card details or sensitive personal information.</p>'
            '<form method="post" action="/apply">'+hidden('csrf',session['csrf'])+field('name','Business name')+field('domain','Business website domain (example.org)')+
            field('contact','Business contact email',kind='email')+'<label>Offer and requested placement<textarea name="offer" maxlength="1000" required></textarea></label><button>Submit inquiry</button></form>',session)

    def admin(self,session):
        from .finance import dashboard_finance
        report=self.store.dashboard()
        search=self.search_report() if callable(self.search_report) else self.search_report
        costs=self.costs() if callable(self.costs) else self.costs
        if self.finance_summary:
            combined=self.finance_summary()
            search,costs=combined['searchReport'],combined['costs']
        finance=dashboard_finance(report,search,costs)
        with self.store.transaction() as db:
            applications=[dict(r) for r in db.execute("SELECT * FROM applications WHERE status='pending' ORDER BY created DESC")]
            advertisers=[dict(r) for r in db.execute('SELECT * FROM advertisers')]
            audit=[dict(r) for r in db.execute('SELECT * FROM audit ORDER BY id DESC LIMIT 40')]
            entries=[dict(r) for r in db.execute('SELECT * FROM business_entries ORDER BY id DESC LIMIT 40')]
        csrf=session['csrf']
        body='<p><a href="/campaign">Create campaign</a> · <a href="/report">Download privacy-limited aggregate report</a></p>'
        body+='<h2>Finance and source definitions</h2><p>Prepayment is liability until valid delivery. Missing provider or operating cost is unknown, never zero. Test campaigns contribute zero commercial revenue.</p>'+readable_report(finance)
        body+='<h2>Campaigns</h2><table><tr><th>Creative / state</th><th>Cash / earned / reserved</th><th>Manage</th></tr>'
        for c in report['campaigns']:
            body+=f'<tr><td>{e(c["config"]["headline"])}<small>{e(c["status"])} · {e(c["config"]["billingType"].upper())}</small></td><td>{money(c["cash_received"])} / {money(c["spent"]-c["credits"])} / {money(c["reserved"])}</td><td><a href="/campaign?id={e(c["id"])}">Review / preview</a></td></tr>'
        body+='</table><h2>Advertiser and domain review</h2>'
        for a in advertisers:
            body+=f'<article><strong>{e(a["name"])}</strong><p>{e(a["domain"])} · {e(a["contact"])} · '+('Approved' if a['approved'] else 'Review required')+'</p>'
            if not a['approved']: body+=self.form(csrf,'approve-advertiser',hidden('id',a['id'])+'<label><input type="checkbox" name="reviewed" value="yes" required> I checked business identity, domain ownership and offer.</label>','Approve identity/domain')
            body+='</article>'
        body+=self.form(csrf,'create-advertiser',field('name','Business name')+field('domain','Approved-domain candidate')+field('contact','Business contact'),'Add advertiser for review')
        body+='<h2>Pending inquiries</h2>'
        for a in applications:
            body+='<article><strong>'+e(a['name'])+'</strong><p>'+e(a['domain'])+' · '+e(a['contact'])+'</p><p>'+e(a['offer'])+'</p>'
            body+=self.form(csrf,'review-application',hidden('id',a['id'])+select('decision','Decision',[('accept','Accept for identity review'),('decline','Decline')]),'Record decision')+'</article>'
        body+='<h2>Manual invoice and reconciliation records</h2><p>Records require external evidence. These controls do not collect or move money. A chargeback pauses delivery and records a disputed receivable if cash was already earned.</p><pre>'+e(json.dumps(entries,indent=2))+'</pre>'
        body+='<h2>Operator audit</h2><pre>'+e(json.dumps(audit,indent=2))+'</pre>'
        return self.page('Campaign operations',body,session)

    def campaign(self,session,entity=None):
        with self.store.transaction() as db:
            advertisers=[dict(r) for r in db.execute('SELECT * FROM advertisers')]
            campaign=self.store.campaign(db,entity) if entity else None
        c=campaign['config'] if campaign else dict(headline='',body='',landingUrl='',placements=['search'],country='US',language='en',targets=['office'],negativeTargets=[],billingType='cpc',currency='USD',rateMicros=500000,budgetMicros=500000000,dailyBudgetMicros=10000000,impressionCap=1000,clickCap=1000,guaranteedImpressions=0,exclusive=False,agreementReference='',assetId=None,qualityScore=1,startsAt=self.clock(),endsAt=self.clock()+7*86400)
        csrf=session['csrf']
        body='<p>Changes invalidate issued tokens and require renewed review. Mandatory destination/content restrictions cannot be lowered here. Review expires after 24 hours; recheck the destination before reapproval.</p>'
        if campaign:
            body+=f'<p><a href="/report?campaignId={e(entity)}">Download this campaign’s privacy-limited report</a></p>'
            body+=f'<article><p class="badge">Sponsored · preview · no billable event</p><h2>{e(c["headline"])}</h2><p>{e(c["body"])}</p><p>{e(campaign["advertiser"])} · {e(c["landingUrl"])}</p>'
            if c['assetId']: body+=f'<img src="/asset?id={e(c["assetId"])}" alt="Reviewed campaign raster preview">'
            body+='<small>Why this ad? Current nonsensitive context, without browsing history or a user profile. An actual click visits the advertiser with ordinary website connection information.</small></article>'
        form=hidden('id',entity or '')+select('advertiser','Advertiser',[(a['id'],a['name']) for a in advertisers],campaign['advertiser_id'] if campaign else '')
        form+=field('headline','Headline',c['headline'])+'<label>Body<textarea name="body" maxlength="300">'+e(c['body'])+'</textarea></label>'+field('landingUrl','HTTPS destination on approved exact domain',c['landingUrl'],kind='url')
        form+=field('placements','Placements, comma separated: search, newtab, news',','.join(c['placements']))+field('targets','Reviewed contexts, comma separated',','.join(c['targets']))+field('negativeTargets','Excluded reviewed contexts',','.join(c['negativeTargets']),required=False)
        form+='<p>Allowed contexts: office, productivity, learning, outdoors, security-tools; news science, technology, arts; New Tab untargeted. Sensitive targeting is unavailable.</p>'
        form+=field('country','Country US/GB/CA/AU/DE/FR/ES',c['country'])+field('language','Language en/de/fr/es',c['language'])
        for key,label in [('startsAt','Starts at UTC'),('endsAt','Ends at UTC')]: form+=field(key,label,datetime.fromtimestamp(c[key],timezone.utc).strftime('%Y-%m-%dT%H:%M'),kind='datetime-local')
        form+=select('billingType','Fixed rate billing',[('cpc','Per valid deliberate click'),('cpm','Per 1,000 qualified visible impressions')],c['billingType'])+field('currency','Currency (USD only)','USD')
        for key,label in [('rateMicros','Rate in USD (CPC or CPM)'),('budgetMicros','Total spend cap USD'),('dailyBudgetMicros','Daily spend cap USD')]: form+=field(key,label,str(Decimal(c[key])/1000000))
        for key,label in [('impressionCap','Qualified impression cap'),('clickCap','Valid click cap'),('guaranteedImpressions','Guaranteed CPM impressions (0 without a guarantee)'),('qualityScore','Reviewed quality (1–3)')]: form+=field(key,label,c[key],kind='number')
        form+=field('agreementReference','External agreement reference',c['agreementReference'])+field('assetId','Reviewed asset SHA256 (optional)',c['assetId'] or '',required=False)+select('exclusive','Exclusive inventory',[('no','No'),('yes','Yes')],'yes' if c['exclusive'] else 'no')
        body+=self.form(csrf,'save-campaign',form,'Save draft for review')
        if campaign:
            body+=self.form(csrf,'approve-campaign',hidden('id',entity)+field('reference','Manual review evidence reference')+'<label><input type="checkbox" name="reviewed" value="yes" required> I verified destination, offer, creative, contract and available inventory.</label>','Approve for 24 hours')
            body+=self.form(csrf,'pause-campaign',hidden('id',entity),'Pause / quarantine campaign now')
            body+=self.form(csrf,'finance',hidden('id',entity)+select('kind','Business record',[(v,v) for v in ('invoice','receipt','credit','refund','payment-fee','partner-share','chargeback')])+field('amount','Amount USD')+field('operationKey','Unique operation / idempotency reference')+field('reference','External invoice, bank or dispute evidence reference'),'Record manual reconciliation')
        body+=self.form(csrf,'asset','<p>Text is supported directly. Raster upload accepts PNG/JPEG bytes encoded as base64, max 256 KB; metadata is stripped and output is first-party PNG. No SVG, scripts, URLs or animation.</p><label>Base64 raster bytes<textarea name="raster" maxlength="350000" required></textarea></label>','Sanitize raster for review')
        return self.page('Review campaign' if campaign else 'Create campaign',body,session)

    def action(self,raw):
        action=raw.pop('action',None)
        raw.pop('csrf',None)
        if action=='create-advertiser':
            self.store.create_advertiser(**raw)
        elif action=='approve-advertiser':
            if raw.get('reviewed')!='yes': raise AdsError('manual-review-required')
            self.store.approve_advertiser(raw['id'])
        elif action=='review-application':
            if raw.get('decision') not in {'accept','decline'}: raise AdsError('invalid-decision')
            self.store.review_application(raw['id'],approve=raw['decision']=='accept')
        elif action=='save-campaign':
            entity,advertiser=raw.pop('id'),raw.pop('advertiser')
            c=dict(raw)
            for key in ('placements','targets','negativeTargets'): c[key]=[v.strip() for v in c[key].split(',') if v.strip()]
            for key in ('rateMicros','budgetMicros','dailyBudgetMicros'): c[key]=dollars(c[key])
            for key in ('impressionCap','clickCap','guaranteedImpressions','qualityScore'): c[key]=int(c[key])
            for key in ('startsAt','endsAt'): c[key]=int(datetime.fromisoformat(c[key]).replace(tzinfo=timezone.utc).timestamp())
            if c['exclusive'] not in {'yes','no'}: raise AdsError('invalid-exclusivity')
            c['exclusive']=c['exclusive']=='yes';c['assetId']=c['assetId'] or None
            if entity: self.store.update_campaign(entity,c)
            else: entity=self.store.create_campaign(advertiser,c)
            return '/campaign?id='+identifier(entity)
        elif action=='approve-campaign':
            if raw.get('reviewed')!='yes': raise AdsError('manual-review-required')
            self.store.approve_campaign(raw['id'],review_reference=raw['reference'])
        elif action=='pause-campaign': self.store.pause_campaign(raw['id'])
        elif action=='finance': self.store.business_entry(raw['id'],kind=raw['kind'],amount_micros=dollars(raw['amount']),operation_key=raw['operationKey'],reference=raw['reference'])
        elif action=='asset':
            try: data=base64.b64decode(raw['raster'],validate=True)
            except Exception: raise AdsError('invalid-raster') from None
            return '/asset-added?id='+self.store.add_asset(data)
        else: raise AdsError('unknown-operator-action')
        return '/admin'

    def calculator(self,session,result=None):
        body='<p>Explicit scenarios, not predicted results. No value below is measured Wingman income. Supply every assumption; net click amount must already include expected revenue deductions.</p>'
        body+='<form method="post" action="/calculator">'+hidden('csrf',session['csrf'])
        assumptions=result['assumptions'] if result else {'k':'1.05','c':'5','v':'1.25'}
        for key,label in [('f','Fraction of all submitted searches receiving one billable-quality opportunity'),('t','Valid click rate among those opportunities'),('p','Net earned USD per valid click'),('k','Paid provider calls per submitted search, including retries/failures (illustrative starting value)'),('c','Provider USD per 1,000 calls (illustrative starting value)'),('v','Other variable USD per 1,000 submitted searches (illustrative starting value)')]: body+=field(key,label,assumptions.get(key,''))
        body+='<button>Calculate scenario</button></form>'
        if result is not None: body+=readable_report(result)
        return self.page('Contribution scenario calculator',body,session)

def create_server(service,port=8896,*,origin=None,search_report=None,costs=None,finance_summary=None):
    # A reverse proxy for an explicitly approved live origin may reach this loopback
    # server. Untrusted forwarding headers never establish authentication or origin.
    origin=origin or 'http://127.0.0.1:'+str(port)
    app=OperatorApp(service,origin,search_report=search_report,costs=costs,finance_summary=finance_summary)
    class Handler(BaseHTTPRequestHandler):
        server_version='WingmanOperator'
        def log_message(self,*args): pass
        def setup(self):
            super().setup();self.connection.settimeout(5)
        def send(self,status,body='',*,kind='text/html; charset=utf-8',cookie=None,location=None):
            body=body.encode() if isinstance(body,str) else body
            self.send_response(status)
            self.send_header('Content-Type',kind);self.send_header('Content-Length',str(len(body)))
            # Same-origin keeps Safari form Origin verifiable while suppressing
            # all cross-origin referrers. Merchant/ad navigation remains no-referrer.
            for k,v in {'Cache-Control':'no-store','Referrer-Policy':'same-origin','X-Content-Type-Options':'nosniff','X-Frame-Options':'DENY',
                'Content-Security-Policy':"default-src 'none'; style-src 'unsafe-inline'; img-src 'self'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'"}.items(): self.send_header(k,v)
            if cookie: self.send_header('Set-Cookie',COOKIE+'='+cookie+'; Path=/; HttpOnly; SameSite=Strict; Max-Age=900'+('; Secure' if app.secure else ''))
            if location: self.send_header('Location',location)
            self.end_headers()
            if self.command!='HEAD': self.wfile.write(body)
        def route(self):
            try:
                if self.headers.get_all('Host')!=[app.host] or len(self.headers)>40: raise AdsError('invalid-host')
                if len(self.path)>2048 or self.headers.get('Transfer-Encoding'): raise AdsError('invalid-request')
                path=urlsplit(self.path)
                if path.scheme or path.netloc or path.fragment: raise AdsError('invalid-path')
                query=parse_qs(path.query,strict_parsing=True)
                if any(len(v)!=1 for v in query.values()): raise AdsError('invalid-parameters')
                sid,session=app.session(self.headers.get('Cookie'),create=True)
                authenticated=session['authenticated']
                if authenticated:
                    with app.store.transaction() as db:
                        current=db.execute('SELECT salt FROM operator_auth WHERE id=1').fetchone()
                    if current is None or current['salt']!=session.get('credentialVersion'):
                        with app.lock: app.sessions.pop(sid,None)
                        self.send(303,location='/login',cookie='expired');return
                if self.command in {'GET','HEAD'}:
                    if path.path=='/': self.send(200,app.public(session),cookie=sid)
                    elif path.path=='/login': self.send(200,app.page('Operator sign in','<form method="post" action="/login">'+hidden('csrf',session['csrf'])+field('password','Operator password',kind='password')+'<button>Sign in</button></form>',session),cookie=sid)
                    elif not authenticated: self.send(303,location='/login',cookie=sid)
                    elif path.path=='/admin': self.send(200,app.admin(session),cookie=sid)
                    elif path.path=='/campaign': self.send(200,app.campaign(session,query.get('id',[None])[0]),cookie=sid)
                    elif path.path=='/calculator': self.send(200,app.calculator(session),cookie=sid)
                    elif path.path=='/report': self.send(200,encode(app.store.export_report(campaign_id=query.get('campaignId',[None])[0])),kind='application/json')
                    elif path.path=='/asset':
                        asset=identifier(query['id'][0])
                        with app.store.transaction() as db: row=db.execute('SELECT body,mime FROM assets WHERE id=?',(asset,)).fetchone()
                        if not row: raise AdsError('asset-unavailable')
                        self.send(200,bytes(row['body']),kind='image/png')
                    elif path.path=='/asset-added': self.send(200,app.page('Raster sanitized','<p>Copy this asset ID into a draft campaign; approval is still required.</p><pre>'+e(identifier(query['id'][0]))+'</pre>',session),cookie=sid)
                    else: self.send(404,'Not found')
                    return
                if self.command!='POST': self.send(405,'Method not allowed');return
                if self.headers.get_all('Origin')!=[app.origin]: raise AdsError('same-origin-required')
                if self.headers.get_content_type()!='application/x-www-form-urlencoded': raise AdsError('form-content-type-required')
                lengths=self.headers.get_all('Content-Length')
                if not lengths or len(lengths)!=1 or not lengths[0].isdigit(): raise AdsError('invalid-body-length')
                length=int(lengths[0])
                if not 1<=length<=370000: raise AdsError('invalid-body-length')
                data=self.rfile.read(length)
                if len(data)!=length: raise AdsError('invalid-body-length')
                pairs=parse_qs(data.decode('utf-8'),keep_blank_values=True,strict_parsing=True,max_num_fields=40)
                if any(len(v)!=1 for v in pairs.values()): raise AdsError('duplicate-form-field')
                raw={key:values[0] for key,values in pairs.items()}
                if not hmac.compare_digest(raw.get('csrf',''),session['csrf']): raise AdsError('csrf-required')
                if path.path=='/login':
                    sid,session=app.authenticate(sid,raw.get('password',''));self.send(303,location='/admin',cookie=sid)
                elif path.path=='/apply':
                    if set(raw)!={'csrf','name','domain','contact','offer'}: raise AdsError('invalid-application')
                    raw.pop('csrf');app.store.apply(**raw)
                    self.send(200,app.page('Inquiry recorded','<p>Your business inquiry is saved for owner review. No agreement was accepted and no payment was taken. The paid pilot is not yet open.</p>',session),cookie=sid)
                elif not authenticated: self.send(403,'Operator sign in required')
                elif path.path=='/logout':
                    with app.lock: app.sessions.pop(sid,None)
                    self.send(303,location='/login',cookie='expired')
                elif path.path=='/admin/action': self.send(303,location=app.action(raw),cookie=sid)
                elif path.path=='/calculator':
                    from .finance import scenario
                    raw.pop('csrf');self.send(200,app.calculator(session,scenario(raw)),cookie=sid)
                else: self.send(404,'Not found')
            except (AdsError,ValueError,TypeError,KeyError,UnicodeError):
                self.send(400,'Request rejected. Check the form, review state and authorization; no unsafe input is echoed.')
            except Exception:
                self.send(503,'Operator service unavailable. Preserve the ledger and inspect local health.')
        do_GET=route;do_HEAD=route;do_POST=route;do_PUT=route;do_DELETE=route
    class Server(ThreadingHTTPServer):
        daemon_threads=True
        def __init__(self,*args): self.slots=threading.BoundedSemaphore(8);super().__init__(*args)
        def process_request(self,request,address):
            if not self.slots.acquire(blocking=False): self.close_request(request);return
            try: super().process_request(request,address)
            except Exception: self.slots.release();raise
        def process_request_thread(self,*args):
            try: super().process_request_thread(*args)
            finally: self.slots.release()
        def service_actions(self):
            now=app.clock()
            with app.lock:
                app.sessions={key:value for key,value in app.sessions.items() if value['expires']>now}
        def server_close(self): super().server_close();service.close()
    server=Server(('127.0.0.1',port),Handler)
    if port==0 and service.fixture:
        app.origin='http://127.0.0.1:'+str(server.server_port);app.host='127.0.0.1:'+str(server.server_port)
    server.app=app
    return server
