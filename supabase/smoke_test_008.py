"""Checks 008_friends.sql: request, accept/decline, remove, leaderboards.

Run:  python supabase\\smoke_test_008.py      (makes three anonymous users)
"""
from sbclient import Player, ok, done

a, b, c = Player(), Player(), Player()
_, pa = a.rpc("create_profile", p_username="Smoke_A")
_, pb = b.rpc("create_profile", p_username="Smoke_B")
_, pc = c.rpc("create_profile", p_username="Smoke_C")

print("== find_player ==")
_, p = a.rpc("find_player", p_username="smoke_b", p_tag=pb["tag"].lower())
ok("case-insensitive exact match", p and p.get("id") == b.id, p)
_, p = a.rpc("find_player", p_username="SmokeXB", p_tag=pb["tag"])
ok("underscore is not a wildcard", not p or p.get("id") is None, p)

print()
print("== request -> accept ==")
status, _ = a.rpc("send_friend_request", p_username="Nobody", p_tag="AAAA")
ok("unknown player refused", status >= 400, status)
status, _ = a.rpc("send_friend_request", p_username="Smoke_A", p_tag=pa["tag"])
ok("self refused", status >= 400, status)
_, s = a.rpc("send_friend_request", p_username="Smoke_B", p_tag=pb["tag"])
ok("sent", s == "sent", s)
_, rows = b.rpc("my_friends")
ok("b sees one incoming", len(rows) == 1 and rows[0]["incoming"], rows)
b.rpc("respond_friend_request", p_requester=a.id, p_accept=True)
_, rows = a.rpc("my_friends")
ok("accepted", rows and rows[0]["status"] == "accepted", rows)
status, rows = c.call("GET", "/rest/v1/friendships?select=*")
ok("c reads no friendships", status == 200 and rows == [], (status, rows))

print()
print("== decline, reverse-accept, remove ==")
c.rpc("send_friend_request", p_username="Smoke_A", p_tag=pa["tag"])
a.rpc("respond_friend_request", p_requester=c.id, p_accept=False)
_, rows = c.rpc("my_friends")
ok("declined request gone", rows == [], rows)
c.rpc("send_friend_request", p_username="Smoke_A", p_tag=pa["tag"])
_, s = a.rpc("send_friend_request", p_username="Smoke_C", p_tag=pc["tag"])
ok("adding someone who asked you accepts", s == "accepted", s)
_, lb = a.rpc("friends_leaderboard")
ok("friends leaderboard = me + 2", len(lb) == 3, [r["username"] for r in lb])
a.rpc("remove_friend", p_other=b.id)
_, rows = a.rpc("my_friends")
ok("removed b", all(r["id"] != b.id for r in rows), rows)
status, _ = a.call("POST", "/rest/v1/friendships",
                   {"requester": a.id, "addressee": b.id})
ok("direct insert refused", status >= 400, status)

print()
print("== global leaderboard ==")
status, top = a.call("GET", "/rest/v1/profiles?select=id,username,tag,trophies"
                     "&order=trophies.desc,id.asc&limit=100")
ok("top 100 readable", status == 200 and len(top) >= 3, status)
_, rank = a.rpc("my_rank")
ok("my_rank is a positive int", isinstance(rank, int) and rank >= 1, rank)
done()
