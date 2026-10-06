"""Checks 007_results.sql against the real project: a whole match over HTTP,
then record_match_result twice, for a Friend Match and a ranked room.

Run:  python supabase\\smoke_test_007.py      (makes two anonymous users)
"""
from sbclient import Player, ok, done

host, guest = Player(), Player()
host.rpc("create_profile", p_username="SmokeHost")
guest.rpc("create_profile", p_username="SmokeGuest")


def play_to_three(code):
    """Host wins three rounds: answers 2100, 1500, 1800 ms; guest 2500 once."""
    host.rpc("start_match", p_code=code)
    for i, ms in enumerate([2100, 1500, 1800]):
        host.patch_room(code, {"host_club_id": 418, "host_club_name": "A"})
        guest.patch_room(code, {"guest_club_id": 131, "guest_club_name": "B"})
        host.rpc("begin_countdown", p_code=code)
        host.rpc("open_answers", p_code=code)
        host.patch_room(code, {"host_answer": "x", "host_elapsed_ms": ms})
        if i == 0:
            guest.patch_room(code, {"guest_answer": "y", "guest_elapsed_ms": 2500})
        host.rpc("finish_round", p_code=code, p_winner="host", p_reason="correct")
        if i < 2:
            host.rpc("next_round", p_code=code)


def new_room():
    _, room = host.rpc("create_room", p_host_id=host.id, p_host_name="SmokeHost")
    guest.rpc("join_room", p_code=room["code"], p_guest_id=guest.id,
              p_guest_name="SmokeGuest")
    return room["code"]


print("== Friend Match: stats only ==")
before_h, before_g = host.profile(), guest.profile()
code = new_room()
play_to_three(code)
room = host.get_room(code)
ok("match over, host won", room["phase"] == "match_over" and room["winner"] == "host")
ok("host_best_ms tracked over rounds", room["host_best_ms"] == 1500, room["host_best_ms"])
status, room = host.rpc("record_match_result", p_code=code)
ok("record 200", status == 200, status)
ok("no economy on a friend match",
   room["host_trophy_delta"] == 0 and room["host_coin_delta"] == 0, room)
h, g = host.profile(), guest.profile()
ok("host +1 match +1 win", h["matches_played"] == before_h["matches_played"] + 1
   and h["wins"] == before_h["wins"] + 1)
ok("guest +1 match", g["matches_played"] == before_g["matches_played"] + 1)
ok("fastest answers", h["fastest_answer_ms"] == 1500 and g["fastest_answer_ms"] == 2500,
   (h["fastest_answer_ms"], g["fastest_answer_ms"]))
ok("trophies/coins unchanged", h["trophies"] == before_h["trophies"]
   and h["coins"] == before_h["coins"])
guest.rpc("record_match_result", p_code=code)
ok("second call changes nothing", host.profile()["matches_played"] == h["matches_played"])

print()
print("== ranked: +30/+10 and -20 (floored)/+2 ==")
code = new_room()
# Only 009's find_match sets `ranked`; for this test the row is patched,
# which the two players' RLS allows (no anti-cheat, by decision).
host.patch_room(code, {"ranked": True})
play_to_three(code)
_, room = guest.rpc("record_match_result", p_code=code)
ok("deltas", (room["host_trophy_delta"], room["guest_trophy_delta"],
              room["host_coin_delta"], room["guest_coin_delta"]) == (30, 0, 10, 2), room)
h2, g2 = host.profile(), guest.profile()
ok("host +30 trophies +10 coins", h2["trophies"] == h["trophies"] + 30
   and h2["coins"] == h["coins"] + 10)
ok("guest at 0 stays 0, +2 coins", g2["trophies"] == 0 and g2["coins"] == g["coins"] + 2)
host.rpc("record_match_result", p_code=code)
ok("idempotent", host.profile()["trophies"] == h2["trophies"])

print()
print("== spend_coins ==")
status, bal = host.rpc("spend_coins", p_amount=3)
ok("spend 3", status == 200 and bal == h2["coins"] - 3, (status, bal))
status, _ = host.rpc("spend_coins", p_amount=100000)
ok("overspend refused", status >= 400, status)
done()
