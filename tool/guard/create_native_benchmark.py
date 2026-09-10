#!/usr/bin/env python3
"""Create an unsigned, isolated DEBUG TEST database; never a distributable pack."""
import argparse
from pathlib import Path
import sqlite3

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('output', type=Path)
args = parser.parse_args()
if args.output.exists():
    parser.error('Output already exists; choose a new test path.')
args.output.parent.mkdir(parents=True, exist_ok=True)
with sqlite3.connect(args.output) as db:
    db.execute('CREATE TABLE guard_state(id INTEGER PRIMARY KEY,active_generation INTEGER,previous_generation INTEGER,active_version TEXT,highest_sequence INTEGER,last_check INTEGER)')
    db.execute("INSERT INTO guard_state VALUES(1,1,NULL,'UNSIGNED-DEBUG-PERFORMANCE-ONLY',0,NULL)")
    db.execute('CREATE TABLE guard_rules(generation INTEGER NOT NULL,host TEXT NOT NULL,kind TEXT NOT NULL,category TEXT NOT NULL,include_subdomains INTEGER NOT NULL,rule_id TEXT NOT NULL,PRIMARY KEY(generation,host,kind,category)) WITHOUT ROWID')
    db.executemany('INSERT INTO guard_rules VALUES(?,?,?,?,?,?)',
        ((1, f'host-{i:06d}.benchmark.test', 'category', 'adult', 1, f'fixture-{i}') for i in range(100_000)))
print(f'Created 100,000 synthetic rules at {args.output} ({args.output.stat().st_size:,} bytes).')
