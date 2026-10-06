import pathlib
import psycopg2

uri = (pathlib.Path(__file__).resolve().parent / ".pgpass.local").read_text().strip()
c = psycopg2.connect(uri, connect_timeout=15)
c.autocommit = True
cur = c.cursor()


def q(title, sql):
    cur.execute(sql)
    print("== %s ==" % title)
    for r in cur.fetchall():
        print("  ", r)
    print()


q("cron jobs", "select jobname, schedule, active from cron.job order by jobname")
q("rooms by phase", "select phase, count(*) from public.rooms group by phase order by 1")
q("closed by the sweep", """
  select code, phase, ended_reason, host_name, guest_name
    from public.rooms where ended_reason = 'abandoned' order by code
""")
q("new functions", """
  select routine_name from information_schema.routines
   where routine_schema = 'public'
     and routine_name in ('claim_forfeit','leave_match','rematch',
                          'active_room_for','abandon_stale_matches')
   order by 1
""")
c.close()
