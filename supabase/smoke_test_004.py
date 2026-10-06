"""Forfeit, rematch, reconnect and cleanup, exercised over HTTP.

Run:  python supabase\smoke_test_004.py

The one test that matters most is "a claim is refused while the opponent is
still alive" — that is what stops a wobble on the claimant's own connection
from silently handing them the match.
"""
import json
import pathlib
import urllib.error
import urllib.request
import uuid

import psycopg2

URL = "https://yjdcsdikcrdupqmaqoqn.supabase.co"
KEY = "sb_publishable_gGylTdpJ4aI3KU6u6UNr9Q_ZaUhHthO"
HEAD = {"apikey": KEY, "Authorization": "Bearer " + KEY,
        "Content-Type": "application/json"}

fails = 0
pg = psycopg2.connect(
    (pathlib.Path(__file__).resolve().parent / ".pgpass.local")
    .read_text(encoding="utf-8").strip(), connect_timeout=15)
pg.autocommit = True


def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(URL + path, data=data, headers=HEAD,
                                 method=method)
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            raw = r.read().decode()
            return r.status, (json.loads(raw) if raw.strip() else None)
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except ValueError:
            return e.code, raw


def rpc(fn, **p):
    return call("POST", "/rest/v1/rpc/" + fn, p)


def ok(label, cond, detail=""):
    global fails
    if not cond:
        fails += 1
    print(("  PASS  " if cond else "  FAIL  ") + label
          + ("  " + str(detail) if detail else ""))


def age_heartbeat(code, seat, seconds):
    """Push one player's last-seen back in time, to simulate them going away."""
    with pg.cursor() as cur:
        cur.execute(
            "update public.rooms set %s_seen_at = now() - make_interval(secs => %%s) "
            "where code = %%s" % seat, (seconds, code))


def fresh_room(host_name="A", guest_name="B"):
    host, guest = str(uuid.uuid4()), str(uuid.uuid4())
    _, room = rpc("create_room", p_host_id=host, p_host_name=host_name)
    rpc("join_room", p_code=room["code"], p_guest_id=guest,
        p_guest_name=guest_name)
    rpc("start_match", p_code=room["code"])
    return room["code"], host, guest


print("== a claim is REFUSED while the opponent is alive ==")
code, host, guest = fresh_room()
rpc("touch_seen", p_code=code, p_seat="guest")     # guest just checked in
status, room = rpc("claim_forfeit", p_code=code, p_claimant="host")
ok("still playing, no forfeit", room["phase"] != "match_over", room["phase"])
ok("no winner recorded", room["winner"] is None, room["winner"])

print()
print("== a claim is GRANTED once the opponent has gone quiet ==")
age_heartbeat(code, "guest", 60)
status, room = rpc("claim_forfeit", p_code=code, p_claimant="host")
ok("match over", room["phase"] == "match_over", room["phase"])
ok("host wins", room["winner"] == "host", room["winner"])
ok("reason names who left", room["ended_reason"] == "forfeit_guest",
   room["ended_reason"])

print()
print("== the guest can claim too, not just the host ==")
code2, _, _ = fresh_room()
age_heartbeat(code2, "host", 60)
status, room = rpc("claim_forfeit", p_code=code2, p_claimant="guest")
ok("guest wins a host walkout", room["winner"] == "guest"
   and room["ended_reason"] == "forfeit_host", room["ended_reason"])

print()
print("== leave_match forfeits immediately, no silence needed ==")
code3, _, _ = fresh_room()
status, room = rpc("leave_match", p_code=code3, p_seat="host")
ok("opponent takes it at once", room["phase"] == "match_over"
   and room["winner"] == "guest", room["ended_reason"])

print()
print("== rematch ==")
code4, host4, guest4 = fresh_room()
with pg.cursor() as cur:
    cur.execute("update public.rooms set host_score = 3, phase = 'match_over',"
                " winner = 'host', ended_reason = 'goals', round = 5,"
                " host_club_id = 772 where code = %s", (code4,))
status, room = rpc("rematch", p_code=code4)
ok("back to lobby", room["phase"] == "lobby", room["phase"])
ok("scores cleared", room["host_score"] == 0 and room["guest_score"] == 0)
ok("round cleared", room["round"] == 0, room["round"])
ok("winner cleared", room["winner"] is None and room["ended_reason"] is None)
ok("clubs cleared", room["host_club_id"] is None)
ok("both players still seated", room["guest_id"] == guest4)
status, room = rpc("start_match", p_code=code4)
ok("start_match works again after a rematch", room["phase"] == "picking",
   room["phase"])

print()
print("== active_room_for (reconnect) ==")
status, found = rpc("active_room_for", p_player_id=guest4)
ok("finds the match this player is in",
   isinstance(found, dict) and found.get("code") == code4, found)
rpc("leave_match", p_code=code4, p_seat="host")
status, gone = rpc("active_room_for", p_player_id=guest4)
ok("finished matches are not offered as resumable",
   gone is None or gone.get("code") is None, gone)

print()
print("== abandon_stale_matches ==")
code5, _, _ = fresh_room()
age_heartbeat(code5, "host", 3600)
age_heartbeat(code5, "guest", 3600)
status, n = rpc("abandon_stale_matches", p_silence=600)
status, rows = call("GET", "/rest/v1/rooms?code=eq." + code5
                    + "&select=phase,ended_reason")
ok("silent match closed", rows[0]["phase"] == "match_over"
   and rows[0]["ended_reason"] == "abandoned", rows[0])
ok("sweep reported at least one", isinstance(n, int) and n >= 1, n)

print()
print("== the scheduled jobs exist and are active ==")
with pg.cursor() as cur:
    cur.execute("select jobname, schedule, active from cron.job order by jobname")
    jobs = cur.fetchall()
ok("two cron jobs, both active", len(jobs) == 2 and all(j[2] for j in jobs), jobs)

pg.close()
print()
print("FAILURES:", fails)
