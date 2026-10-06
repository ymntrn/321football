"""Checks 006_accounts.sql: anonymous players, profiles, tags, room RLS.

Run:  python supabase\\smoke_test_006.py

Needs anonymous sign-ins enabled (see sbclient.py). Makes three auth users.
"""
import re

from sbclient import Player, anon_call, ok, done

a, b, c = Player(), Player(), Player()

print("== create_profile ==")
status, prof = a.rpc("create_profile", p_username="Yaman")
ok("returns 200", status == 200, status)
ok("id is the auth user", prof.get("id") == a.id)
ok("tag is 4 chars of A-Z/2-9, no 0 O 1 I",
   re.fullmatch(r"[A-HJ-NP-Z2-9]{4}", prof.get("tag", "")), prof.get("tag"))
ok("starts at 0 trophies, 30 coins",
   prof.get("trophies") == 0 and prof.get("coins") == 30)
tag = prof["tag"]

_, again = a.rpc("create_profile", p_username="SomeoneElse")
ok("second call returns the same profile", again.get("tag") == tag
   and again.get("username") == "Yaman", again)

status, _ = b.rpc("create_profile", p_username="ab")
ok("2-char username refused", status >= 400, status)
status, _ = b.rpc("create_profile", p_username="has space")
ok("space refused", status >= 400, status)
status, prof_b = b.rpc("create_profile", p_username="Şükrü_10")
ok("Turkish letters, digit, underscore accepted", status == 200, prof_b)
c.rpc("create_profile", p_username="Yaman")

status, _ = anon_call("POST", "/rest/v1/rpc/create_profile", {"p_username": "Nobody"})
ok("signed-out caller refused", status >= 400, status)

print()
print("== profile RLS and column grants ==")
ok("b can read a's profile", b.profile(a.id) is not None)
status, rows = a.call("PATCH", "/rest/v1/profiles?id=eq." + a.id,
                      {"username": "Yaman2"}, {"Prefer": "return=representation"})
ok("a renames itself", status == 200 and rows and rows[0]["username"] == "Yaman2",
   (status, rows))
ok("tag unchanged after rename", a.profile()["tag"] == tag)
status, _ = a.call("PATCH", "/rest/v1/profiles?id=eq." + a.id, {"coins": 9999})
ok("a cannot write its own coins", status >= 400, status)
status, _ = a.call("PATCH", "/rest/v1/profiles?id=eq." + a.id, {"tag": "AAAA"})
ok("a cannot write its own tag", status >= 400, status)
status, rows = b.call("PATCH", "/rest/v1/profiles?id=eq." + a.id,
                      {"username": "Hijack"}, {"Prefer": "return=representation"})
ok("b cannot rename a", not rows, (status, rows))
status, rows = anon_call("GET", "/rest/v1/profiles?select=id&limit=1")
ok("signed-out caller reads no profiles", status >= 400 or rows == [], (status, rows))

print()
print("== rooms carry auth uids; RLS is the two players ==")
status, room = a.rpc("create_room", p_host_id="00000000-0000-0000-0000-000000000000",
                     p_host_name="Yaman2")
ok("create_room 200", status == 200, status)
code = room["code"]
ok("host_id is the session user, not the parameter", room["host_id"] == a.id)
status, _ = a.rpc("join_room", p_code=code, p_guest_id=a.id, p_guest_name="me")
ok("cannot join own room", status >= 400, status)
status, room = b.rpc("join_room", p_code=code,
                     p_guest_id="00000000-0000-0000-0000-000000000000",
                     p_guest_name="Şükrü_10")
ok("join_room 200, guest_id is b", status == 200 and room["guest_id"] == b.id)

ok("host reads the room", a.get_room(code) is not None)
ok("guest reads the room", b.get_room(code) is not None)
ok("third player cannot read it", c.get_room(code) is None)
status, rows = anon_call("GET", "/rest/v1/rooms?code=eq." + code)
ok("signed-out caller cannot read it", status >= 400 or rows == [], (status, rows))

status, rows = b.patch_room(code, {"guest_club_id": 1, "guest_club_name": "X"})
ok("guest writes its own pick", status == 200 and rows, status)
status, rows = c.patch_room(code, {"host_score": 3})
ok("third player's write touches nothing", not rows, (status, rows))
status, _ = a.call("POST", "/rest/v1/rooms",
                   {"code": "999999", "host_id": a.id, "host_name": "x"})
ok("direct insert refused", status >= 400, status)

done()
