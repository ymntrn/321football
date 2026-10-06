"""Checks 009_matchmaking.sql: queue, pair within the window, cancel.

Run:  python supabase\\smoke_test_009.py      (makes two anonymous users)

New players start at 0 trophies, so two fresh users are always within the
+-100 window. Run it when nobody else is queueing for ranked.
"""
import time

from sbclient import Player, ok, done

a, b = Player(), Player()
a.rpc("create_profile", p_username="Queue_A")
b.rpc("create_profile", p_username="Queue_B")

print("== cancel ==")
_, r = a.rpc("find_match")
ok("alone: no room yet", not r or r.get("code") is None, r)
_, r = a.rpc("leave_queue")
ok("cancel: no room", not r or r.get("code") is None, r)
status, rows = a.call("GET", "/rest/v1/match_queue?select=*")
ok("queue not readable directly", status >= 400 or rows == [], (status, rows))

print()
print("== pair ==")
a.rpc("find_match")
time.sleep(0.5)
_, rb = b.rpc("find_match")
ok("b pairs with a", rb and rb.get("code"), rb)
ok("ranked room in picking, round 1",
   rb.get("ranked") and rb.get("phase") == "picking" and rb.get("round") == 1, rb)
ok("finder (b) hosts", rb.get("host_id") == b.id and rb.get("guest_id") == a.id)
_, ra = a.rpc("find_match")
ok("a's next poll returns the same room", ra and ra.get("code") == rb.get("code"), ra)
ok("a can read it", a.get_room(rb["code"]) is not None)

print()
print("== prefer_guest (the bot) ==")
bot, app = Player(), Player()
bot.rpc("create_profile", p_username="Queue_Bot")
app.rpc("create_profile", p_username="Queue_App")
app.rpc("find_match")
time.sleep(0.5)
_, r = bot.rpc("find_match", p_prefer_guest=True)
ok("bot finds app, app still hosts", r and r.get("host_id") == app.id, r)

# Close both rooms so they do not linger as active matches.
for p, code in ((a, rb["code"]), (app, r["code"] if r else None)):
    if code:
        p.rpc("leave_match", p_code=code, p_seat="host" if p is app else "guest")
done()
