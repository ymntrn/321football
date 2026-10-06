"""Checks 005_void_from_picking.sql: an unplayable pair is voided from picking.

Run:  python supabase\\smoke_test_005.py
"""
import json
import urllib.request
import urllib.error
import uuid

URL = "https://yjdcsdikcrdupqmaqoqn.supabase.co"
KEY = "sb_publishable_gGylTdpJ4aI3KU6u6UNr9Q_ZaUhHthO"
HEAD = {"apikey": KEY, "Authorization": "Bearer " + KEY,
        "Content-Type": "application/json"}

fails = 0


def call(method, path, body=None, extra=None):
    headers = dict(HEAD)
    if extra:
        headers.update(extra)
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(URL + path, data=data, headers=headers,
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


def rpc(fn, **params):
    return call("POST", "/rest/v1/rpc/" + fn, params)


def patch(code, body):
    return call("PATCH", "/rest/v1/rooms?code=eq." + code, body,
                {"Prefer": "return=representation"})


def ok(label, cond, detail=""):
    global fails
    if not cond:
        fails += 1
    print(("  PASS  " if cond else "  FAIL  ") + label
          + ("  " + str(detail) if detail else ""))


def new_room():
    host, guest = str(uuid.uuid4()), str(uuid.uuid4())
    _, room = rpc("create_room", p_host_id=host, p_host_name="Test")
    code = room["code"]
    rpc("join_room", p_code=code, p_guest_id=guest, p_guest_name="Test2")
    rpc("start_match", p_code=code)
    return code


print("== only one club in: picking cannot be voided yet ==")
code = new_room()
patch(code, {"host_club_id": 196, "host_club_name": "Real Zaragoza"})
_, room = rpc("finish_round", p_code=code, p_winner=None, p_reason="unplayable")
ok("still picking", room["phase"] == "picking", room["phase"])

print()
print("== a goal cannot be scored from picking ==")
patch(code, {"guest_club_id": 316, "guest_club_name": "Nottingham Forest F.C."})
_, room = rpc("finish_round", p_code=code, p_winner="host", p_reason="correct")
ok("still picking", room["phase"] == "picking", room["phase"])
ok("no score", room["host_score"] == 0 and room["guest_score"] == 0)

print()
print("== both clubs in, dead pair: voided straight from picking ==")
_, room = rpc("finish_round", p_code=code, p_winner=None, p_reason="unplayable")
ok("phase is round_over", room["phase"] == "round_over", room["phase"])
ok("reason unplayable", room["round_reason"] == "unplayable")
ok("nobody scored", room["host_score"] == 0 and room["guest_score"] == 0)

print()
print("== next_round replays the same round number ==")
_, room = rpc("next_round", p_code=code)
ok("back to picking", room["phase"] == "picking", room["phase"])
ok("round still 1", room["round"] == 1, room["round"])
ok("clubs cleared", room["host_club_id"] is None and room["guest_club_id"] is None)

call("DELETE", "/rest/v1/rooms?code=eq." + code)
print()
print("FAILURES:", fails)
