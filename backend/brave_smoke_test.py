"""Single launcher-authorized local smoke allowance; never run automatically.

Initialize once, then run. Missing credentials do not consume requests. A failed
or abandoned attempt stops the allowance permanently. No result bodies persist.
"""
import argparse
import json
import sys
import time
from pathlib import Path
from wingman_search.budget import BudgetLedger, BudgetError, default_ledger_path
from wingman_search.secrets import load_secret, default_secret_path, SecretError, secret_status

REPO = Path(__file__).resolve().parent.parent

def run_smoke(ledger, provider, *, sleeper=time.sleep, clock=time.time_ns):
    from wingman_search.contracts import SearchRequest, SearchError
    state = ledger.snapshot()
    # No continuation/restart repeats a partly run allowance, including when
    # the previous process died between the web and news checks.
    if state['profile'] != 'smoke' or state['attempts'] or state['halted']:
        raise BudgetError('smoke_already_started')
    evidence = []
    for kind, query in (('web', 'Python documentation'), ('news', 'space science research')):
        state = ledger.snapshot()
        delay = max(0, (state['next_allowed_utc_micros'] - clock() // 1000) / 1_000_000)
        # Do not sit indefinitely on exhausted account windows or try a fallback.
        if delay > 60:
            evidence.append(dict(endpoint=kind, status='provider-wait', dispatched=False))
            break
        if delay:
            sleeper(delay + .01)
        try:
            dto, _ = provider.search(SearchRequest(query, kind), count=1)
        except (SearchError, BudgetError) as exc:
            evidence.append(dict(endpoint=kind, status=exc.code,
                httpStatus=getattr(exc, 'provider_status', None),
                dispatched=ledger.snapshot()['attempts'] > state['attempts']))
            break
        evidence.append(dict(endpoint=kind, status='schema-success', httpStatus=200,
                             resultCount=len(dto['results']), fixture=False))
    return evidence

def main(argv=None):
    parser = argparse.ArgumentParser(description='One bounded local Brave smoke test; no secret arguments.')
    parser.add_argument('--initialize', action='store_true', help='First install only. Refuses an existing allowance/marker.')
    parser.add_argument('--status', action='store_true', help='Metadata and accounting only; no network or secret reads.')
    args = parser.parse_args(argv)
    path = default_ledger_path(REPO)
    if args.initialize and args.status:
        parser.error('Choose one operation.')
    if args.initialize:
        ledger = BudgetLedger.initialize_smoke(path)
        print(json.dumps(dict(status='initialized', accounting=ledger.snapshot())))
        return
    if args.status:
        status = secret_status(default_secret_path(REPO), REPO)
        try:
            accounting = BudgetLedger(path).snapshot()
        except BudgetError:
            accounting = {'status': 'uninitialized-or-unavailable', 'dispatchAllowed': False}
        print(json.dumps(dict(credential=status, accounting=accounting)))
        return
    # Metadata/init remain standard-library only and never load credential data.
    from wingman_search.provider import BraveProvider
    key = load_secret(default_secret_path(REPO), REPO)
    ledger = BudgetLedger(path)
    evidence = run_smoke(ledger, BraveProvider(ledger, key))
    print(json.dumps(dict(evidence=evidence, accounting=ledger.snapshot())))
    if len(evidence) != 2 or any(row['status'] != 'schema-success' for row in evidence):
        raise SystemExit(1)

if __name__ == '__main__':
    try:
        main()
    except (SecretError, BudgetError) as exc:
        print(json.dumps({'status': 'stopped', 'reason': str(exc)}))
        sys.exit(1)
    except Exception:
        print(json.dumps({'status': 'stopped', 'reason': 'local-configuration-or-accounting-error'}))
        sys.exit(1)
