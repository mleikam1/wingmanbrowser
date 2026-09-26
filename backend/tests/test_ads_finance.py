"""Exact hypothetical arithmetic and aggregate business reconciliation only."""
from copy import deepcopy
from decimal import Decimal
import json
import unittest

from wingman_ads.common import AdsError
from wingman_ads.finance import (
    ADJUSTMENTS, FIXED_COSTS, PLACEMENTS, VARIABLE_COSTS,
    dashboard_finance, illustrative_scenarios, scenario,
)


class AdsFinanceTests(unittest.TestCase):
    def scenario(self, **changes):
        return scenario(dict(dict(f='.50', t='.03', p='.60', k='1.05', c='5', v='1.25'), **changes))

    def business(self, mode='live'):
        prefix = mode
        amounts = dict(InvoicedMicros=500_000_000, CashCollectedMicros=500_000_000,
            GrossEarnedMicros=9_000_000, CreditsMicros=0, EarnedMicros=9_000_000,
            RefundedMicros=0, PrepaidLiabilityMicros=491_000_000, DisputedReceivableMicros=0,
            ReservedMicros=1_000_000, PaymentFeesMicros=0, PartnerShareMicros=0, FeesAndSharesMicros=0)
        aggregates = [dict(day='2026-09-26', campaign_id='fixture-business', placement='search', metric=key, value=value)
                      for key, value in {'opportunity':500, 'eligible':500, 'fill':400, 'render':390, 'view':300,
                                         'click':15, 'earned-micros':9_000_000, 'billable-event':15,
                                         'eligible-page':500, 'filled-page':400}.items()]
        return dict(mode=mode, currency='USD', aggregates=aggregates, campaigns=[],
                    **{prefix+key: value for key, value in amounts.items()})

    def searches(self):
        return dict(metrics=dict(submitted=1000, completed=900, failed=100, durable=True, environment='production'),
            provider=dict(attempts=1050, endpoint_attempts=dict(web=1050, news=0), environment='production',
                          confirmed_successes=1000, estimated_success_cost_micros=5_000_000,
                          unknown_outcomes=50, unknown_reserved_micros=250_000,
                          reconciled_attempts=1050, reconciled_billed_micros=5_250_000),
            period=dict(start='2026-09-01', end='2026-09-30'), periodAligned=True, countsComplete=True)

    def costs(self):
        return dict(dict.fromkeys(VARIABLE_COSTS + FIXED_COSTS, 0), providerWebMicros=5_250_000,
            otherSearchVariableMicros=1_250_000, periodAligned=True, costEvidenceReference='fixture-reconciled-period',
            salariesTimeMicros=2_000_000, expectedPaymentDays=30)

    def test_required_sensitivities_exact_and_not_forecasts(self):
        expected = [('weak', '2.4', '-4.1'), ('working', '9', '2.5'), ('strong', '20.8', '14.3')]
        reports = illustrative_scenarios()
        for name, revenue, contribution in expected:
            with self.subTest(name=name):
                self.assertEqual(revenue, reports[name]['revenuePer1000Searches'])
                self.assertEqual('6.5', reports[name]['deliveryCostPer1000Searches'])
                self.assertEqual(contribution, reports[name]['contributionPer1000Searches'])
                self.assertFalse(reports[name]['predictedResults'])
                self.assertIsNone(reports[name]['fullyLoadedResult'])

    def test_scenario_scales_all_searches_without_multiplying_fill_twice(self):
        report = self.scenario(S='100000')
        self.assertEqual(dict(searches=100000, revenue='900', deliveryCost='650', contribution='250'), report['totals'])
        self.assertAlmostEqual(Decimal('6.5')/(1000*Decimal('.03')*Decimal('.6')),
                               Decimal(report['breakEvenCoverage']))
        self.assertAlmostEqual(Decimal('6.5')/(1000*Decimal('.5')*Decimal('.03')),
                               Decimal(report['breakEvenNetCpc']))

    def test_zero_divisors_and_infeasible_coverage_are_explicit(self):
        report = self.scenario(f=0, t=0, p=0, S=0)
        self.assertIsNone(report['breakEvenCoverage'])
        self.assertIsNone(report['breakEvenNetCpc'])
        self.assertIsNone(report['contributionMargin'])
        self.assertEqual('0', report['totals']['contribution'])
        self.assertFalse(self.scenario(t='.0001')['breakEvenCoverageFeasible'])

    def test_assumptions_required_finite_and_bounded(self):
        with self.assertRaises(AdsError): scenario({'f': '.5'})
        for change in (dict(f='NaN'), dict(p='Infinity'), dict(t='1.01'), dict(v='-.01'),
                       dict(S='1.5'), dict(c=True), dict(k=1001), dict(query='not-allowed')):
            with self.subTest(change=change), self.assertRaises(AdsError):
                self.scenario(**change)

    def test_all_submitted_denominator_includes_failed_noncommercial_requests(self):
        report = dashboard_finance(self.business(), self.searches(), self.costs())
        self.assertEqual(1000, report['search']['submitted'])
        self.assertEqual('1.05', report['search']['webProviderAttemptsPerSubmitted'])
        self.assertEqual('0.5', report['search']['eligibleAdRate'])
        self.assertEqual('0.4', report['search']['filledPageRate'])
        self.assertEqual('0.8', report['ads']['placements']['search']['fillAmongEligible'])
        self.assertEqual('9000000', report['economics']['searchRevenuePer1000SubmittedMicros'])
        self.assertEqual(2_500_000, report['economics']['variableContributionMicros'])
        self.assertEqual(500_000, report['economics']['fullyLoadedResultMicros'])
        self.assertEqual('5250', report['search']['providerCostPerSubmittedMicros'])
        self.assertEqual('5833.333333333333333333333333', report['search']['providerCostPerCompletedMicros'])

    def test_second_slot_counts_do_not_inflate_eligible_page_fraction(self):
        business = self.business()
        business['aggregates'].append(dict(day='2026-09-26', campaign_id='-', placement='search', metric='eligible', value=400))
        report = dashboard_finance(business, self.searches())
        self.assertEqual('0.5', report['search']['eligibleAdRate'])
        self.assertEqual('0.9', report['search']['eligibleSlotOpportunitiesPerSubmitted'])

    def test_missing_costs_and_incomplete_reconciliation_are_not_zero(self):
        searches = self.searches()
        searches['provider'].update(reconciled_attempts=1000, reconciled_billed_micros=5_000_000)
        report = dashboard_finance(self.business(), searches)
        self.assertEqual(5_000_000, report['search']['estimatedSuccessCostMicros'])
        self.assertEqual(250_000, report['search']['unknownReservedMicros'])
        self.assertEqual(5_000_000, report['search']['reconciledBilledMicros'])
        self.assertIsNone(report['search']['actualProviderCostMicros'])
        self.assertIsNone(report['search']['actualBilledRequestCount'])
        self.assertIsNone(report['economics']['variableContributionMicros'])
        self.assertIsNone(report['economics']['fullyLoadedResultMicros'])
        self.assertIn('datastoreMicros', report['missingInputs'])

    def test_positive_billed_requests_need_complete_reconciliation(self):
        searches = self.searches()
        searches['provider'].update(reconciled_attempts=1000, reconciled_billed_requests=900)
        report = dashboard_finance(self.business(), searches)
        self.assertEqual(900, report['search']['reconciledBilledRequests'])
        self.assertIsNone(report['search']['actualBilledRequestCount'])
        searches['provider']['reconciled_attempts'] = 1050
        report = dashboard_finance(self.business(), searches)
        self.assertEqual(900, report['search']['actualBilledRequestCount'])
        searches['provider']['reconciled_billed_requests'] = 1051
        with self.assertRaises(AdsError): dashboard_finance(self.business(), searches)

    def test_misaligned_or_non_durable_live_counts_cannot_generate_rpm(self):
        for key in ('periodAligned', 'countsComplete', 'durable'):
            searches = self.searches()
            if key == 'durable': searches['metrics'][key] = False
            else: searches[key] = False
            report = dashboard_finance(self.business(), searches, self.costs())
            self.assertIsNone(report['economics']['searchRevenuePer1000SubmittedMicros'])
            self.assertIsNone(report['search']['providerAttemptsPerSubmitted'])
        self.assertIsNone(dashboard_finance(self.business())['search']['submitted'])

    def test_zero_searches_never_divide_or_claim_reach(self):
        searches = self.searches()
        searches['metrics'].update(submitted=0, completed=0, failed=0)
        report = dashboard_finance(self.business(), searches)
        self.assertIsNone(report['economics']['searchRevenuePer1000SubmittedMicros'])
        self.assertIsNone(report['search']['providerAttemptsPerSubmitted'])
        self.assertFalse(report['audienceVerified'])

    def test_fixture_cash_impressions_and_earned_money_are_not_commercial(self):
        report = dashboard_finance(self.business('test'), self.searches(), self.costs())
        self.assertEqual(500_000_000, report['ads']['fixtureBusiness']['CashCollectedMicros'])
        self.assertEqual(0, report['ads']['commercial']['CashCollectedMicros'])
        self.assertEqual(0, report['ads']['commercial']['EarnedMicros'])
        self.assertEqual(0, report['ads']['placements']['search']['grossEarnedMicros'])
        self.assertEqual(0, report['ads']['placements']['search']['billableEvents'])
        self.assertIsNone(report['economics']['searchRevenuePer1000SubmittedMicros'])
        self.assertFalse(report['revenueLive'])

    def test_net_placement_allocation_required_and_reconciled(self):
        business = self.business()
        business.update(liveCreditsMicros=1_000_000, liveEarnedMicros=8_000_000, livePaymentFeesMicros=100_000,
                        livePartnerShareMicros=200_000, liveFeesAndSharesMicros=300_000)
        report = dashboard_finance(business, self.searches())
        self.assertEqual(7_700_000, report['ads']['netEarnedMicros'])
        self.assertIsNone(report['economics']['searchRevenuePer1000SubmittedMicros'])
        costs = self.costs()
        costs['placementAdjustments'] = {p:dict.fromkeys(ADJUSTMENTS, 0) for p in PLACEMENTS}
        costs['placementAdjustments']['search'].update(creditsMicros=1_000_000, paymentFeesMicros=100_000, partnerShareMicros=200_000)
        report = dashboard_finance(business, self.searches(), costs)
        self.assertEqual('7700000', report['economics']['searchRevenuePer1000SubmittedMicros'])
        self.assertEqual(1_200_000, report['economics']['variableContributionMicros'])
        costs['placementAdjustments']['search']['creditsMicros'] += 1
        with self.assertRaisesRegex(AdsError, 'allocation-reconciliation'):
            dashboard_finance(business, self.searches(), costs)

    def test_provider_costs_cannot_be_double_counted_or_false_zero(self):
        costs = self.costs()
        costs['providerWebMicros'] -= 1
        with self.assertRaisesRegex(AdsError, 'provider-cost-reconciliation'):
            dashboard_finance(self.business(), self.searches(), costs)
        costs = self.costs()
        costs.pop('costEvidenceReference')
        report = dashboard_finance(self.business(), self.searches(), costs)
        self.assertIsNone(report['economics']['variableContributionMicros'])

    def test_shared_news_separate_from_web_search_unit_economics(self):
        searches, costs = self.searches(), self.costs()
        searches['provider'].update(attempts=1150, endpoint_attempts=dict(web=1050,news=100),
                                   reconciled_attempts=1150, reconciled_billed_micros=5_750_000)
        costs['providerNewsMicros'] = 500_000
        report = dashboard_finance(self.business(), searches, costs)
        self.assertEqual('1.05', report['search']['webProviderAttemptsPerSubmitted'])
        self.assertEqual('1.15', report['search']['providerAttemptsPerSubmitted'])
        self.assertEqual(2_500_000, report['economics']['searchContributionMicros'])
        self.assertEqual(2_000_000, report['economics']['variableContributionMicros'])

    def test_nonzero_datastore_needs_search_allocation_before_search_contribution(self):
        costs = self.costs()
        costs['datastoreMicros'] = 100_000
        report = dashboard_finance(self.business(), self.searches(), costs)
        self.assertIsNone(report['economics']['searchContributionMicros'])
        self.assertEqual(2_400_000, report['economics']['variableContributionMicros'])
        costs['searchDatastoreMicros'] = 80_000
        report = dashboard_finance(self.business(), self.searches(), costs)
        self.assertEqual(2_420_000, report['economics']['searchContributionMicros'])
        self.assertEqual(2_400_000, report['economics']['variableContributionMicros'])
        costs['searchDatastoreMicros'] = 100_001
        with self.assertRaises(AdsError): dashboard_finance(self.business(), self.searches(), costs)

    def test_invalid_aggregate_period_money_and_extra_consumer_fields_rejected(self):
        for change in (dict(submitted=999), dict(failed=True)):
            searches = self.searches(); searches['metrics'].update(change)
            with self.assertRaises(AdsError): dashboard_finance(self.business(), searches)
        searches = self.searches(); searches['period']['start'] = '2026-10-01'
        with self.assertRaises(AdsError): dashboard_finance(self.business(), searches)
        with self.assertRaises(AdsError): dashboard_finance(self.business(), costs={'query':'CANARY'})
        with self.assertRaises(AdsError): dashboard_finance(self.business(), costs={'providerWebMicros':1.25})
        business = self.business(); business['liveGrossEarnedMicros'] += 1
        with self.assertRaises(AdsError): dashboard_finance(business)

    def test_invoiced_earned_collected_settled_and_obligations_stay_distinct(self):
        business = self.business()
        business['campaigns'] = [dict(id='fixture-obligation', status='active', views=10,
            config=dict(guaranteedImpressions=100, endsAt=1790400000))]
        report = dashboard_finance(business, self.searches(), self.costs())
        self.assertEqual(500_000_000, report['ads']['commercial']['InvoicedMicros'])
        self.assertEqual(9_000_000, report['ads']['commercial']['EarnedMicros'])
        self.assertIsNone(report['ads']['cashSettledMicros'])
        self.assertIsNone(report['ads']['invoiceOutstandingMicros'])
        self.assertEqual(30, report['ads']['expectedPaymentDays'])
        self.assertEqual(90, report['ads']['obligations'][0]['remainingGuaranteedImpressions'])
        json.dumps(report, allow_nan=False)


if __name__ == '__main__':
    unittest.main()
