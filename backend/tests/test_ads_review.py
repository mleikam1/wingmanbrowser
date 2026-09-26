"""Independent review regressions; disposable fixture money, no external I/O."""
from contextlib import contextmanager
import json
from pathlib import Path
import unittest

import test_ads_core as core
from wingman_ads import AdsError
from wingman_ads.demand import CandidateChain, DemandSlot


class AdsReviewTests(unittest.TestCase):
    def setUp(self):
        self.h = core.AdsCoreTests()
        self.h.setUp()

    def tearDown(self):
        self.h.tearDown()

    def delay_lock(self, seconds):
        original = self.h.store.transaction

        @contextmanager
        def delayed():
            with original() as db:
                self.h.now += seconds
                yield db
        self.h.store.transaction = delayed
        return original

    def test_campaign_expiry_during_lock_wait_cannot_settle(self):
        self.h.campaign(endsAt=self.h.now + 1)
        ad = self.h.decision()['ad']
        original = self.delay_lock(2)
        self.assertEqual('rejected', self.h.event(ad)['status'])
        self.h.store.transaction = original
        self.assertEqual(0, self.h.store.dashboard()['testEarnedMicros'])

    def test_campaign_expiry_during_lock_wait_cannot_reserve(self):
        self.h.campaign(endsAt=self.h.now + 1)
        original = self.delay_lock(2)
        self.assertEqual('no-fill', self.h.decision()['status'])
        self.h.store.transaction = original
        self.assertEqual(0, self.h.store.dashboard()['testReservedMicros'])

    def test_live_gate_rechecked_after_lock_entry(self):
        self.h.campaign()
        ad = self.h.decision()['ad']
        original = self.h.store.transaction

        @contextmanager
        def revoke():
            with original() as db:
                def denied():
                    raise AdsError('live-finance-authorization-required')
                self.h.store.authorize_live = denied
                yield db
        self.h.store.transaction = revoke
        with self.assertRaisesRegex(AdsError, 'live-finance-authorization-required'):
            self.h.event(ad)
        self.h.store.transaction = original
        self.assertEqual(0, self.h.store.dashboard()['testEarnedMicros'])

    def test_yield_compares_click_and_qualified_view_per_fill(self):
        cpc = self.h.campaign(rateMicros=500000)
        cpm = self.h.campaign(billingType='cpm', rateMicros=10000000)
        with self.h.store.transaction() as db:
            for campaign in (cpc, cpm):
                self.h.store.count(db, campaign, 'search', 'fill', 100)
            self.h.store.count(db, cpc, 'search', 'click', 1)
            self.h.store.count(db, cpm, 'search', 'view', 25)
        # Smoothed CPC = 500000 * .01; CPM = 10000 * .25.
        self.assertEqual(cpc, self.h.decision()['ad']['campaignId'])

    def test_guarantees_cannot_exceed_cap_budget_or_cash(self):
        for changes in (
            dict(billingType='cpm', rateMicros=10000000, guaranteedImpressions=101, impressionCap=100),
            dict(billingType='cpm', rateMicros=10000000, guaranteedImpressions=100, budgetMicros=500000, dailyBudgetMicros=500000),
            dict(billingType='cpc', guaranteedImpressions=1),
        ):
            with self.subTest(changes=changes), self.assertRaises(AdsError):
                self.h.campaign(**changes)
        with self.assertRaises(AdsError):
            self.h.campaign(funds=500000, billingType='cpm', rateMicros=10000000, guaranteedImpressions=100)

    def test_actual_chargeback_after_spend_preserves_reconciliation(self):
        entity = self.h.campaign(funds=500000, budgetMicros=500000, dailyBudgetMicros=500000)
        ad = self.h.decision()['ad']
        self.h.event(ad)
        request = dict(kind='chargeback', amount_micros=500000,
                       operation_key='observed-reversal', reference='fixture-bank-reversal')
        self.assertTrue(self.h.store.business_entry(entity, **request))
        self.assertFalse(self.h.store.business_entry(entity, **request))
        report = self.h.store.dashboard()
        self.assertEqual('paused', report['campaigns'][0]['status'])
        self.assertEqual(500000, report['testRefundedMicros'])
        self.assertEqual(500000, report['testDisputedReceivableMicros'])
        self.assertEqual(0, report['testPrepaidLiabilityMicros'])
        self.assertEqual(0, report['testReservedMicros'])
        self.assertEqual(0, report['commercialRevenueMicros'])
        self.assertEqual('no-fill', self.h.decision()['status'])

    def test_currency_cannot_be_mixed(self):
        with self.assertRaisesRegex(AdsError, 'unsupported-currency'):
            self.h.campaign(currency='EUR')
        self.h.campaign(currency='USD')
        self.assertEqual('USD', self.h.store.dashboard()['currency'])

    def test_second_slot_requires_explicit_evidence_and_three_organic(self):
        self.h.campaign()
        service = self.h.service
        grant = service.issue_context(intent='office', fixture=True, organic_count=10)
        request = dict(placement='search', context='normal', foreground=True, contextToken=grant['token'], slotIndex=1)
        self.assertFalse(grant['secondSlotAllowed'])
        self.assertEqual('no-fill', service.decision(request)['status'])
        path = Path(self.h.temp.name) / 'experiment.json'
        approval = dict(ownerApproved=True, expiresAt=self.h.now + 3600, demandReference='fixture',
                        stableLayoutReference='fixture', relevanceReference='fixture',
                        incrementalNetContributionReference='fixture', qualityLatencyReference='fixture',
                        secondSearchAdEnabled=True, explorationEnabled=False)
        path.write_text(json.dumps(approval)); path.chmod(0o600)
        service.experiment_path = path
        self.assertFalse(service.issue_context(intent='office', fixture=True, organic_count=2)['secondSlotAllowed'])
        grant = service.issue_context(intent='office', fixture=True, organic_count=3)
        request['contextToken'] = grant['token']
        self.assertEqual('filled', service.decision(request)['status'])
        with self.assertRaises(AdsError):
            service.decision(dict(request, slotIndex=2))
        approval['secondSearchAdEnabled'] = False
        path.write_text(json.dumps(approval))
        self.assertEqual('no-fill', service.decision(request)['status'])

    def test_demand_chain_is_direct_first_gated_and_does_not_fan_out(self):
        calls = []

        class Adapter:
            def __init__(self, result): self.result = result
            def select(self, context, allowed):
                calls.append((context, allowed))
                return self.result

        def candidate(entity, source):
            return (1, False, 1, {'id': entity, 'config': {'demandSource': source}}, 1)

        direct, partner, merchant = [candidate(x, x) for x in ('direct', 'partner', 'merchant')]
        gate = dict(ownerApproved=True, expiresAt=self.h.now + 100, agreementReference='fixture',
                    apiReviewReference='fixture', privacyReviewReference='fixture', inventoryApproved=True,
                    providerCompatible=True, identifierFree=True, noSdkCookiePixel=True, merchantActionPermitted=True)
        chain = CandidateChain(DemandSlot('partner', Adapter('partner'), gate),
                               DemandSlot('merchant', Adapter('merchant'), gate))
        self.assertEqual(direct, chain.choose([partner, direct, merchant], {}, self.h.now)[0])
        self.assertFalse(calls)
        self.assertEqual(partner, chain.choose([partner, merchant], {}, self.h.now)[0])
        self.assertEqual(1, len(calls))
        calls.clear()
        disabled = DemandSlot('partner', Adapter('partner'))
        self.assertIsNone(disabled.choose([partner], {}, self.h.now)[0])
        self.assertFalse(calls)
        forged = DemandSlot('partner', Adapter('unreviewed-campaign'), gate)
        self.assertIsNone(forged.choose([partner], {}, self.h.now)[0])


if __name__ == '__main__':
    unittest.main()
