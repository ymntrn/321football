"""Applies every migration to a throwaway local Postgres and runs SQL checks.

Cloud sessions have no route to the real project, so this is how the SQL in
this folder gets executed before it reaches Supabase. NOT a substitute for the
smoke_test_00N.py scripts, which run against the real project over HTTP.

    python supabase/localpg/harness.py         (needs a Postgres 16 on
                                                 /tmp:5499, user postgres)
"""
import contextlib
import pathlib
import re
import sys
import uuid

import psycopg2

HERE = pathlib.Path(__file__).resolve().parent
SUPA = HERE.parent
DSN = "host=/tmp port=5499 user=postgres"
MIGRATIONS = ["schema.sql", "002_fix_grants.sql", "003_match_flow.sql",
              "004_forfeit_rematch_cleanup.sql", "005_void_from_picking.sql"]
MIGRATIONS += sorted(p.name for p in SUPA.glob("0[0-9][0-9]_*.sql")
                     if p.name >= "006")


def fresh():
    admin = psycopg2.connect(DSN + " dbname=postgres")
    admin.autocommit = True
    with admin.cursor() as cur:
        cur.execute("drop database if exists t321")
        cur.execute("create database t321")
    admin.close()
    conn = psycopg2.connect(DSN + " dbname=t321")
    conn.autocommit = True
    with conn.cursor() as cur:
        stubs = (HERE / "stubs.sql").read_text()
        # roles are cluster-wide: tolerate them already existing
        stubs = re.sub(r"create role (\w+) ([^;]*);",
                       r"do $$ begin create role \1 \2; exception when duplicate_object then end $$;",
                       stubs)
        cur.execute(stubs)
        for name in MIGRATIONS:
            sql = (SUPA / name).read_text(encoding="utf-8")
            sql = sql.replace("create extension if not exists pg_cron;", "")
            cur.execute(sql)
            print("applied", name)
    return conn


class User:
    """Runs statements as the `authenticated` role with auth.uid() = id."""

    def __init__(self, conn, uid=None):
        self.conn = conn
        self.id = uid or str(uuid.uuid4())
        with conn.cursor() as cur:
            cur.execute("insert into auth.users (id) values (%s) on conflict do nothing",
                        (self.id,))

    def q(self, sql, params=None):
        with self.conn.cursor() as cur:
            cur.execute("begin")
            try:
                cur.execute("set local role authenticated")
                cur.execute("select set_config('request.jwt.claim.sub', %s, true)", (self.id,))
                cur.execute(sql, params)
                rows = None
                if cur.description:
                    cols = [d[0] for d in cur.description]
                    rows = [dict(zip(cols, r)) for r in cur.fetchall()]
                cur.execute("commit")
                return rows
            except Exception:
                cur.execute("rollback")
                raise

    def one(self, sql, params=None):
        rows = self.q(sql, params)
        return rows[0] if rows else None

    def fails(self, sql, params=None):
        try:
            self.q(sql, params)
            return None
        except psycopg2.Error as e:
            return str(e).splitlines()[0]


fails = 0


def ok(label, cond, detail=""):
    global fails
    if not cond:
        fails += 1
    print(("  PASS  " if cond else "  FAIL  ") + label + ("  " + str(detail) if detail else ""))


if __name__ == "__main__":
    conn = fresh()
    sys.path.insert(0, str(HERE))
    for test in sorted(HERE.glob("check_*.py")):
        print("==", test.name)
        ns = {"conn": conn, "User": User, "ok": ok}
        exec(compile(test.read_text(encoding="utf-8"), str(test), "exec"), ns)
    print()
    print("FAILURES:", fails)
    sys.exit(1 if fails else 0)
