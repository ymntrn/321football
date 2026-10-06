"""Remove the throwaway players that smoke tests and old bot runs leave behind.

Every smoke test signs in anonymously and creates real profiles (SmokeHost,
Queue_A, Smoke_B ...), and before 6 Oct 2026 every bot.py run created a new
`Bot#XXXX`. They all show on the Global leaderboard.

    python supabase\\purge_test_accounts.py              # list only
    python supabase\\purge_test_accounts.py --apply      # delete them
    python supabase\\purge_test_accounts.py --keep FL3Z --apply

What counts as a test account:
  * a profile whose username starts with Smoke, Queue_, Test or Kanka, or is
    exactly `Bot` (except tags passed with --keep, e.g. the saved bot), or
    whose tag is passed with --also
  * an anonymous auth user with no profile at all (an install or a script
    that never chose a username)

Deleting is permanent: their friendships, queue entries, profile and auth
user go. Rooms are left alone (pg_cron purges them after a day).
Reads the database URI from supabase/.pgpass.local, like migrate.py.
"""
import argparse
import os
import psycopg2

HERE = os.path.dirname(os.path.abspath(__file__))
ap = argparse.ArgumentParser()
ap.add_argument("--apply", action="store_true", help="actually delete")
ap.add_argument("--keep", nargs="*", default=[], help="tags never to delete")
ap.add_argument("--also", nargs="*", default=[], help="extra tags to delete")
args = ap.parse_args()
keep = [t.upper() for t in args.keep]
also = [t.upper() for t in args.also]

conn = psycopg2.connect(open(os.path.join(HERE, ".pgpass.local")).read().strip())
cur = conn.cursor()

cur.execute("""
  select p.id, p.username || '#' || p.tag, p.trophies, p.matches_played
    from public.profiles p
   where (p.username ~ '^(Smoke|Queue_|Test|Kanka)' or p.username = 'Bot'
          or upper(p.tag) = any(%s))
     and not (upper(p.tag) = any(%s))
  union all
  select u.id, '(anonymous, no profile)', null, null
    from auth.users u
   where u.is_anonymous
     and not exists (select 1 from public.profiles p where p.id = u.id)
   order by 2
""", (also, keep))
rows = cur.fetchall()
for uid, name, trophies, played in rows:
    extra = "" if trophies is None else "  trophies %s, matches %s" % (trophies, played)
    print("  %-28s %s%s" % (name, uid, extra))
print("%d account(s)" % len(rows))

if not args.apply:
    print("dry run - nothing deleted. Add --apply to delete these.")
    raise SystemExit(0)

ids = [r[0] for r in rows]
if ids:
    cur.execute("delete from public.friendships where requester = any(%s::uuid[]) "
                "or addressee = any(%s::uuid[])", (ids, ids))
    cur.execute("delete from public.match_queue where player_id = any(%s::uuid[])", (ids,))
    cur.execute("delete from public.profiles where id = any(%s::uuid[])", (ids,))
    cur.execute("delete from auth.users where id = any(%s::uuid[])", (ids,))
conn.commit()
print("deleted %d account(s)" % len(ids))
