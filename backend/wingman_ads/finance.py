"""Pure aggregate finance calculations. No consumer records, storage or network.

Money inputs are integer USD micros. Scenario assumptions use Decimal and return
decimal strings; they are hypothetical, never entered into the business ledger.
Missing costs and incomplete/misaligned reporting periods remain unknown.
"""
from datetime import date
from decimal import Decimal, InvalidOperation, localcontext

from .common import AdsError, identifier


PLACEMENTS = ('search', 'newtab', 'news')
VARIABLE_COSTS = ('providerWebMicros', 'providerNewsMicros', 'otherSearchVariableMicros',
                  'otherNewtabVariableMicros', 'otherNewsVariableMicros', 'datastoreMicros')
FIXED_COSTS = ('fixedInfrastructureMicros', 'salariesTimeMicros', 'salesMicros',
              'licensesMicros', 'taxesMicros', 'supportMicros', 'acquisitionMicros')
ADJUSTMENTS = ('creditsMicros', 'paymentFeesMicros', 'partnerShareMicros')


def _money(value):
    if type(value) is not int or not 0 <= value <= 10**18:
        raise AdsError('invalid-finance-micros')
    return value


def _optional(value):
    return None if value is None else _money(value)


def _number(value, maximum=Decimal('1000000000')):
    try:
        if isinstance(value, bool) or not isinstance(value, (str, int, float, Decimal)) or len(str(value)) > 64:
            raise ValueError()
        result = Decimal(str(value))
        if not result.is_finite() or not 0 <= result <= maximum:
            raise ValueError()
        return result
    except (ValueError, InvalidOperation):
        raise AdsError('invalid-scenario-assumption') from None


def _text(value):
    if value is None:
        return None
    if value == 0:
        return '0'
    result = format(value, 'f')
    return result.rstrip('0').rstrip('.') if '.' in result else result


def _ratio(numerator, denominator, scale=1):
    if numerator is None or denominator in (None, 0):
        return None
    with localcontext() as context:
        context.prec = 28
        return _text(Decimal(numerator) * scale / Decimal(denominator))


def scenario(raw):
    """Explicit f,t,p,k,c,v; optional S. USD values, not currency micros."""
    required = {'f', 't', 'p', 'k', 'c', 'v'}
    if not isinstance(raw, dict) or not required <= set(raw) <= required | {'S'}:
        raise AdsError('scenario-assumptions-required')
    values = {name: _number(raw[name], Decimal(1) if name in ('f', 't') else
                           Decimal(1000) if name == 'k' else Decimal('1000000000')) for name in required}
    searches = None
    if 'S' in raw:
        searches = _number(raw['S'], Decimal(10**15))
        if searches != searches.to_integral_value():
            raise AdsError('invalid-search-count')
    with localcontext() as context:
        context.prec = 28
        f, t, p, k, c, v = (values[name] for name in ('f', 't', 'p', 'k', 'c', 'v'))
        revenue, cost = 1000 * f * t * p, k * c + v
        coverage = cost / (1000 * t * p) if t and p else None
        cpc = cost / (1000 * f * t) if f and t else None
        totals = None if searches is None else dict(
            searches=int(searches), revenue=_text(revenue * searches / 1000),
            deliveryCost=_text(cost * searches / 1000), contribution=_text((revenue - cost) * searches / 1000))
        return dict(schemaVersion=1, currency='USD', predictedResults=False,
                    assumptions={key: _text(value) for key, value in sorted(values.items())},
                    revenuePer1000Searches=_text(revenue), deliveryCostPer1000Searches=_text(cost),
                    contributionPer1000Searches=_text(revenue - cost),
                    breakEvenCoverage=_text(coverage), breakEvenNetCpc=_text(cpc),
                    breakEvenCoverageFeasible=None if coverage is None else coverage <= 1,
                    contributionMargin=_text((revenue - cost) / revenue) if revenue else None,
                    totals=totals, fullyLoadedResult=None,
                    missingFullyLoadedInputs=['shared news', *FIXED_COSTS],
                    definitions={'S': 'All submitted search-page requests, including failed and noncommercial requests.',
                                 'f': 'Fraction of all requests receiving one billable-quality ad opportunity; do not multiply fill again.',
                                 'p': 'Net earned USD per valid click after expected revenue deductions.',
                                 'k': 'All paid web provider attempts divided by all submitted searches, including retries/failures.',
                                 'c': 'USD per 1000 provider calls.', 'v': 'Other variable USD cost per 1000 submitted searches.'})


