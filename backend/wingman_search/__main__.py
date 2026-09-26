"""Explicit local commands. No command silently initializes or renews a grant."""
import argparse
import json
from pathlib import Path

from .budget import BudgetError
from .gateway import SearchApplication, serve, valid_local_origin
from .provider import FixtureProvider


def main(argv=None):
    parser = argparse.ArgumentParser(description='Wingman loopback gateway: disabled, synthetic fixtures, or explicit local live evaluation.')
    parser.add_argument('command', choices=('serve', 'serve-fixtures', 'serve-live-local',
                                            'initialize-local', 'status-local', 'resume-local'))
    parser.add_argument('--port', type=int)
    parser.add_argument('--origin', action='append', default=[])
    parser.add_argument('--actor', choices=('manual', 'automated'), default='manual',
                        help='Server-wide attribution; automated acceptance must use automated.')
    parser.add_argument('--correction', choices=('credential-updated', 'account-corrected',
        'request-corrected', 'schema-corrected', 'rate-metadata-corrected', 'transport-reviewed'))
    parser.add_argument('--ads-fixture-store', help='Existing test-money campaign store; serve-fixtures only')
    args = parser.parse_args(argv)
    if args.port is None:
        args.port = 8895 if args.command in ('serve', 'serve-fixtures') else 8897
    if not 1024 <= args.port <= 65535:
        parser.error('Use a local unprivileged port.')
    if any(not valid_local_origin(origin) for origin in args.origin):
        parser.error('Origins must be exact HTTP loopback origins with an explicit port.')
    if args.ads_fixture_store and args.command != 'serve-fixtures':
        parser.error('Ad fixtures require serve-fixtures; live finance is a separate authorization.')
    if bool(args.correction) != (args.command == 'resume-local'):
        parser.error('--correction is required only for resume-local.')
    root = Path(__file__).resolve().parents[2]
    ads = None
    try:
        if args.command in ('initialize-local', 'status-local', 'resume-local'):
            from .local_budget import LocalEvaluationLedger, default_local_ledger_path
            from .local_runtime import local_status
            path = default_local_ledger_path(root)
            if args.command == 'initialize-local':
                LocalEvaluationLedger.initialize(path, actor=args.actor, unit_cost_micros=5000)
            elif args.command == 'resume-local':
                LocalEvaluationLedger(path, actor=args.actor).resume(correction=args.correction)
            print(json.dumps(local_status(root, actor=args.actor), sort_keys=True), flush=True)
            return 0
        if args.command == 'serve-live-local':
            from .local_runtime import create_local_search_application
            app = create_local_search_application(root, actor=args.actor)
        else:
            provider = FixtureProvider() if args.command == 'serve-fixtures' else None
            if args.ads_fixture_store:
                from wingman_ads.service import open_fixture_service
                ads = open_fixture_service(args.ads_fixture_store)
            app = SearchApplication(provider, ads=ads, mode='fixtures' if provider else 'disabled')
        print(json.dumps({'mode': app.mode, 'bind': f'http://127.0.0.1:{args.port}',
                          'actor': args.actor if app.mode == 'local-live' else None,
                          'automaticRequests': False, 'stop': 'Ctrl-C'}, sort_keys=True), flush=True)
        serve(app, port=args.port, origins=args.origin)
        return 0
    except KeyboardInterrupt:
        return 0
    except BudgetError as exc:
        # Ledger codes are fixed enums; never serialize arbitrary exceptions.
        print(json.dumps({'status': 'error', 'code': 'allowance-unavailable',
                          'action': 'Inspect status-local; preserve the existing grant and ledger.'}), flush=True)
        return 2
    except OSError:
        print(json.dumps({'status': 'error', 'code': 'local-startup-failed',
                          'action': 'Check local file permissions and port availability; do not stop unrelated processes.'}), flush=True)
        return 2
    except Exception as exc:
        from .local_runtime import LocalRuntimeError, DIAGNOSTICS
        code = exc.code if isinstance(exc, LocalRuntimeError) else 'local-startup-failed'
        print(json.dumps({'status': 'error', 'code': code,
                          'action': DIAGNOSTICS.get(code, 'Inspect local configuration without replacing the ledger.')}), flush=True)
        return 2
    finally:
        if ads:
            ads.close()


if __name__ == '__main__':
    raise SystemExit(main())
