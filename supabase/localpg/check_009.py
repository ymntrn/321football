import time
a, b, far, bot = User(conn), User(conn), User(conn), User(conn)
a.one("select * from create_profile('Aaa')"); b.one("select * from create_profile('Bbb')")
far.one("select * from create_profile('Far')"); bot.one("select * from create_profile('Bot')")
with conn.cursor() as cur:
    cur.execute("update profiles set trophies=1000 where id=%s", (a.id,))
    cur.execute("update profiles set trophies=1080 where id=%s", (b.id,))
    cur.execute("update profiles set trophies=1500 where id=%s", (far.id,))
    cur.execute("update profiles set trophies=0 where id=%s", (bot.id,))
nope = User(conn)
ok("no profile refused", nope.fails("select * from find_match()"))
r = a.one("select * from find_match()")
ok("alone: no room", r["code"] is None, r)
r = far.one("select * from find_match()")
ok("1500 vs 1000: out of window", r["code"] is None)
r = b.one("select * from find_match()")
ok("b finds a (diff 80)", r["code"] is not None and r["ranked"], r)
ok("room in picking, round 1", r["phase"] == "picking" and r["round"] == 1)
ok("finder hosts", str(r["host_id"]) == b.id and str(r["guest_id"]) == a.id)
ra = a.one("select * from find_match()")
ok("a's next poll returns the same room", ra["code"] == r["code"])
ok("a can read the room", a.one("select code from rooms where code=%s", (r["code"],)))
ok("queue empty of a and b", a.one("select * from find_match()")["code"] is None)  # a re-queues
a.one("select * from leave_queue()")
# window widening: far waits; pretend far joined 25 s ago -> window 600
with conn.cursor() as cur:
    cur.execute("update match_queue set joined_at = now() - interval '25 seconds', seen_at = now() where player_id=%s", (far.id,))
c = User(conn); c.one("select * from create_profile('Ccc')")
with conn.cursor() as cur:
    cur.execute("update profiles set trophies=1000 where id=%s", (c.id,))
r = c.one("select * from find_match()")
ok("widened window pairs 1000 with 1500 after 25 s", r["code"] is not None, r)
# prefer_guest: bot queues first, app finds it -> app hosts; bot first then app
r = bot.one("select * from find_match(true)")
ok("bot waits", r["code"] is None)
z = User(conn); z.one("select * from create_profile('App')")
r = z.one("select * from find_match()")
ok("app (finder) hosts vs bot", str(r["host_id"]) == z.id and str(r["guest_id"]) == bot.id, r)
bot.one("select * from find_match(true)")
y = User(conn); y.one("select * from create_profile('App2')")
y.one("select * from find_match()")       # app queues first
r = bot.one("select * from find_match(true)")  # bot finds app
ok("bot finding still makes the app host", str(r["host_id"]) == y.id, r)
# cancel
q = User(conn); q.one("select * from create_profile('Quit')")
with conn.cursor() as cur:
    cur.execute("update profiles set trophies=9000 where id=%s", (q.id,))
q.one("select * from find_match()")
ok("cancel returns no room", q.one("select * from leave_queue()")["code"] is None)
ok("queue not readable directly", q.fails("select * from match_queue"))
# full ranked match through to results
code = r["code"]
