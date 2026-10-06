"""Apply a .sql migration straight to the database.

    python supabase\migrate.py supabase\004_whatever.sql
    python supabase\migrate.py --check          (just prove the connection)

The password is read from the PGURI environment variable, or from
supabase\.pgpass.local (one line, the full connection URI). That file is
deliberately NOT part of the source: it holds full read/write/drop control of
the database, unlike the publishable key shipped in the app.

Supabase's direct connection (db.<ref>.supabase.co:5432) is IPv6-only on the
free plan. If that fails, the transaction pooler on port 6543 is reachable
over IPv4 and is tried as a fallback — it cannot run every statement type,
but it is fine for ordinary DDL.
"""
import os
import pathlib
import sys

import psycopg2

HERE = pathlib.Path(__file__).resolve().parent
SECRET = HERE / ".pgpass.local"


def uri():
    value = os.environ.get("PGURI")
    if value:
        return value.strip()
    if SECRET.exists():
        return SECRET.read_text(encoding="utf-8").strip()
    sys.exit("No connection URI. Set PGURI or create supabase\\.pgpass.local")


def pooler_uri(direct):
    """Rewrite a direct URI into the transaction-pooler form."""
    # postgresql://postgres:PW@db.REF.supabase.co:5432/postgres
    #   -> postgresql://postgres.REF:PW@aws-0-eu-central-1.pooler.supabase.com:6543/postgres
    try:
        rest = direct.split("://", 1)[1]
        creds, hostpart = rest.rsplit("@", 1)
        user, pw = creds.split(":", 1)
        host = hostpart.split(":", 1)[0]
        ref = host.split(".")[1]
        region = os.environ.get("SUPABASE_REGION", "eu-central-1")
        return ("postgresql://%s.%s:%s@aws-0-%s.pooler.supabase.com:6543/postgres"
                % (user, ref, pw, region))
    except Exception:
        return None


def connect():
    direct = uri()
    try:
        return psycopg2.connect(direct, connect_timeout=15), "direct"
    except Exception as e:
        print("   direct connection failed: %s" % str(e).strip()[:160])
        alt = pooler_uri(direct)
        if not alt:
            raise
        print("   trying the transaction pooler over IPv4 ...")
        return psycopg2.connect(alt, connect_timeout=15), "pooler"


def main():
    args = [a for a in sys.argv[1:]]
    conn, how = connect()
    conn.autocommit = True
    print("connected (%s)" % how)

    with conn.cursor() as cur:
        cur.execute("select current_database(), current_user, version()")
        db, user, version = cur.fetchone()
        print("   %s as %s" % (db, user))
        print("   %s" % version.split(",")[0])

        if not args or args[0] == "--check":
            cur.execute("""select table_name from information_schema.tables
                            where table_schema='public' order by 1""")
            print("   tables:", [r[0] for r in cur.fetchall()])
            return

        for path in args:
            sql = pathlib.Path(path).read_text(encoding="utf-8")
            print("applying %s (%d bytes) ..." % (path, len(sql)))
            cur.execute(sql)
            print("   ok")

    conn.close()


if __name__ == "__main__":
    main()
