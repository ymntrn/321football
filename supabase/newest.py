import pathlib
import psycopg2

uri = (pathlib.Path(__file__).resolve().parent / ".pgpass.local").read_text().strip()
c = psycopg2.connect(uri, connect_timeout=15)
cur = c.cursor()
cur.execute("""
  select code, phase, host_name, guest_name, winner, ended_reason,
         host_score, guest_score
    from public.rooms order by created_at desc limit 1
""")
row = cur.fetchone()
print("code=%s phase=%s host=%s guest=%s winner=%s reason=%s score=%s-%s"
      % row)
c.close()
