import argparse
import json
import os
import sys
from pathlib import Path
from .config import load_config, registry
from .normalize import DestinationPolicy
from .provider import ingest, RssAtomProvider, CompositeNewsProvider
from .store import LocalStore, GCSStore
from .server import serve


def main():
    if len(sys.argv) > 1 and sys.argv[1].startswith("candidates-"):
        from .candidate_cli import main as candidates_main
        candidates_main(sys.argv[1:])
        return
    parser = argparse.ArgumentParser(description="Wingman shared content ingestion / read-only service")
    parser.add_argument("command", choices=("ingest", "serve", "registry", "diagnostics",
                                            "currents-init", "currents-setup", "currents-bootstrap", "currents-status"))
    parser.add_argument("--config", default=os.environ.get("SOURCE_CONFIG", "backend/sources.json"))
    parser.add_argument("--store", default=os.environ.get("CONTENT_STORE", "work/live-content/store"))
    parser.add_argument("--baseline", default=os.environ.get("CONSUMER_BASELINE", "assets/policy/consumer_protection.json"))
    parser.add_argument("--bucket", default=os.environ.get("CONTENT_BUCKET"))
    parser.add_argument("--project", default=os.environ.get("CONTENT_PROJECT"))
    parser.add_argument("--host", default=os.environ.get("HOST", "127.0.0.1"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("PORT", "8891")))
    parser.add_argument("--output")
    parser.add_argument('--ledger', default=os.environ.get('CURRENTS_LEDGER',
                                                         'work/wingman-operations/currents-ledger.sqlite3'))
    parser.add_argument('--ledger-object', default=os.environ.get('CURRENTS_LEDGER_OBJECT',
                                                                'wingman-operations/currents-ledger.json'))
    parser.add_argument('--secret-file', default=os.environ.get('CURRENTS_SECRET_FILE', 'backend/.env.currents'))
    parser.add_argument('--replace-credential', action='store_true',
                        help='Deliberate one-time credential replacement; never resets the daily ledger')
    args = parser.parse_args()
    if args.command == "registry":
        target = Path(args.output or "assets/live_content/sources.json")
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(registry(load_config(args.config)), indent=2) + "\n")
        return
    store = GCSStore(args.bucket, project=args.project) if args.bucket else LocalStore(args.store)
    if args.command == 'diagnostics':
        from .diagnostics import export_diagnostics
        data = json.dumps(export_diagnostics(load_config(args.config), store.read()), indent=2) + '\n'
        if args.output:
            target = Path(args.output)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(data)
        else:
            print(data, end='')
        return
    if args.command == "serve":
        serve(store, args.host, args.port)
        return
    # The read service never constructs the gateway or reads provider credentials.
    from .currents_budget import LocalLedger, GCSLedger
    from .currents import CurrentsProvider, BudgetGateway
    ledger = (GCSLedger(args.bucket, project=args.project, object_name=args.ledger_object)
              if args.bucket else LocalLedger(args.ledger))
    if args.command == 'currents-init':
        ledger.initialize()
        print(json.dumps({'status': 'initialized', 'dailyHardCap': 150}))
        return
    if args.command == 'currents-status':
        print(json.dumps(ledger.diagnostics(), indent=2))
        return
    from .secret import load_currents_secret
    key = load_currents_secret(args.secret_file)
    policy = DestinationPolicy(args.baseline)
    currents = CurrentsProvider(policy, BudgetGateway(ledger, key=key)) if key else None
    if args.command == 'currents-setup':
        if currents is None:
            parser.error('Set the backend secret using python3 backend/setup_currents_secret.py first')
        result = currents.setup(replace_credential=args.replace_credential)
        print(json.dumps(result, indent=2))
        return
    if args.command == 'currents-bootstrap' and currents is None:
        parser.error('Set the backend secret using python3 backend/setup_currents_secret.py first')
    config = load_config(args.config)
    provider = CompositeNewsProvider(RssAtomProvider(policy), currents)
    if args.command == 'currents-bootstrap':
        class BootstrapProvider:
            def bind_writer_guard(self, guard):
                currents.gateway.before_request = guard

            def refresh(self, source, prior, now):
                if source.get('providerId') == 'currents':
                    return currents.bootstrap(source, prior)
                # Preserve other approved content; bootstrap never refetches RSS.
                return dict(prior, lastHttpStatus=prior.get('lastHttpStatus') or 200)
        provider = BootstrapProvider()
    # Store writer context owns the cross-process/job lease and publication fence.
    snapshot, report = ingest(config, store, provider)
    print(json.dumps({"generatedAt": snapshot["generatedAt"], "snapshotId": snapshot["snapshotId"],
                      "items": len(snapshot["items"]), "sources": report}, indent=2))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # Provider exceptions or environment values must never reach logs.
        print('Content operation stopped safely. Inspect currents-status and local configuration; no credential was logged.',
              file=sys.stderr)
        sys.exit(1)
