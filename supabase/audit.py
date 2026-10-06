import pathlib
import psycopg2

HERE = pathlib.Path(__file__).resolve().parent
uri = (HERE / ".pgpass.local").read_text(encoding="utf-8").strip()
c = psycopg2.connect(uri, connect_timeout=15)
c.autocommit = True
cur = c.cursor()

def show(title, sql, args=None):
    print("== %s ==" % title)
    cur.execute(sql, args or ())
    for row in cur.fetchall():
        print("  ", row)
    print()

show("rooms accumulated", """
  select count(*) as total,
         count(*) filter (where phase = 'match_over') as finished,
         count(*) filter (where phase = 'lobby')      as never_started,
         count(*) filter (where phase not in ('lobby','match_over')) as mid_match,
         min(created_at)::date as oldest
    from public.rooms
""")

show("is pg_cron available", """
  select name, installed_version, default_version
    from pg_available_extensions
   where name in ('pg_cron','pg_net')
""")

show("realtime publication members", """
  select schemaname, tablename
    from pg_publication_tables
   where pubname = 'supabase_realtime'
""")

show("rooms stuck mid-match (nobody will ever finish these)", """
  select code, phase, round, host_name, guest_name,
         host_seen_at, guest_seen_at,
         now() - greatest(coalesce(host_seen_at, created_at),
                          coalesce(guest_seen_at, created_at)) as silent_for
    from public.rooms
   where phase not in ('lobby','match_over')
   order by created_at desc limit 10
""")

show("flow functions present", """
  select routine_name
    from information_schema.routines
   where routine_schema = 'public'
   order by routine_name
""")

c.close()
