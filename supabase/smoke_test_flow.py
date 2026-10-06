"""Drives a whole match through the 003 state-transition functions.

No app, no emulator — just the two players' HTTP calls, in order. If this
passes, the server half of the match loop is correct and anything that then
goes wrong on a phone is a client bug.

Run:  python supabase\smoke_test_flow.py
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


host, guest = str(uuid.uuid4()), str(uuid.uuid4())

print("== set up a room with two players ==")
_, room = rpc("create_room", p_host_id=host, p_host_name="Yaman")
code = room["code"]
rpc("join_room", p_code=code, p_guest_id=guest, p_guest_name="Arkadas")
print("   room", code)

print()
print("== start_match ==")
status, room = rpc("start_match", p_code=code)
ok("phase is picking", room["phase"] == "picking", room["phase"])
ok("round 1", room["round"] == 1)
ok("pick_deadline set", room["pick_deadline"] is not None)
prev_deadline = room["pick_deadline"]

status, again = rpc("start_match", p_code=code)
ok("start_match is idempotent (deadline not restarted)",
   again["pick_deadline"] == prev_deadline)

print()
print("== both players pick ==")
status, _ = patch(code, {"host_club_id": 772, "host_club_name": "FC Barcelona"})
status, room = rpc("begin_countdown", p_code=code)
ok("countdown refused with only one club in", room["phase"] == "picking",
   room["phase"])

patch(code, {"guest_club_id": 2, "guest_club_name": "Inter Milan"})
status, room = rpc("begin_countdown", p_code=code)
ok("countdown starts once both are in", room["phase"] == "countdown")
ok("unlock_at set", room["unlock_at"] is not None)
ok("answer_deadline after unlock_at",
   room["answer_deadline"] > room["unlock_at"])
unlock = room["unlock_at"]

status, room = rpc("begin_countdown", p_code=code)
ok("begin_countdown is idempotent", room["unlock_at"] == unlock)

print()
print("== answers ==")
status, room = rpc("open_answers", p_code=code)
ok("phase is answering", room["phase"] == "answering")

# Guest is faster.
patch(code, {"guest_answer": "sneijder", "guest_elapsed_ms": 2100})
patch(code, {"host_answer": "sneijder", "host_elapsed_ms": 3400})

status, rows = call("GET", "/rest/v1/rooms?code=eq." + code
                    + "&select=host_elapsed_ms,guest_elapsed_ms")
r = rows[0]
winner = "host" if r["host_elapsed_ms"] <= r["guest_elapsed_ms"] else "guest"
ok("client-side verdict picks the faster player", winner == "guest", winner)

# A second submission must not overwrite a faster first one.
call("PATCH", "/rest/v1/rooms?code=eq." + code
     + "&guest_elapsed_ms=is.null", {"guest_elapsed_ms": 50})
status, rows = call("GET", "/rest/v1/rooms?code=eq." + code
                    + "&select=guest_elapsed_ms")
ok("a resubmission cannot overwrite the first time",
   rows[0]["guest_elapsed_ms"] == 2100, rows[0]["guest_elapsed_ms"])

print()
print("== finish_round ==")
status, room = rpc("finish_round", p_code=code, p_winner="guest",
                   p_reason="correct")
ok("phase is round_over", room["phase"] == "round_over")
ok("guest scored", room["guest_score"] == 1 and room["host_score"] == 0,
   "%s-%s" % (room["host_score"], room["guest_score"]))

status, room = rpc("finish_round", p_code=code, p_winner="guest",
                   p_reason="correct")
ok("finish_round is idempotent (no double goal)", room["guest_score"] == 1,
   room["guest_score"])

print()
print("== next_round ==")
status, room = rpc("next_round", p_code=code)
ok("round 2", room["round"] == 2, room["round"])
ok("clubs cleared", room["host_club_id"] is None
   and room["guest_club_id"] is None)
ok("answers cleared", room["host_elapsed_ms"] is None
   and room["guest_elapsed_ms"] is None)
ok("back to picking with a fresh deadline",
   room["phase"] == "picking" and room["pick_deadline"] != prev_deadline)

print()
print("== a voided round is replayed, not counted ==")
patch(code, {"host_club_id": 1, "guest_club_id": 2})
rpc("begin_countdown", p_code=code)
status, room = rpc("finish_round", p_code=code, p_winner=None,
                   p_reason="unplayable")
ok("nobody scored", room["host_score"] == 0 and room["guest_score"] == 1)
status, room = rpc("next_round", p_code=code)
ok("round number did NOT advance", room["round"] == 2, room["round"])

print()
print("== match ends at the target ==")
for _ in range(2):
    patch(code, {"host_club_id": 1, "guest_club_id": 2})
    rpc("begin_countdown", p_code=code)
    status, room = rpc("finish_round", p_code=code, p_winner="guest",
                       p_reason="correct")
    if room["phase"] != "match_over":
        rpc("next_round", p_code=code)
ok("match_over at 3 goals", room["phase"] == "match_over", room["phase"])
ok("guest is the winner", room["winner"] == "guest", room["winner"])
ok("ended_reason is goals", room["ended_reason"] == "goals",
   room["ended_reason"])

print()
print("== forfeit ==")
_, room2 = rpc("create_room", p_host_id=str(uuid.uuid4()), p_host_name="A")
rpc("join_room", p_code=room2["code"], p_guest_id=str(uuid.uuid4()),
    p_guest_name="B")
rpc("start_match", p_code=room2["code"])
status, room2 = rpc("forfeit", p_code=room2["code"], p_loser="guest")
ok("host wins a guest forfeit", room2["winner"] == "host"
   and room2["ended_reason"] == "forfeit_guest", room2["ended_reason"])

print()
print("FAILURES:", fails)
