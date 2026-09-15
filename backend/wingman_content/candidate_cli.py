"""Private local operator commands; these routes are never part of the HTTP service."""
import argparse
import fcntl
import json
from pathlib import Path
from .candidates import (atomic_json, build_report, import_csv, promotion_patch,
                         read_json, report_markdown, validate_inventory)
from .candidate_probe import run_validation


def main(argv=None):
    parser = argparse.ArgumentParser(description="Review-preserving Wingman feed candidates")
    parser.add_argument("command", choices=("candidates-import", "candidates-validate", "candidates-report", "candidates-promote"))
    parser.add_argument("--input", default="backend/candidate_data/wingman_feed_candidates.csv")
    parser.add_argument("--candidates", default="backend/candidate_data/candidates.json")
    parser.add_argument("--config", default="backend/sources.json")
    parser.add_argument("--state", default="work/feed-candidates/validation.json")
    parser.add_argument("--reviews", default="backend/candidate_data/reviews.json")
    parser.add_argument("--output", default="work/feed-candidates/report.json")
    parser.add_argument("--batch-size", type=int, default=24)
    parser.add_argument("--concurrency", type=int, default=3)
    parser.add_argument("--run-seconds", type=int, default=240)
    parser.add_argument("--priority-record", action="append", default=[])
    parser.add_argument("--allow-input-changes", action="store_true",
                        help="Explicitly accept a different inventory; original row validation still applies")
    parser.add_argument("--record-id")
    parser.add_argument("--review-id")
    parser.add_argument("--compatibility-raw", help="Bounded retained original bytes for reviewed compatibility reproduction")
    args = parser.parse_args(argv)
    config = read_json(args.config, {"sources": []})
    if args.command == "candidates-import":
        inventory = import_csv(Path(args.input).read_bytes(), read_json(args.candidates), config,
                               args.input, expected=not args.allow_input_changes)
        atomic_json(args.candidates, inventory)
        print(json.dumps(inventory["counts"], indent=2))
        return
    inventory = validate_inventory(read_json(args.candidates))
    reviews = read_json(args.reviews, {"schemaVersion": 1, "decisions": []})
    if args.command == "candidates-validate":
        lock_path = Path(args.state).with_suffix(".lock")
        lock_path.parent.mkdir(parents=True, exist_ok=True)
        with lock_path.open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            _, summary = run_validation(inventory, read_json(args.state), args.state, reviews,
                                        batch_size=args.batch_size, concurrency=args.concurrency,
                                        run_seconds=args.run_seconds, priority_records=args.priority_record)
        print(json.dumps(summary, indent=2))
        return
    state = read_json(args.state, {})
    if args.command == "candidates-promote":
        if not args.record_id or not args.review_id:
            parser.error("Promotion requires --record-id and --review-id")
        original = None
        if args.compatibility_raw:
            raw_path = Path(args.compatibility_raw)
            if raw_path.stat().st_size > 2 * 1024 * 1024:
                raise ValueError("Compatibility input byte limit")
            original = raw_path.read_bytes()
        value = promotion_patch(inventory, state, reviews, args.record_id, args.review_id, config,
                                compatibility_bytes=original)
        # Run the existing production validator against the combined source set.
        # The reviewed root config is never mutated by this command.
        from .config import load_config
        import tempfile
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "proposed.json"
            proposed = config["sources"] + ([value["source"]] if value['action'] == 'add-reviewed-source' else [])
            atomic_json(path, dict(config, sources=proposed))
            load_config(path)
        atomic_json(args.output, value)
        print(json.dumps({"written": args.output, "action": value["action"]}))
        return
    report = build_report(inventory, state, reviews, config)
    atomic_json(args.output, report)
    Path(args.output).with_suffix(".md").write_text(report_markdown(report), encoding="utf-8")
    print(json.dumps({"written": args.output, "inventory": report["inventory"],
                      "checks": report["uniqueEndpointChecks"]}, indent=2))


if __name__ == "__main__":
    main()
