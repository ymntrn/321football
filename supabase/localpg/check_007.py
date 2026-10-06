# Results: idempotent, stats for all, economy for ranked only.
w, l = User(conn), User(conn)
w.one("select * from create_profile('Winner')")
l.one("select * from create_profile('Loser')")

def play(ranked, winner_seat="host", forfeit=False):
    r = w.one("select * from create_room(null, 'Winner')")
    code = r["code"]
    l.one("select * from join_room(%s, null, 'Loser')", (code,))
    with conn.cursor() as cur:
        cur.execute("update rooms set ranked=%s where code=%s", (ranked, code))
    w.one("select * from start_match(%s)", (code,))
    # three rounds: host answers 2100, 1500, 1800; guest 2500 in round 1
    for i, ms in enumerate([2100, 1500, 1800]):
        w.q("update rooms set host_club_id=1, guest_club_id=2 where code=%s", (code,))
        w.one("select * from begin_countdown(%s)", (code,))
        w.one("select * from open_answers(%s)", (code,))
        w.q("update rooms set host_answer='x', host_elapsed_ms=%s where code=%s", (ms, code))
        if i == 0:
            l.q("update rooms set guest_answer='y', guest_elapsed_ms=2500 where code=%s", (code,))
        w.one("select * from finish_round(%s, 'host', 'correct')", (code,))
        if i < 2:
            w.one("select * from next_round(%s)", (code,))
    return code

code = play(ranked=False)
r = w.one("select * from rooms where code=%s", (code,))
ok("friend match finished", r["phase"] == "match_over" and r["winner"] == "host")
ok("host best tracked across rounds", r["host_best_ms"] == 1500, r["host_best_ms"])
ok("guest best tracked", r["guest_best_ms"] == 2500, r["guest_best_ms"])
r = w.one("select * from record_match_result(%s)", (code,))
ok("recorded", r["result_recorded_at"] is not None)
ok("friend match: no trophy/coin delta", r["host_trophy_delta"] == 0 and r["host_coin_delta"] == 0)
pw = w.one("select * from profiles where id=auth.uid()")
pl = l.one("select * from profiles where id=auth.uid()")
ok("winner stats", (pw["matches_played"], pw["wins"], pw["current_streak"], pw["best_streak"], pw["fastest_answer_ms"]) == (1, 1, 1, 1, 1500), pw)
ok("winner economy untouched", pw["trophies"] == 0 and pw["coins"] == 30)
ok("loser stats", (pl["matches_played"], pl["wins"], pl["current_streak"], pl["fastest_answer_ms"]) == (1, 0, 0, 2500), pl)
l.one("select * from record_match_result(%s)", (code,))
pw2 = w.one("select * from profiles where id=auth.uid()")
ok("second call (by guest) changes nothing", pw2 == pw)

code = play(ranked=True)
r = l.one("select * from record_match_result(%s)", (code,))
ok("ranked deltas", (r["host_trophy_delta"], r["guest_trophy_delta"], r["host_coin_delta"], r["guest_coin_delta"]) == (30, 0, 10, 2), r)
pw = w.one("select * from profiles where id=auth.uid()")
pl = l.one("select * from profiles where id=auth.uid()")
ok("winner +30 trophies +10 coins", pw["trophies"] == 30 and pw["coins"] == 40, pw)
ok("loser floored at 0, +2 coins", pl["trophies"] == 0 and pl["coins"] == 32, pl)
ok("streaks", pw["current_streak"] == 2 and pw["best_streak"] == 2)
w.one("select * from record_match_result(%s)", (code,))
ok("idempotent on ranked", w.one("select trophies from profiles where id=auth.uid()")["trophies"] == 30)
# loser with trophies loses 20
with conn.cursor() as cur:
    cur.execute("update profiles set trophies=55 where id=%s", (l.id,))
code = play(ranked=True)
w.one("select * from record_match_result(%s)", (code,))
ok("loser -20", l.one("select trophies from profiles where id=auth.uid()")["trophies"] == 35)
# rematch clears and re-records
w.one("select * from rematch(%s)", (code,))
r = w.one("select * from rooms where code=%s", (code,))
ok("rematch clears result", r["result_recorded_at"] is None and r["host_best_ms"] is None)
# record on unfinished room is a no-op
ok("unfinished is no-op", w.one("select * from record_match_result(%s)", (code,))["result_recorded_at"] is None)
# spend_coins
bal = w.one("select spend_coins(3) as b")["b"]
ok("spend 3", bal == pw["coins"] + 10 - 3 if False else bal == 50 - 3, bal)
ok("overspend refused", w.fails("select spend_coins(1000)"))
ok("zero refused", w.fails("select spend_coins(0)"))
ok("coins still direct-unwritable", w.fails("update profiles set coins=1 where id=auth.uid()"))