def illustrative_scenarios():
    """Required sensitivity examples; no forecast or assumed current traffic."""
    return {name: scenario(dict(f=f, t=t, p=p, k='1.05', c='5', v='1.25'))
            for name, f, t, p in (('weak', '.30', '.02', '.40'),
                                   ('working', '.50', '.03', '.60'),
                                   ('strong', '.65', '.04', '.80'))}


def _sum_known(values):
    values = list(values)
    return None if any(value is None for value in values) else sum(values)


def _period(raw):
    if raw is None:
        return None
    try:
        if not isinstance(raw, dict) or set(raw) != {'start', 'end'}:
            raise ValueError()
        first, last = date.fromisoformat(raw['start']), date.fromisoformat(raw['end'])
        if first > last or first.isoformat() != raw['start'] or last.isoformat() != raw['end']:
            raise ValueError()
        return dict(raw)
    except (ValueError, TypeError):
        raise AdsError('invalid-finance-period') from None


def dashboard_finance(store_report, search_report=None, costs=None):
    """Combine same-period aggregate records; never infer audience or conversions.

    search_report: {metrics, provider, period:{start,end}, periodAligned, countsComplete}.
    periodAligned is an operator assertion that the supplied search/provider and
    business snapshots cover exactly the same lifetime/period. Counters are not
    period-filtered here. Costs need their own periodAligned assertion.
    """
    if not isinstance(store_report, dict) or store_report.get('mode') not in ('test', 'live') or store_report.get('currency') != 'USD':
        raise AdsError('invalid-business-summary')
    costs = {} if costs is None else costs
    cost_fields = set(VARIABLE_COSTS + FIXED_COSTS) | {'placementAdjustments', 'periodAligned',
                   'invoiceOutstandingMicros', 'cashSettledMicros', 'expectedPaymentDays', 'costEvidenceReference',
                   'searchDatastoreMicros'}
    if not isinstance(costs, dict) or set(costs) - cost_fields:
        raise AdsError('invalid-business-cost-fields')
    if 'periodAligned' in costs and type(costs['periodAligned']) is not bool:
        raise AdsError('invalid-finance-period')
    supplied_costs = {name: _optional(costs.get(name)) for name in VARIABLE_COSTS + FIXED_COSTS}
    search_datastore = _optional(costs.get('searchDatastoreMicros'))
    invoice, settled = (_optional(costs.get(key)) for key in ('invoiceOutstandingMicros', 'cashSettledMicros'))
    payment_days = _optional(costs.get('expectedPaymentDays'))
    if payment_days is not None and payment_days > 3650:
        raise AdsError('invalid-payment-assumption')
    evidence = costs.get('costEvidenceReference')
    if evidence is not None:
        identifier(evidence)
    fixture, prefix = store_report['mode'] == 'test', 'test' if store_report['mode'] == 'test' else 'live'
    names = ('InvoicedMicros', 'CashCollectedMicros', 'GrossEarnedMicros', 'CreditsMicros', 'EarnedMicros',
             'RefundedMicros', 'PrepaidLiabilityMicros', 'DisputedReceivableMicros', 'ReservedMicros',
             'FeesAndSharesMicros', 'PaymentFeesMicros', 'PartnerShareMicros')
    business = {name: _optional(store_report.get(prefix + name)) for name in names}
    if business['FeesAndSharesMicros'] == 0:
        business['PaymentFeesMicros'] = business['PartnerShareMicros'] = 0
    if (business['PaymentFeesMicros'] is not None and business['PartnerShareMicros'] is not None
            and business['FeesAndSharesMicros'] != business['PaymentFeesMicros'] + business['PartnerShareMicros']):
        raise AdsError('business-fee-reconciliation-mismatch')
    actual_business = {key: 0 if fixture else value for key, value in business.items()}
    placement = {name: {'opportunities': 0, 'eligible': 0, 'fills': 0, 'renders': 0,
                        'visibleImpressions': 0, 'validClicks': 0, 'rejected': 0, 'billableEvents': 0,
                        'eligiblePages': None, 'filledPages': None,
                        'grossEarnedMicros': 0, 'noFillReasons': {}} for name in PLACEMENTS}
    metric_names = {'opportunity': 'opportunities', 'eligible': 'eligible', 'fill': 'fills',
                    'render': 'renders', 'view': 'visibleImpressions', 'click': 'validClicks',
                    'rejected': 'rejected', 'billable-event': 'billableEvents', 'earned-micros': 'grossEarnedMicros'}
    aggregates = store_report.get('aggregates', [])
    if not isinstance(aggregates, list):
        raise AdsError('invalid-ad-aggregates')
    for row in aggregates:
        if not isinstance(row, dict) or row.get('placement') not in placement or not isinstance(row.get('metric'), str):
            raise AdsError('invalid-ad-aggregates')
        amount = _money(row.get('value'))
        target, metric = placement[row['placement']], row['metric']
        if metric in metric_names:
            target[metric_names[metric]] += amount
        elif metric in ('eligible-page', 'filled-page'):
            key = 'eligiblePages' if metric == 'eligible-page' else 'filledPages'
            target[key] = (target[key] or 0) + amount
        elif metric.startswith('no-fill-'):
            reason = metric[len('no-fill-'):]
            target['noFillReasons'][reason] = target['noFillReasons'].get(reason, 0) + amount
    if sum(row['grossEarnedMicros'] for row in placement.values()) != business['GrossEarnedMicros']:
        raise AdsError('earned-revenue-reconciliation-mismatch')
    allocations = costs.get('placementAdjustments')
    totals = {'creditsMicros': business['CreditsMicros'], 'paymentFeesMicros': business['PaymentFeesMicros'],
              'partnerShareMicros': business['PartnerShareMicros']}
    if allocations is not None:
        if costs.get('periodAligned') is not True or evidence is None:
            raise AdsError('placement-allocation-evidence-required')
        if not isinstance(allocations, dict) or set(allocations) != set(PLACEMENTS):
            raise AdsError('invalid-placement-allocation')
        for row in allocations.values():
            if not isinstance(row, dict) or set(row) != set(ADJUSTMENTS):
                raise AdsError('invalid-placement-allocation')
            for value in row.values(): _money(value)
        if any(totals[name] is None or sum(row[name] for row in allocations.values()) != totals[name] for name in ADJUSTMENTS):
            raise AdsError('placement-allocation-reconciliation-mismatch')
    elif all(value == 0 for value in totals.values()):
        allocations = {place: dict.fromkeys(ADJUSTMENTS, 0) for place in PLACEMENTS}
    for name, row in placement.items():
        adjustment = None if allocations is None else allocations[name]
        if adjustment is not None and adjustment['creditsMicros'] > row['grossEarnedMicros']:
            raise AdsError('placement-credit-exceeds-earned')
        row['netEarnedMicros'] = None if adjustment is None else row['grossEarnedMicros'] - sum(adjustment.values())
        row['fillAmongEligible'] = _ratio(row['fills'], row['eligible'])
        row['qualifiedViewRateAmongFills'] = _ratio(row['visibleImpressions'], row['fills'])
        row['validClickRateAmongFills'] = _ratio(row['validClicks'], row['fills'])
        if fixture:
            row['fixtureGrossEarnedMicros'] = row['grossEarnedMicros']
            row['fixtureNetEarnedMicros'] = row['netEarnedMicros']
            row['grossEarnedMicros'], row['netEarnedMicros'], row['billableEvents'] = 0, 0, 0
    search_report = {} if search_report is None else search_report
    if not isinstance(search_report, dict) or set(search_report) - {'metrics', 'provider', 'period', 'periodAligned', 'countsComplete'}:
        raise AdsError('invalid-search-summary')
    metrics, provider = search_report.get('metrics', {}), search_report.get('provider', {})
    if not isinstance(metrics, dict) or not isinstance(provider, dict):
        raise AdsError('invalid-search-summary')
    period = _period(search_report.get('period'))
    for key in ('periodAligned', 'countsComplete'):
        if key in search_report and type(search_report[key]) is not bool:
            raise AdsError('invalid-finance-period')
    counts = {name: _optional(metrics.get(name)) for name in ('submitted', 'completed', 'failed')}
    unresolved = None if any(value is None for value in counts.values()) else counts['submitted'] - counts['completed'] - counts['failed']
    if unresolved is not None and unresolved < 0:
        raise AdsError('inconsistent-search-counters')
    usable = (not fixture and period is not None and search_report.get('periodAligned') is True
              and search_report.get('countsComplete') is True and metrics.get('durable') is True
              and metrics.get('environment') == 'production' and all(value is not None for value in counts.values()))
    attempts = _optional(provider.get('attempts'))
    endpoints = provider.get('endpoint_attempts', {})
    if not isinstance(endpoints, dict) or set(endpoints) - {'web', 'news'}:
        raise AdsError('invalid-provider-summary')
    web, news = (_optional(endpoints.get(key)) for key in ('web', 'news'))
    if attempts is not None and web is not None and news is not None and attempts != web + news:
        raise AdsError('inconsistent-provider-counters')
    reconciled_count = _optional(provider.get('reconciled_attempts'))
    reconciled_cost = _optional(provider.get('reconciled_billed_micros'))
    billed_count = _optional(provider.get('reconciled_billed_requests'))
    if reconciled_count is not None and (attempts is None or reconciled_count > attempts):
        raise AdsError('inconsistent-provider-reconciliation')
    if billed_count is not None and (reconciled_count is None or billed_count > reconciled_count):
        raise AdsError('inconsistent-provider-reconciliation')
    provider_usable = usable and provider.get('environment') == 'production'
    actual_provider_cost = reconciled_cost if (provider_usable and attempts is not None
                                               and reconciled_count == attempts) else None
    actual_costs = dict(supplied_costs)
    costs_aligned = costs.get('periodAligned') is True and evidence is not None and usable
    if not costs_aligned:
        actual_costs = dict.fromkeys(actual_costs)
        search_datastore = None
    if actual_costs['datastoreMicros'] == 0:
        if search_datastore not in (None, 0):
            raise AdsError('datastore-allocation-mismatch')
        search_datastore = 0
    if search_datastore is not None and (actual_costs['datastoreMicros'] is None or search_datastore > actual_costs['datastoreMicros']):
        raise AdsError('datastore-allocation-mismatch')
    endpoint_cost = _sum_known(actual_costs[key] for key in ('providerWebMicros', 'providerNewsMicros'))
    if actual_provider_cost is not None and endpoint_cost is not None and endpoint_cost != actual_provider_cost:
        raise AdsError('provider-cost-reconciliation-mismatch')
    if actual_provider_cost is None and endpoint_cost is not None:
        actual_provider_cost = endpoint_cost
    if actual_provider_cost is not None and endpoint_cost is None and news == 0:
        actual_costs['providerWebMicros'], actual_costs['providerNewsMicros'] = actual_provider_cost, 0
    elif actual_provider_cost is not None and endpoint_cost is None and web == 0:
        actual_costs['providerWebMicros'], actual_costs['providerNewsMicros'] = 0, actual_provider_cost
    other_variable = _sum_known(actual_costs[key] for key in VARIABLE_COSTS if not key.startswith('provider'))
    variable = _sum_known((actual_provider_cost, other_variable))
    fixed = _sum_known(actual_costs[key] for key in FIXED_COSTS)
    net = None if actual_business['EarnedMicros'] is None or actual_business['FeesAndSharesMicros'] is None else actual_business['EarnedMicros'] - actual_business['FeesAndSharesMicros']
    contribution = None if variable is None or net is None else net - variable
    fully_loaded = None if contribution is None or fixed is None else contribution - fixed
    search_cost = _sum_known((actual_costs['providerWebMicros'], actual_costs['otherSearchVariableMicros'], search_datastore))
    search_net = placement['search']['netEarnedMicros']
    denominator = counts['submitted'] if usable else None
    search = dict(counts, unresolved=unresolved, durable=metrics.get('durable') is True,
                  denominatorStatus='aligned-all-submitted' if usable else 'unverified-or-misaligned',
                  fixture=fixture, eligibleAdRate=_ratio(placement['search']['eligiblePages'], denominator),
                  filledPageRate=_ratio(placement['search']['filledPages'], denominator),
                  eligibleSlotOpportunitiesPerSubmitted=_ratio(placement['search']['eligible'], denominator),
                  totalProviderAttempts=attempts, webProviderAttempts=web, newsProviderAttempts=news,
                  providerAttemptsPerSubmitted=_ratio(attempts, denominator) if provider_usable else None,
                  webProviderAttemptsPerSubmitted=_ratio(web, denominator) if provider_usable else None,
                  confirmedProviderSuccesses=_optional(provider.get('confirmed_successes')),
                  estimatedSuccessCostMicros=_optional(provider.get('estimated_success_cost_micros')),
                  unknownProviderOutcomes=_optional(provider.get('unknown_outcomes')),
                  unknownReservedMicros=_optional(provider.get('unknown_reserved_micros')),
                  reconciledAttempts=reconciled_count, reconciledBilledMicros=reconciled_cost,
                  reconciledBilledRequests=billed_count,
                  actualProviderCostMicros=actual_provider_cost,
                  actualBilledRequestCount=billed_count if provider_usable and attempts is not None and reconciled_count == attempts else None,
                  providerCostPerSubmittedMicros=_ratio(actual_provider_cost, denominator),
                  providerCostPerCompletedMicros=_ratio(actual_provider_cost, counts['completed'] if usable else None))
    obligations = []
    for campaign in store_report.get('campaigns', []):
        if not isinstance(campaign, dict) or not isinstance(campaign.get('config'), dict):
            raise AdsError('invalid-campaign-summary')
        guarantee = _money(campaign['config'].get('guaranteedImpressions', 0))
        if guarantee:
            obligations.append(dict(campaignId=campaign['id'], status=campaign['status'],
                remainingGuaranteedImpressions=max(0, guarantee - _money(campaign.get('views', 0))),
                endsAt=campaign['config'].get('endsAt'), fixture=fixture))
    return dict(schemaVersion=1, mode=store_report['mode'], currency='USD', fixture=fixture, period=period,
                revenueLive=False, audienceVerified=False,
                search=search,
                ads=dict(commercial=actual_business, fixtureBusiness=business if fixture else None,
                         placements=placement, netEarnedMicros=net, obligations=obligations,
                         invoiceOutstandingMicros=invoice if costs_aligned else None,
                         cashSettledMicros=settled if costs_aligned else None, expectedPaymentDays=payment_days),
                costs=dict(actual_costs, totalVariableMicros=variable, totalFixedMicros=fixed,
                           searchDatastoreMicros=search_datastore, periodAligned=costs_aligned, evidenceReference=evidence),
                economics=dict(searchRevenuePer1000SubmittedMicros=_ratio(search_net, denominator, 1000),
                               searchVariableCostMicros=search_cost,
                               searchContributionMicros=None if search_cost is None or search_net is None else search_net-search_cost,
                               variableContributionMicros=contribution, fullyLoadedResultMicros=fully_loaded,
                               contributionMargin=_ratio(contribution, net)),
                missingInputs=[name for name, value in actual_costs.items() if value is None] +
                              ([] if usable else ['aligned-complete-production-search-period']) +
                              ([] if allocations is not None else ['placementAdjustments']) +
                              ([] if search_datastore is not None else ['searchDatastoreMicros']) +
                              ([] if actual_provider_cost is not None else ['reconciled-provider-cost']),
                definitions={'revenue': 'Earned valid delivery less recorded credits; prepaid receipts are liabilities until earned.',
                             'net': 'Earned delivery less credits, payment fees and partner shares. Chargebacks may create a disputed receivable; they do not prove cash settlement.',
                             'searchDenominator': 'ALL submitted search-page requests, including failures, private and noncommercial requests; not eligible queries, clicks or unique users.',
                             'provider': 'Attempts include errors and retries. Confirmed HTTP successes are estimated billing, not invoiced requests. Partial reconciliation is not full actual cost.',
                             'costs': 'Each category is mutually exclusive and covers the same period. Fees/shares are deducted from revenue once. Shared news and datastore are included in total variable contribution.',
                             'reporting': 'Operator-only aggregate finance summary. Advertiser exports use the separate minimum-bucket-size report.',
                             'timeToCash': 'expectedPaymentDays is an explicit assumption; outstanding invoice and settled cash are unknown until supplied from verified business records.'})
