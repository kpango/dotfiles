#!/usr/bin/env python3
"""Disable superseded duplicate api_key credentials in OMP's agent.db.

OMP selects the first enabled api_key row per provider ordered by id ASC, so a
stale older login silently shadows a newer valid one. This keeps the newest
enabled api_key row per provider and marks older ones with OMP's own
disabled_cause mechanism (reversible; no rows are deleted). OAuth rows are never
touched. A timestamped backup is taken before any write. Secret values are
never printed.
"""
import argparse
import os
import sqlite3
import sys
import time

DEFAULT_DB = os.path.expanduser("~/.omp/agent/agent.db")
CAUSE = "superseded: newer api_key login"


def dedupe(db_path, apply):
    if not os.path.exists(db_path):
        print(f"omp-auth-dedupe: {db_path} not found; nothing to do")
        return 0

    con = sqlite3.connect(db_path, timeout=10)
    try:
        rows = con.execute(
            "SELECT id, provider FROM auth_credentials "
            "WHERE credential_type = 'api_key' AND disabled_cause IS NULL "
            "ORDER BY provider, id"
        ).fetchall()
        by_provider = {}
        for rid, provider in rows:
            by_provider.setdefault(provider, []).append(rid)

        stale = []
        for provider, ids in sorted(by_provider.items()):
            if len(ids) < 2:
                continue
            keep = ids[-1]
            older = ids[:-1]
            print(f"{provider}: keep id={keep}, supersede ids={older}")
            stale.extend(older)

        if not stale:
            print("omp-auth-dedupe: no superseded api_key rows")
            return 0
        if not apply:
            print(f"omp-auth-dedupe: dry-run, {len(stale)} row(s) would be disabled")
            return 0

        backup = f"{db_path}.bak-{int(time.time())}"
        src = sqlite3.connect(db_path, timeout=10)
        dst = sqlite3.connect(backup)
        with dst:
            src.backup(dst)
        dst.close()
        src.close()
        print(f"omp-auth-dedupe: backup written to {backup}")

        now = int(time.time())
        with con:
            for rid in stale:
                con.execute(
                    "UPDATE auth_credentials SET disabled_cause = ?, updated_at = ? "
                    "WHERE id = ? AND disabled_cause IS NULL",
                    (CAUSE, now, rid),
                )
        print(f"omp-auth-dedupe: disabled {len(stale)} row(s)")
        return 0
    finally:
        con.close()


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--db", default=DEFAULT_DB)
    ap.add_argument("--apply", action="store_true", help="write changes (default: dry-run)")
    args = ap.parse_args()
    try:
        return dedupe(args.db, args.apply)
    except sqlite3.Error as e:
        print(f"omp-auth-dedupe: sqlite error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
