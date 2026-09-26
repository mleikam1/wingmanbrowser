"""Loopback HTTP tests, isolated fixture ledger, no provider or payment calls."""
import base64
from http.client import HTTPConnection
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import threading
import unittest
from urllib.parse import urlencode

from wingman_ads import AdsStore,AdsService,AdsError
from wingman_ads.operator import create_server,set_password

REPO=Path(__file__).resolve().parents[2]
PASSWORD='fixture-only-long-local-password'

class AdsOperatorTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(dir=REPO/'work')
        self.store=AdsStore.initialize(Path(self.temp.name)/'ads.sqlite3')
        self.service=AdsService(self.store,sweep=False)
        set_password(self.store,PASSWORD)
        self.server=create_server(self.service,port=0)
        self.thread=threading.Thread(target=self.server.serve_forever,daemon=True)
        self.thread.start()
        self.origin=self.server.app.origin
        self.cookie=None;self.csrf=None
    def tearDown(self):
        self.server.shutdown();self.server.server_close();self.thread.join(timeout=2);self.temp.cleanup()
    def request(self,path='/',method='GET',raw=None,headers=None):
        connection=HTTPConnection('127.0.0.1',self.server.server_port,timeout=5)
        selected={}
        if self.cookie:selected['Cookie']=self.cookie
        body=None
        if raw is not None:
            body=urlencode(raw);selected.update({'Content-Type':'application/x-www-form-urlencoded','Origin':self.origin})
        selected.update(headers or {})
        connection.request(method,path,body,selected)
        response=connection.getresponse()
        payload=response.read().decode('utf-8')
        status=response.status;result=dict(response.getheaders())
        connection.close()
        if 'Set-Cookie' in result:self.cookie=result['Set-Cookie'].split(';')[0]
        found=re.search(r'name="csrf" value="([a-f0-9]+)"',payload)
        if found:self.csrf=found[1]
        return status,payload,result
    def login(self):
        self.assertEqual(200,self.request('/login')[0])
        self.assertEqual(303,self.request('/login','POST',{'csrf':self.csrf,'password':PASSWORD})[0])
        self.request('/campaign')
    def action(self,action,**fields):
        return self.request('/admin/action','POST',dict(fields,action=action,csrf=self.csrf))

    def test_public_truthful_intake_and_no_admin_anonymous(self):
        status,body,headers=self.request()
        self.assertEqual(200,status)
        self.assertIn('paid pilot is not yet open',body)
        self.assertIn('commercial revenue $0',body)
        self.assertEqual('same-origin',headers['Referrer-Policy'])
        self.assertIn('HttpOnly',headers['Set-Cookie'])
        self.assertIn('SameSite=Strict',headers['Set-Cookie'])
        self.assertEqual(303,self.request('/admin')[0])
        self.assertEqual(200,self.request('/apply','POST',dict(csrf=self.csrf,name='Applicant',domain='example.org',contact='business@example.org',offer='Office tools'))[0])
        with self.store.transaction() as db:
            self.assertEqual(1,db.execute('SELECT COUNT(*) FROM applications').fetchone()[0])
            self.assertEqual(0,db.execute('SELECT COUNT(*) FROM advertisers').fetchone()[0])
        self.assertEqual(0,self.store.dashboard()['commercialCashMicros'])

    def test_password_hash_rotation_and_session_fixation(self):
        self.request('/login');old=self.cookie
        self.assertEqual(400,self.request('/login','POST',dict(csrf=self.csrf,password='wrong'))[0])
        self.login();self.assertNotEqual(old,self.cookie)
        self.assertEqual(200,self.request('/campaign')[0])
        with self.store.transaction() as db:
            row=db.execute('SELECT * FROM operator_auth').fetchone()
            self.assertNotIn(PASSWORD,row['digest']);self.assertEqual(128,len(row['digest']))
        set_password(self.store,'another-fixture-long-password')
        self.assertEqual(303,self.request('/campaign')[0])

    def test_csrf_origin_host_and_get_cannot_mutate(self):
        self.login()
        fields=dict(action='create-advertiser',name='Test',domain='example.org',contact='business@example.org')
        self.assertEqual(400,self.request('/admin/action','POST',fields)[0])
        self.assertEqual(400,self.request('/admin/action','POST',dict(fields,csrf=self.csrf),headers={'Origin':'https://attacker.example'})[0])
        self.assertEqual(400,self.request('/',headers={'Host':'attacker.example'})[0])
        self.assertEqual(404,self.request('/admin/action?action=create-advertiser')[0])
        self.assertEqual(404,self.request('/admin/action?action=create-advertiser','HEAD')[0])
        with self.store.transaction() as db:self.assertEqual(0,db.execute('SELECT COUNT(*) FROM advertisers').fetchone()[0])

    def test_complete_direct_operator_invoice_receipt_review_pause_workflow(self):
        self.login()
        self.assertEqual(303,self.action('create-advertiser',name='Fixture Sponsor',domain='example.org',contact='fixture@example.org')[0])
        with self.store.transaction() as db:advertiser=db.execute('SELECT id FROM advertisers').fetchone()[0]
        self.assertEqual(303,self.action('approve-advertiser',id=advertiser,reviewed='yes')[0])
        fields=dict(id='',advertiser=advertiser,headline='Fixture tools',body='Synthetic offer',landingUrl='https://example.org/',placements='search',country='US',language='en',targets='office',negativeTargets='',billingType='cpc',currency='USD',rateMicros='0.50',budgetMicros='500',dailyBudgetMicros='10',impressionCap='1000',clickCap='1000',guaranteedImpressions='0',qualityScore='2',agreementReference='fixture-contract',assetId='',exclusive='no',startsAt='2026-01-01T00:00',endsAt='2026-12-31T00:00')
        status,body,headers=self.action('save-campaign',**fields)
        self.assertEqual(303,status)
        entity=headers['Location'].split('=')[1]
        preview=self.request('/campaign?id='+entity)
        self.assertIn('Sponsored · preview',preview[1])
        self.assertEqual(0,self.store.dashboard()['testEarnedMicros'])
        for kind in ('invoice','receipt'):
            self.assertEqual(303,self.action('finance',id=entity,kind=kind,amount='500',operationKey='fixture-'+kind,reference='fixture-bank-'+kind)[0])
        self.assertEqual(303,self.action('approve-campaign',id=entity,reference='fixture-reviewed',reviewed='yes')[0])
        grant=self.service.issue_context(intent='office',fixture=True)
        ad=self.service.decision(dict(placement='search',context='normal',foreground=True,contextToken=grant['token']))['ad']
        self.assertIsNotNone(ad)
        self.assertEqual(303,self.action('pause-campaign',id=entity)[0])
        event=self.service.event(dict(deliveryToken=ad['deliveryToken'],kind='click',foreground=True,visiblePermille=1000,visibleMs=0,explicitAction=True))
        self.assertEqual('rejected',event['status'])
        report=self.store.dashboard()
        self.assertEqual(500000000,report['testInvoicedMicros'])
        self.assertEqual(500000000,report['testCashCollectedMicros'])
        self.assertEqual(0,report['testEarnedMicros'])
        self.assertEqual(0,report['commercialRevenueMicros'])
        with self.store.transaction() as db:
            self.assertGreater(db.execute('SELECT COUNT(*) FROM audit').fetchone()[0],5)

    def test_xss_and_payment_fields_not_reflected_or_accepted(self):
        self.request()
        response=self.request('/apply','POST',dict(csrf=self.csrf,name='<script>CANARY_XSS</script>',domain='example.org',contact='contact@example.org',offer='Office'))
        self.assertEqual(400,response[0]);self.assertNotIn('CANARY_XSS',response[1])
        response=self.request('/apply','POST',dict(csrf=self.csrf,name='Name',domain='example.org',contact='contact@example.org',offer='Office',cardNumber='CANARY_CARD'))
        self.assertEqual(400,response[0]);self.assertNotIn(b'CANARY_CARD',self.store.path.read_bytes())
        self.assertEqual(400,self.request('/apply','POST',dict(csrf=self.csrf,name='Name',domain='example.org',contact='contact@example.org',offer='Office'),headers={'Content-Type':'text/plain'})[0])

    def test_idle_session_expiry_and_fixture_bind_restrictions(self):
        self.login()
        self.server.app.clock=lambda:10**12
        self.assertEqual(303,self.request('/campaign')[0])
        from wingman_ads.operator import OperatorApp
        with self.assertRaises(AdsError):OperatorApp(self.service,'http://0.0.0.0:8896')
        with self.assertRaises(AdsError):OperatorApp(self.service,'https://ads.example.org')

    def test_noninteractive_password_entry_refuses_echo_and_dashboard_calculator_render(self):
        result=subprocess.run([sys.executable,'-m','wingman_ads','set-password','--store',str(self.store.path)],
            input='DO_NOT_ECHO_FIXTURE_INPUT',text=True,capture_output=True,cwd=REPO)
        self.assertEqual(2,result.returncode)
        self.assertNotIn('DO_NOT_ECHO_FIXTURE_INPUT',result.stdout+result.stderr)
        self.assertIn('hidden-interactive-terminal-required',result.stderr)
        self.login()
        status,body,_=self.request('/admin')
        self.assertEqual(200,status);self.assertIn('Not supplied / unverified',body)
        status,body,_=self.request('/calculator','POST',dict(csrf=self.csrf,f='.5',t='.03',p='.6',k='1.05',c='5',v='1.25'))
        self.assertEqual(200,status)
        self.assertIn('Contribution per1000 searches',body)
        self.assertIn('<td>2.5</td>',body)
        self.assertIn('value="0.5"',body)

if __name__=='__main__':unittest.main()
