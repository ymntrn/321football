# delete_my_account: the caller's profile, friendships, queue entry,
# 2X records and auth user — nobody else's.
me, friend, other = User(conn), User(conn), User(conn)
me.one("select * from create_profile('Silinecek')")
friend.one("select * from create_profile('Kalan')")
other.one("select * from create_profile('Baska')")

tag = lambda u: u.one("select tag from profiles where id=auth.uid()")["tag"]
me.one("select * from send_friend_request('Kalan', %s)", (tag(friend),))
other.one("select * from send_friend_request('Silinecek', %s)", (tag(me),))
fr = friend.one("select requester from friendships where addressee=auth.uid()")
friend.one("select * from respond_friend_request(%s, true)", (fr["requester"],))

with conn.cursor() as cur:
    cur.execute("insert into match_queue (player_id, trophies, username) values (%s, 0, 'Silinecek')", (me.id,))
    cur.execute("insert into coin_doubles (room_code, player_id, match_recorded_at, coins) "
                "values ('111111', %s, now(), 10)", (me.id,))


def count(sql, *params):
    with conn.cursor() as cur:
        cur.execute(sql, params)
        return cur.fetchone()[0]


ok("setup: two friendships", count(
    "select count(*) from friendships where requester=%s or addressee=%s", me.id, me.id) == 2)

r = me.one("select delete_my_account() as d")
ok("returns true", r["d"] is True, r)
ok("profile gone", count("select count(*) from profiles where id=%s", me.id) == 0)
ok("friendships gone (both directions)", count(
    "select count(*) from friendships where requester=%s or addressee=%s", me.id, me.id) == 0)
ok("queue entry gone", count("select count(*) from match_queue where player_id=%s", me.id) == 0)
ok("2X records gone", count("select count(*) from coin_doubles where player_id=%s", me.id) == 0)
ok("auth user gone", count("select count(*) from auth.users where id=%s", me.id) == 0)

ok("the friend's profile stays", count("select count(*) from profiles where id=%s", friend.id) == 1)
ok("others' auth users stay", count(
    "select count(*) from auth.users where id in (%s, %s)", friend.id, other.id) == 2)

r = me.one("select delete_my_account() as d")
ok("repeat call returns false", r["d"] is False, r)

with conn.cursor() as cur:
    cur.execute("set role anon")
    try:
        cur.execute("select delete_my_account()")
        refused = False
    except Exception:
        refused = True
    cur.execute("reset role")
ok("anon cannot call it", refused)
