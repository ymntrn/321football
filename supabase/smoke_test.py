"""End-to-end smoke test for the Friend Match schema.

Run:  python supabase\smoke_test.py

Checks the things that are easy to get wrong and silent when they are:
clock offset, room creation, the atomic guest seat, the three join failure
modes, an ordinary row update, and that deletes really are refused.
"""
import json
import time
import urllib.request
import urllib.error
import uuid

URL = "https://yjdcsdikcrdupqmaqoqn.supabase.co"
KEY = ("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
       "eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlqZGNzZGlrY3JkdXBxbWFxb3FuIiwicm9sZSI6"
       "ImFub24iLCJpYXQiOjE3ODkzMTkzMTYsImV4cCI6MjEwNDg5NTMxNn0."
       "DyBo1RM0YBmX-Any8j2e-czGZ5oTwLBEiSrAoSRIvHM")

HEAD = {
    "apikey": KEY,
    "Authorization": "Bearer " + KEY,
    "Content-Type": "application/json",
}


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


def ok(label, cond, detail=""):
    print(("  PASS  " if cond else "  FAIL  ") + label + ("  " + str(detail) if detail else ""))
    return cond


fails = 0

print("== clock offset (5 samples, lowest round trip wins) ==")
best = None
for _ in range(5):
    t0 = time.time() * 1000
    status, server_ms = call("POST", "/rest/v1/rpc/server_now", {})
    t1 = time.time() * 1000
    if status != 200:
        print("   server_now failed:", status, server_ms)
        break
    rtt = t1 - t0
    offset = server_ms - (t0 + t1) / 2
    print("   rtt %7.1f ms   offset %9.1f ms" % (rtt, offset))
    if best is None or rtt < best[0]:
        best = (rtt, offset)
if best:
    fails += not ok("server_now reachable, offset measured",
                    True, "best rtt %.0f ms, offset %.0f ms" % best)
else:
    fails += 1

print()
print("== create_room ==")
host = str(uuid.uuid4())
status, room = call("POST", "/rest/v1/rpc/create_room",
                    {"p_host_id": host, "p_host_name": "Yaman"})
fails += not ok("create_room returns 200", status == 200, status)
code = room.get("code") if isinstance(room, dict) else None
fails += not ok("six digit code", bool(code) and len(code) == 6 and code.isdigit(), code)
fails += not ok("starts in lobby", isinstance(room, dict) and room.get("phase") == "lobby")
fails += not ok("defaults: first to 3, 15s pick, 10s answer",
                isinstance(room, dict) and room.get("target_goals") == 3
                and room.get("pick_seconds") == 15 and room.get("answer_seconds") == 10)

print()
print("== join_room ==")
guest = str(uuid.uuid4())
status, joined = call("POST", "/rest/v1/rpc/join_room",
                      {"p_code": code, "p_guest_id": guest,
                       "p_guest_name": "Arkadas"})
fails += not ok("guest joins", status == 200 and isinstance(joined, dict)
                and joined.get("guest_id") == guest, status)

status, again = call("POST", "/rest/v1/rpc/join_room",
                     {"p_code": code, "p_guest_id": guest,
                      "p_guest_name": "Arkadas"})
fails += not ok("same guest rejoining is allowed (reconnect)", status == 200, status)

status, third = call("POST", "/rest/v1/rpc/join_room",
                     {"p_code": code, "p_guest_id": str(uuid.uuid4()),
                      "p_guest_name": "Ucuncu"})
msg = third.get("message", "") if isinstance(third, dict) else str(third)
fails += not ok("third player refused with room_full", "room_full" in msg, msg)

status, missing = call("POST", "/rest/v1/rpc/join_room",
                       {"p_code": "000001", "p_guest_id": str(uuid.uuid4()),
                        "p_guest_name": "Yok"})
msg = missing.get("message", "") if isinstance(missing, dict) else str(missing)
fails += not ok("unknown code refused with room_not_found",
                "room_not_found" in msg, msg)

print()
print("== plain row update ==")
status, updated = call("PATCH", "/rest/v1/rooms?code=eq." + code,
                       {"phase": "picking", "round": 1},
                       {"Prefer": "return=representation"})
row = updated[0] if isinstance(updated, list) and updated else {}
fails += not ok("phase updated", status in (200, 204) and row.get("phase") == "picking", status)
fails += not ok("updated_at trigger fired",
                row.get("updated_at") != row.get("created_at"))

status, bad = call("PATCH", "/rest/v1/rooms?code=eq." + code, {"phase": "nonsense"})
# Assert the SPECIFIC error. An earlier version accepted any 4xx and therefore
# passed on a 401 permission failure, reporting a constraint that was never
# reached. 23514 is check_violation.
bad_code = bad.get("code") if isinstance(bad, dict) else None
fails += not ok("invalid phase rejected by the check constraint (23514)",
                bad_code == "23514", "%s %s" % (status, bad_code))

print()
print("== join refused once the match is under way ==")
status, late = call("POST", "/rest/v1/rpc/join_room",
                    {"p_code": code, "p_guest_id": str(uuid.uuid4()),
                     "p_guest_name": "Gec"})
msg = late.get("message", "") if isinstance(late, dict) else str(late)
fails += not ok("room_in_progress", "room_in_progress" in msg, msg)

print()
print("== delete must be refused (no delete policy) ==")
status, _ = call("DELETE", "/rest/v1/rooms?code=eq." + code)
status2, still = call("GET", "/rest/v1/rooms?code=eq." + code + "&select=code")
fails += not ok("row survives the delete attempt",
                isinstance(still, list) and len(still) == 1, still)

print()
print("== cleanup ==")
status, n = call("POST", "/rest/v1/rpc/purge_stale_rooms", {})
print("   purge_stale_rooms ->", status, n, "(only removes rooms older than a day)")

print()
print("FAILURES:", fails)
