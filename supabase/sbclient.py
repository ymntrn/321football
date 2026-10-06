"""A signed-in Supabase HTTP client for the smoke tests and the bot.

Since 006_accounts.sql every room is readable only by its two players
(`auth.uid() in (host_id, guest_id)`), so a script must sign in the way the
app does: an ANONYMOUS sign-in, which gives it a real auth user and a JWT.
Each Player() is a separate auth user — two of them are two players.

Anonymous sign-ins must be enabled in the dashboard
(Authentication -> Sign In / Providers -> Allow anonymous sign-ins), and the
project rate-limits them per IP (30 an hour by default), so a test run makes
only as many players as it needs.
"""
import json
import urllib.error
import urllib.request

URL = "https://yjdcsdikcrdupqmaqoqn.supabase.co"
KEY = "sb_publishable_gGylTdpJ4aI3KU6u6UNr9Q_ZaUhHthO"


def _send(method, path, body=None, headers=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(URL + path, data=data, headers=headers or {},
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


def anon_call(method, path, body=None, extra=None):
    """A request with only the publishable key — what a signed-OUT client is."""
    headers = {"apikey": KEY, "Authorization": "Bearer " + KEY,
               "Content-Type": "application/json"}
    if extra:
        headers.update(extra)
    return _send(method, path, body, headers)


class Player:
    """One anonymous auth user."""

    def __init__(self):
        status, body = _send("POST", "/auth/v1/signup", {},
                             {"apikey": KEY, "Content-Type": "application/json"})
        if status != 200 or not isinstance(body, dict) or "access_token" not in body:
            raise SystemExit(
                "anonymous sign-in failed (%s): %s\n"
                "Is 'Allow anonymous sign-ins' on in the dashboard?" % (status, body))
        self.token = body["access_token"]
        self.id = body["user"]["id"]

    def call(self, method, path, body=None, extra=None):
        headers = {"apikey": KEY, "Authorization": "Bearer " + self.token,
                   "Content-Type": "application/json"}
        if extra:
            headers.update(extra)
        return _send(method, path, body, headers)

    def rpc(self, fn, **params):
        return self.call("POST", "/rest/v1/rpc/" + fn, params)

    def get_room(self, code):
        status, rows = self.call("GET", "/rest/v1/rooms?code=eq." + code + "&select=*")
        return rows[0] if status == 200 and rows else None

    def patch_room(self, code, body):
        return self.call("PATCH", "/rest/v1/rooms?code=eq." + code, body,
                         {"Prefer": "return=representation"})

    def profile(self, uid=None):
        status, rows = self.call(
            "GET", "/rest/v1/profiles?id=eq." + (uid or self.id) + "&select=*")
        return rows[0] if status == 200 and rows else None


fails = 0


def ok(label, cond, detail=""):
    global fails
    if not cond:
        fails += 1
    print(("  PASS  " if cond else "  FAIL  ") + label
          + ("  " + str(detail) if detail else ""))
    return cond


def done():
    print()
    print("FAILURES:", fails)
    raise SystemExit(1 if fails else 0)
