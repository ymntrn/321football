"""
The orchestrator — runs the whole pipeline end to end.

    python build_database.py            # run every step, stopping on failure
    python build_database.py --from 2   # resume from step 2
    python build_database.py --only 4   # run just one step

Every step is independently re-runnable and the expensive one (step 2)
is resumable, so a crash or a Ctrl-C never costs you more than the chunk
that was in flight.

Expect the full build to take a few hours, almost all of it in step 2 —
that's Wikidata's rate limits, not your machine. You can stop and resume
whenever you like.
"""

from __future__ import annotations

import argparse
import sys
import time

import config
import db

STEPS = [
    (0, "Resolve league QIDs",        "resolve_leagues"),
    (1, "Discover clubs per league",  "scrape_clubs"),
    (2, "Scrape player spells",       "scrape_players"),
    (3, "Enrich prestige + aliases",  "enrich"),
    (4, "Curate nicknames + labels",  "curate"),
    (5, "Player fame + era filter",   "enrich_players"),
    (6, "Compute fame scores",        "compute_fame_scores"),
    (7, "Build practice pairs",       "build_practice_pairs"),
    (8, "Verify the database",        "verify"),
]


def run_step(number: int, title: str, module_name: str) -> int:
    print("\n" + "=" * 72)
    print(f"STEP {number}: {title}")
    print("=" * 72)

    started = time.time()
    module = __import__(module_name)
    code = module.main()
    elapsed = time.time() - started

    print(f"\n-- step {number} finished in {elapsed / 60:.1f} min (exit {code})")
    return code


def main() -> int:
    parser = argparse.ArgumentParser(description="Build the 321 Football Challenge database")
    parser.add_argument("--from", dest="start", type=int, default=0,
                        help="resume from this step number")
    parser.add_argument("--only", dest="only", type=int, default=None,
                        help="run only this step")
    parser.add_argument("--keep-going", action="store_true",
                        help="continue even if a step reports a problem")
    args = parser.parse_args()

    conn = db.connect()
    db.init_schema(conn)
    conn.close()
    print(f"Database: {config.DB_PATH}")
    print(f"Cutoff:   {config.CUTOFF_YEAR} (rule: {config.INCLUDE_SPELL_RULE})")

    if args.only is not None:
        steps = [s for s in STEPS if s[0] == args.only]
        if not steps:
            valid = ", ".join(str(s[0]) for s in STEPS)
            print(f"\nNo such step: {args.only}. Valid steps are: {valid}")
            return 2
    else:
        steps = [s for s in STEPS if s[0] >= args.start]
        if not steps:
            valid = ", ".join(str(s[0]) for s in STEPS)
            print(f"\n--from {args.start} skips every step. Valid steps are: {valid}")
            return 2

    overall_started = time.time()
    for number, title, module_name in steps:
        code = run_step(number, title, module_name)
        if code != 0 and not args.keep_going:
            print(f"\nStopped at step {number} ({title}).")
            print("Fix the problem above, then resume with:")
            print(f"    python build_database.py --from {number}")
            return code

    print("\n" + "=" * 72)
    print(f"BUILD COMPLETE in {(time.time() - overall_started) / 60:.1f} minutes")
    print("=" * 72)
    print(f"\nYour database is at:\n    {config.DB_PATH}")
    print("\nCopy that file into your Flutter project's assets/ folder to ship it.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
