"""Checks 010_double_reward.sql against the real project: a ranked match over
HTTP, record_match_result, then double_match_coins by the winner (twice),
the loser, an outsider, and on a Friend Match.

Run:  python supabase\\smoke_test_010.py      (makes three anonymous users)
Then: python supabase\\purge_test_accounts.py  (lists the Smoke* leftovers)
"""
from sbclient import Player, anon_call, ok, done

host, guest, outsider = Player(), Player(), Player()
host.rpc("create_profile", p_username="SmokeDblHost")
guest.rpc("create_profile", p_username="SmokeDblGuest")
outsider.rpc("create_profile", p_username="SmokeDblOut")


def new_room(ranked):
    _, room = host.rpc("create_room", p_host_id=host.id, p_host_name="SmokeDblHost")
    code = room["code"]
    guest.rpc("join_room", p_code=code, p_guest_id=guest.id,
              p_guest_name="SmokeDblGuest")
    if ranked:
        # Only 009's find_match sets `ranked`; the players' RLS lets the test
        # patch it (no anti-cheat, by decision).
        host.patch_room(code, {"ranked": True})
    return code


def host_wins(code):
    host.rpc("start_match", p_code=code)
    for i in range(3):
        host.patch_room(code, {"host_club_id": 418, "host_club_name": "A"})
        guest.patch_room(code, {"guest_club_id": 131, "guest_club_name": "B"})
        host.rpc("begin_countdown", p_code=code)
        host.rpc("open_answers", p_code=code)
        host.patch_room(code, {"host_answer": "x", "host_elapsed_ms": 1500})
        host.rpc("finish_round", p_code=code, p_winner="host", p_reason="correct")
        if i < 2:
            host.rpc("next_round", p_code=code)


print("== ranked win: doubled once ==")
code = new_room(ranked=True)
host_wins(code)
status, _ = host.rpc("double_match_coins", p_code=code)
ok("refused before the result is recorded", status >= 400, status)

host.rpc("record_match_result", p_code=code)
c0 = host.profile()["coins"]
status, room = host.rpc("double_match_coins", p_code=code)
ok("double 200", status == 200, (status, room))
ok("room shows +20 for the winner", isinstance(room, dict)
   and room.get("host_coin_delta") == 20, room)
ok("winner +10 more coins", host.profile()["coins"] == c0 + 10,
   (c0, host.profile()["coins"]))

status, room = host.rpc("double_match_coins", p_code=code)
ok("second call 200 (idempotent)", status == 200, status)
ok("second call: no more coins", host.profile()["coins"] == c0 + 10)

host.patch_room(code, {"host_coin_delta": 10})
host.rpc("double_match_coins", p_code=code)
ok("once holds after the room row is edited", host.profile()["coins"] == c0 + 10)

g0 = guest.profile()["coins"]
status, body = guest.rpc("double_match_coins", p_code=code)
ok("loser refused", status >= 400 and "not_a_win" in str(body), (status, body))
ok("loser's coins unchanged", guest.profile()["coins"] == g0)

status, body = outsider.rpc("double_match_coins", p_code=code)
ok("outsider refused", status >= 400 and "room_not_found" in str(body), (status, body))

status, _ = anon_call("POST", "/rest/v1/rpc/double_match_coins", {"p_code": code})
ok("signed-out caller refused", status >= 400, status)

status, _ = host.call("GET", "/rest/v1/coin_doubles?select=*")
ok("coin_doubles not readable", status >= 400 or _ == [], (status, _))

print()
print("== Friend Match: refused ==")
code = new_room(ranked=False)
host_wins(code)
host.rpc("record_match_result", p_code=code)
status, body = host.rpc("double_match_coins", p_code=code)
ok("not_ranked", status >= 400 and "not_ranked" in str(body), (status, body))

done()
