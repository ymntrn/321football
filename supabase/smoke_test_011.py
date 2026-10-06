"""Checks 011_delete_account.sql against the real project: a player with a
friend, an incoming request and a queue entry deletes their account; then
everything of theirs is gone, the friend is untouched, and the old session
no longer resolves to a user.

Run:  python supabase\\smoke_test_011.py      (makes three anonymous users)
"""
from sbclient import Player, anon_call, ok, done

me, friend, other = Player(), Player(), Player()
_, mine = me.rpc("create_profile", p_username="SmokeDel")
_, theirs = friend.rpc("create_profile", p_username="SmokeDelFriend")
_, others = other.rpc("create_profile", p_username="SmokeDelOther")

me.rpc("send_friend_request", p_username="SmokeDelFriend", p_tag=theirs["tag"])
friend.rpc("respond_friend_request", p_requester=me.id, p_accept=True)
other.rpc("send_friend_request", p_username="SmokeDel", p_tag=mine["tag"])
status, room = me.rpc("find_match")   # joins the ranked queue (nobody else there)
ok("setup: friend accepted", any(
    f.get("id") == me.id for f in (friend.rpc("my_friends")[1] or [])),
   friend.rpc("my_friends"))

status, _ = anon_call("POST", "/rest/v1/rpc/delete_my_account", {})
ok("signed-out caller refused", status >= 400, status)

status, body = me.rpc("delete_my_account")
ok("delete 200, returns true", status == 200 and body is True, (status, body))

ok("profile gone (read by the friend)", friend.profile(me.id) is None)
status, friends = friend.rpc("my_friends")
ok("friend's list no longer has them", status == 200 and not any(
    f.get("id") == me.id for f in (friends or [])), friends)
status, found = friend.rpc("find_player", p_username="SmokeDel", p_tag=mine["tag"])
ok("find_player no longer finds them",
   status == 200 and (not found or found.get("id") is None), (status, found))
ok("the friend's own profile stays", friend.profile() is not None)

# The auth user is gone: its (unexpired) JWT no longer resolves to a user.
status, body = me.call("GET", "/auth/v1/user")
ok("auth user gone", status >= 400, (status, body))
status, body = me.rpc("delete_my_account")
ok("repeat call does not delete anything else",
   status >= 400 or body is False, (status, body))

done()
