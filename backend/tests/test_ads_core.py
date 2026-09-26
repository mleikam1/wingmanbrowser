"""Synthetic money and local fixtures only; no provider, merchant or payment I/O."""
from concurrent.futures import ThreadPoolExecutor
import io
import json
import os
from pathlib import Path
import secrets
import tempfile
import unittest

from wingman_ads import AdsStore, AdsService, AdsError

REPO=Path(__file__).resolve().parents[2]

class AdsCoreTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(dir=REPO/'work')
        self.path=Path(self.temp.name)/'ads.sqlite3'
        self.now=1_790_380_800
        self.store=AdsStore.initialize(self.path,clock=lambda:self.now)
        self.service=AdsService(self.store,sweep=False)
        self.advertiser=self.store.create_advertiser(name='Fixture Sponsor',domain='example.org',contact='fixture@example.org')
        self.store.approve_advertiser(self.advertiser)
    def tearDown(self):
        self.service.close()
        self.temp.cleanup()
    def config(self,**changes):
        value=dict(headline='Fixture office tools',body='Synthetic example',landingUrl='https://example.org/',
            placements=['search','newtab','news'],country='US',language='en',targets=['office','untargeted','science'],
            negativeTargets=[],startsAt=self.now-100,endsAt=self.now+86400,billingType='cpc',rateMicros=500000,
            budgetMicros=5000000,dailyBudgetMicros=5000000,impressionCap=100,clickCap=100,
            agreementReference='fixture-agreement',guaranteedImpressions=0,exclusive=False,assetId=None,qualityScore=2,currency='USD')
        return dict(value,**changes)
    def campaign(self,*,funds=5000000,**changes):
        entity=self.store.create_campaign(self.advertiser,self.config(**changes))
        self.store.business_entry(entity,kind='receipt',amount_micros=funds,operation_key='receipt-'+entity,reference='fixture-payment')
        self.store.approve_campaign(entity,review_reference='fixture-review')
        return entity
    def decision(self,**changes):
        grant=self.service.issue_context(intent='office',fixture=True)
        return self.service.decision(dict(placement='search',context='normal',foreground=True,contextToken=grant['token'],**changes))
    def event(self,ad,kind='click',**changes):
        return self.service.event(dict(dict(deliveryToken=ad['deliveryToken'],kind=kind,foreground=True,
            visiblePermille=1000,visibleMs=0,explicitAction=True),**changes))

    def test_early_deliberate_cpc_click_and_duplicate_replay(self):
        self.campaign()
        ad=self.decision()['ad']
        reply=self.event(ad)
        self.assertEqual('accepted',reply['status'])
        self.assertEqual('https://example.org/',reply['landingUrl'])
        self.assertEqual(500000,reply['testChargedMicros'])
        self.assertEqual(0,reply['chargedMicros'])
        self.assertFalse(reply['billable'])
        self.assertEqual('duplicate',self.event(ad)['status'])
        self.assertEqual(500000,self.store.dashboard()['testEarnedMicros'])

    def test_cpm_click_before_view_does_not_bill_and_actual_view_qualifies(self):
        self.campaign(billingType='cpm',rateMicros=10000000)
        ad=self.decision()['ad']
        self.assertEqual(0,self.event(ad)['testChargedMicros'])
        self.assertEqual('rejected',self.event(ad,'view',visibleMs=1000)['status'])
        self.now+=1
        self.assertEqual('rejected',self.event(ad,'view',visibleMs=999)['status'])
        self.assertEqual('rejected',self.event(ad,'view',visibleMs=1000,visiblePermille=499)['status'])
        reply=self.event(ad,'view',visibleMs=1000,visiblePermille=500)
        self.assertEqual(10000,reply['testChargedMicros'])
        self.assertEqual('duplicate',self.event(ad,'view',visibleMs=1000)['status'])

    def test_hidden_background_prefetch_and_wrong_method_never_charge(self):
        self.campaign()
        ad=self.decision()['ad']
        for fields in ({'foreground':False},{'explicitAction':False},{'visiblePermille':0}):
            self.assertEqual('rejected',self.event(ad,**fields)['status'])
        with self.assertRaises(AdsError):
            self.service.event({'deliveryToken':ad['deliveryToken'],'kind':'GET'})
        self.assertEqual(0,self.store.dashboard()['testEarnedMicros'])

    def test_forged_expired_tokens_and_rotated_keys(self):
        self.campaign()
        ad=self.decision()['ad']
        with self.assertRaises(AdsError):
            self.event(dict(ad,deliveryToken=ad['deliveryToken'][:-8]+'abcdefgh'))
        other=AdsService(self.store,secrets.token_bytes(32),sweep=False)
        with self.assertRaises(AdsError):
            other.event(dict(deliveryToken=ad['deliveryToken'],kind='click',foreground=True,visiblePermille=1000,visibleMs=0,explicitAction=True))
        other.close()
        self.now+=901
        with self.assertRaises(AdsError):self.event(ad)
        self.store.purge_expired()
        self.assertEqual(0,self.store.dashboard()['testReservedMicros'])
        with self.store.transaction() as db:
            self.assertEqual(0,db.execute('SELECT COUNT(*) FROM deliveries').fetchone()[0])

    def test_concurrent_budget_reservations_and_events_cannot_overspend(self):
        self.campaign(funds=500000,budgetMicros=500000,dailyBudgetMicros=500000)
        with ThreadPoolExecutor(max_workers=10) as pool:
            replies=list(pool.map(lambda _:self.decision(),range(20)))
        ads=[r['ad'] for r in replies if r['ad']]
        self.assertEqual(1,len(ads))
        with ThreadPoolExecutor(max_workers=10) as pool:
            events=list(pool.map(lambda _:self.event(ads[0]),range(20)))
        self.assertEqual(1,sum(r['status']=='accepted' for r in events))
        report=self.store.dashboard()
        self.assertEqual(500000,report['testEarnedMicros'])
        self.assertEqual(0,report['testPrepaidLiabilityMicros'])
        self.assertEqual(0,report['testReservedMicros'])

    def test_same_page_decision_idempotent_no_second_ad(self):
        self.campaign()
        grant=self.service.issue_context(intent='office',fixture=True)
        request=dict(placement='search',context='normal',foreground=True,contextToken=grant['token'])
        first=self.service.decision(request)
        self.assertEqual(first,self.service.decision(request))
        self.assertEqual(500000,self.store.dashboard()['testReservedMicros'])

    def test_pause_edits_and_review_expiry_invalidate_deliveries(self):
        entity=self.campaign()
        ad=self.decision()['ad']
        self.store.pause_campaign(entity)
        self.assertEqual('rejected',self.event(ad)['status'])
        self.store.approve_campaign(entity,review_reference='fixture-new-review')
        self.assertEqual('rejected',self.event(ad)['status'])
        new=self.decision()['ad']
        self.store.update_campaign(entity,self.config(headline='Revised fixture'))
        self.assertEqual('rejected',self.event(new)['status'])
        self.assertEqual('no-fill',self.decision()['status'])

    def test_destination_change_or_new_mandatory_restriction_fails_closed(self):
        self.campaign()
        ad=self.decision()['ad']
        self.store.policy.allows_result=lambda *args:False
        self.assertEqual('rejected',self.event(ad)['status'])
        self.assertEqual(0,self.store.dashboard()['testReservedMicros'])

    def test_private_managed_sensitive_and_fixture_live_segregation(self):
        self.campaign()
        for context in ('private','managed'):
            self.assertIsNone(self.service.issue_context(intent='office',context=context,fixture=True))
            self.assertEqual('no-fill',self.service.decision(dict(placement='search',context=context,foreground=True))['status'])
        self.assertIsNone(self.service.issue_context(intent='debt',fixture=True))
        self.assertIsNone(self.service.issue_context(intent='office',fixture=False))
        with self.assertRaises(AdsError):AdsService(self.store,environment='single-durable-host',live_authorized=True)
        self.assertEqual(0,self.store.dashboard()['commercialRevenueMicros'])

    def test_density_newtab_and_news_count_other_sponsored_cards(self):
        self.campaign()
        req=dict(placement='news',context='normal',foreground=True,pageId=secrets.token_hex(16),country='US',
                 language='en',section='science',organicCount=6,sponsoredCount=0,slotIndex=0)
        self.assertEqual('no-fill',self.service.decision(dict(req,organicCount=5))['status'])
        self.assertEqual('filled',self.service.decision(req)['status'])
        self.assertEqual('no-fill',self.service.decision(dict(req,organicCount=12,sponsoredCount=2,slotIndex=1))['status'])
        self.assertEqual('filled',self.service.decision(dict(req,organicCount=12,sponsoredCount=1,slotIndex=1))['status'])
        self.assertEqual('no-fill',self.service.decision(dict(req,placement='newtab',section='untargeted'))['status'])

    def test_finance_reconciliation_credit_refund_idempotency_and_reserved_funds(self):
        entity=self.campaign(funds=1000000)
        ad=self.decision()['ad']
        with self.assertRaises(AdsError):
            self.store.business_entry(entity,kind='refund',amount_micros=1000000,operation_key='refund-1',reference='invoice-1')
        self.event(ad)
        self.store.business_entry(entity,kind='credit',amount_micros=100000,operation_key='credit-1',reference='review-1')
        self.store.business_entry(entity,kind='refund',amount_micros=600000,operation_key='refund-2',reference='invoice-2')
        self.assertFalse(self.store.business_entry(entity,kind='refund',amount_micros=600000,operation_key='refund-2',reference='invoice-2'))
        with self.assertRaises(AdsError):
            self.store.business_entry(entity,kind='refund',amount_micros=1,operation_key='refund-2',reference='invoice-2')
        report=self.store.dashboard()
        self.assertEqual(report['testCashCollectedMicros'],report['testEarnedMicros']+report['testRefundedMicros']+report['testPrepaidLiabilityMicros'])
        self.assertEqual(400000,report['testEarnedMicros'])
        self.assertEqual(0,report['testPrepaidLiabilityMicros'])

    def test_campaign_policy_and_exact_money_validation(self):
        for changes in ({'headline':'<script>x</script>'},{'landingUrl':'https://example.org/?user=1'},
                        {'landingUrl':'https://evil.example/'},{'headline':'Buy casino bonus'},
                        {'billingType':'cpm','rateMicros':10001},{'rateMicros':True},{'targets':['debt']},
                        {'country':'US','language':'de'}):
            with self.subTest(changes=changes),self.assertRaises(AdsError):
                self.store.create_campaign(self.advertiser,self.config(**changes))

    def test_exclusive_inventory_not_sold_twice(self):
        self.campaign(exclusive=True)
        entity=self.store.create_campaign(self.advertiser,self.config())
        self.store.business_entry(entity,kind='receipt',amount_micros=1000000,operation_key='second',reference='fixture')
        with self.assertRaisesRegex(AdsError,'exclusive-inventory'):
            self.store.approve_campaign(entity,review_reference='fixture-review')

    def test_no_query_payload_or_arbitrary_fields_enter_ledger(self):
        self.campaign()
        grant=self.service.issue_context(intent='office',fixture=True)
        with self.assertRaises(AdsError):
            self.service.decision(dict(placement='search',context='normal',foreground=True,contextToken=grant['token'],query='CANARY_QUERY'))
        self.assertNotIn(b'CANARY_QUERY',self.path.read_bytes())
        self.assertEqual([],self.store.export_report()['rows'])
        with self.store.transaction() as db:
            for table in ('deliveries','opportunities','aggregates'):
                columns={row[1] for row in db.execute('PRAGMA table_info('+table+')')}
                self.assertFalse(columns & {'query','ip','referrer','user_id','history'})

    def test_missing_and_corrupt_ledger_cannot_reset_finance(self):
        self.campaign()
        with self.assertRaises(AdsError):AdsStore.initialize(self.path)
        self.path.unlink()
        with self.assertRaises(AdsError):AdsStore(self.path)
        with self.assertRaises(AdsError):AdsStore.initialize(self.path)

    def test_raster_reencoded_no_scripts_or_unapproved_serving(self):
        from PIL import Image
        body=io.BytesIO()
        Image.new('RGB',(300,250),'blue').save(body,format='PNG')
        asset=self.store.add_asset(body.getvalue())
        with self.assertRaises(AdsError):self.service.asset(asset)
        self.campaign(assetId=asset)
        data,mime=self.service.asset(asset)
        self.assertEqual('image/png',mime)
        self.assertTrue(data.startswith(b'\x89PNG'))
        with self.assertRaises(AdsError):self.store.add_asset(b'<svg onload="alert(1)"/>')

    def test_live_initialization_requires_separate_scoped_authorization(self):
        with self.assertRaises(AdsError):AdsStore.initialize(self.path,mode='live')
        other=Path(self.temp.name)/'live.sqlite3'
        approval=Path(self.temp.name)/'approval.json'
        with self.assertRaises(AdsError):AdsStore.initialize_approved_live(other,authorization_path=approval,clock=lambda:self.now)
        value=dict(schemaVersion=1,environment='single-durable-host',storePath=str(other),operatorHostId='approved-fixture-host',
            productionOrigin='https://ads.wingman.example.com',expiresAt=self.now+86400,
            deploymentReference='fixture-evidence',liveAdsReference='fixture-evidence',financeReference='fixture-evidence',
            manualPaymentsReference='fixture-evidence',deploymentApproved=True,liveAdsApproved=True,financeApproved=True,
            manualPaymentsApproved=True,durableStorage=True,singleHost=True,partnerDemandEnabled=False,secondSearchAdEnabled=False)
        approval.write_text(json.dumps(value));approval.chmod(0o600)
        live=AdsStore.initialize_approved_live(other,authorization_path=approval,clock=lambda:self.now)
        service=AdsService(live,environment='single-durable-host',live_authorized=True,sweep=False)
        with self.assertRaisesRegex(AdsError,'fixture-cannot-be-live'):
            live.create_advertiser(name='Fixture Sponsor',domain='example.org',contact='fixture@example.org')
        value['liveAdsApproved']=False
        approval.write_text(json.dumps(value))
        with self.assertRaises(AdsError):service.issue_context(intent='office')
        service.close()

if __name__=='__main__':unittest.main()
