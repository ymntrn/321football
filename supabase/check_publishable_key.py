"""Does the new-style publishable key work against this project?

The Dart client uses `publishableKey` (the legacy `anonKey` parameter is
deprecated), so it is worth proving the key actually authenticates before
trusting it inside the app, where a failure surfaces as an opaque socket or
401 error.
"""
import json
import urllib.request
import urllib.error

URL = "https://yjdcsdikcrdupqmaqoqn.supabase.co"
PUBLISHABLE = "sb_publishable_gGylTdpJ4aI3KU6u6UNr9Q_ZaUhHthO"


def call(key, method, path, body=None):
    headers = {
        "apikey": key,
        "Authorization": "Bearer " + key,
        "Content-Type": "application/json",
    }
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


print("rpc server_now      ->", call(PUBLISHABLE, "POST", "/rest/v1/rpc/server_now", {}))
print("select rooms        ->", call(PUBLISHABLE, "GET", "/rest/v1/rooms?select=code&limit=1"))
status, _ = call(PUBLISHABLE, "GET", "/rest/v1/rooms?select=code&limit=1")
print()
print("VERDICT:", "publishable key works" if status == 200
      else "publishable key REJECTED (%s) - keep the anon JWT" % status)
