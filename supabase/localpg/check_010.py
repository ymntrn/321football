# double_match_coins: the caller's own ranked win, once.
w, l, x = User(conn), User(conn), User(conn)
w.one("select * from create_profile('Dbl')")
l.one("select * from create_profile('DblLoser')")
x.one("select * from create_profile('Outsider')")


def play(ranked, record=True):
    r = w.one("select * from create_room(null, 'Dbl')")
    code = r["code"]
    l.one("select * from join_room(%s, null, 'DblLoser')", (code,))
    with conn.cursor() as cur:
        cur.execute("update rooms set ranked=%s where code=%s", (ranked, code))
    w.one("select * from start_match(%s)", (code,))
    for i in range(3):
        w.q("update rooms set host_club_id=1, guest_club_id=2 where code=%s", (code,))
        w.one("select * from begin_countdown(%s)", (code,))
        w.one("select * from open_answers(%s)", (code,))
        w.q("update rooms set host_answer='x', host_elapsed_ms=1500 where code=%s", (code,))
        w.one("select * from finish_round(%s, 'host', 'correct')", (code,))
        if i < 2:
            w.one("select * from next_round(%s)", (code,))
    if record:
        w.one("select * from record_match_result(%s)", (code,))
    return code


def coins(u):
    return u.one("select coins from profiles where id=auth.uid()")["coins"]


code = play(ranked=True, record=False)
ok("refused before the result is recorded",
   "result_not_recorded" in (w.fails("select * from double_match_coins(%s)", (code,)) or ""))
w.one("select * from record_match_result(%s)", (code,))

c0 = coins(w)
r = w.one("select * from double_match_coins(%s)", (code,))
ok("winner +10 coins", coins(w) == c0 + 10, (c0, coins(w)))
ok("room shows +20 for the winner", r["host_coin_delta"] == 20, r["host_coin_delta"])
ok("loser's delta untouched", r["guest_coin_delta"] == 2, r["guest_coin_delta"])

r2 = w.one("select * from double_match_coins(%s)", (code,))
ok("second call: no more coins", coins(w) == c0 + 10, coins(w))
ok("second call: returns the row unchanged", r2["host_coin_delta"] == 20)

# Clearing the room's columns (players may write their room) does not reopen it.
w.q("update rooms set host_coin_delta=10 where code=%s", (code,))
w.one("select * from double_match_coins(%s)", (code,))
ok("once holds even after the room row is edited", coins(w) == c0 + 10, coins(w))

lc = coins(l)
ok("loser refused", "not_a_win" in (l.fails("select * from double_match_coins(%s)", (code,)) or ""))
ok("loser's coins unchanged", coins(l) == lc)
ok("outsider refused", "room_not_found" in (x.fails("select * from double_match_coins(%s)", (code,)) or ""))
ok("unknown room refused", "room_not_found" in (w.fails("select * from double_match_coins('000000')") or ""))

code = play(ranked=False)
ok("friend match refused", "not_ranked" in (w.fails("select * from double_match_coins(%s)", (code,)) or ""))

# a new match in the same room (rematch) may be doubled again
code = play(ranked=True)
w.one("select * from double_match_coins(%s)", (code,))
c1 = coins(w)
w.one("select * from rematch(%s)", (code,))
w.one("select * from start_match(%s)", (code,))
for i in range(3):
    w.q("update rooms set host_club_id=1, guest_club_id=2 where code=%s", (code,))
    w.one("select * from begin_countdown(%s)", (code,))
    w.one("select * from open_answers(%s)", (code,))
    w.q("update rooms set host_answer='x', host_elapsed_ms=1500 where code=%s", (code,))
    w.one("select * from finish_round(%s, 'host', 'correct')", (code,))
    if i < 2:
        w.one("select * from next_round(%s)", (code,))
w.one("select * from record_match_result(%s)", (code,))
c2 = coins(w)
w.one("select * from double_match_coins(%s)", (code,))
ok("the next match in the room doubles once more", coins(w) == c2 + 10, (c1, c2, coins(w)))

ok("coin_doubles not readable directly", w.fails("select * from coin_doubles"))
ok("coin_doubles not writable directly",
   w.fails("insert into coin_doubles values ('1', auth.uid(), now(), 10)"))
with conn.cursor() as cur:
    cur.execute("set role anon")
    try:
        cur.execute("select double_match_coins('000000')")
        anon_ok = False
    except Exception:
        anon_ok = True
    conn.rollback() if not conn.autocommit else None
    cur.execute("reset role")
ok("anon cannot call it", anon_ok)
