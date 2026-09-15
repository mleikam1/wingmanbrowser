import argparse
import fcntl
import json
import os
import sys
from pathlib import Path
from .config import load_config, registry
from .normalize import DestinationPolicy
from .provider import ingest, RssAtomProvider
from .store import LocalStore, GCSStore
from .server import serve


def main():
    if len(sys.argv) > 1 and sys.argv[1].startswith("candidates-"):
        from .candidate_cli import main as candidates_main
        candidates_main(sys.argv[1:])
        return
    parser = argparse.ArgumentParser(description="Wingman shared content ingestion / read-only service")
    parser.add_argument("command", choices=("ingest", "serve", "registry"))
    parser.add_argument("--config", default=os.environ.get("SOURCE_CONFIG", "backend/sources.json"))
    parser.add_argument("--store", default=os.environ.get("CONTENT_STORE", "work/live-content/store"))
    parser.add_argument("--baseline", default=os.environ.get("CONSUMER_BASELINE", "assets/policy/consumer_protection.json"))
    parser.add_argument("--bucket", default=os.environ.get("CONTENT_BUCKET"))
    parser.add_argument("--project", default=os.environ.get("CONTENT_PROJECT"))
    parser.add_argument("--host", default=os.environ.get("HOST", "127.0.0.1"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("PORT", "8891")))
    parser.add_argument("--output", default="assets/live_content/sources.json")
    args = parser.parse_args()
    if args.command == "registry":
        target = Path(args.output)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(registry(load_config(args.config)), indent=2) + "\n")
        return
    store = GCSStore(args.bucket, project=args.project) if args.bucket else LocalStore(args.store)
    if args.command == "serve":
        serve(store, args.host, args.port)
        return
    config = load_config(args.config)
    provider = RssAtomProvider(DestinationPolicy(args.baseline))
    # Local CLI overlap is serialized. GCS uses generation preconditions instead.
    if isinstance(store, LocalStore):
        with (store.directory / "ingest.lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            snapshot, report = ingest(config, store, provider)
    else:
        snapshot, report = ingest(config, store, provider)
    print(json.dumps({"generatedAt": snapshot["generatedAt"], "snapshotId": snapshot["snapshotId"],
                      "items": len(snapshot["items"]), "sources": report}, indent=2))


if __name__ == "__main__":
    main()
