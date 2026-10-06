"""A second player, for testing a match from one machine.

    python supabase\bot.py 123456          join that room and play
    python supabase\bot.py --host          create a room, print the code, wait
    python supabase\bot.py 123456 --slow    always answer slowly, so you win

The emulator cannot be run twice on this machine (one instance is 2.4 GB of
7.7), and there is no second phone, so this stands in for the opponent. It
speaks the same HTTP the app does, so it exercises the real room logic rather
than a mock.

What it deliberately does NOT do: guess. It reads the answer key straight out
of the shipped SQLite database, the same file the app carries, so a failure
here is always a protocol or timing bug and never the bot being bad at
football.
"""
import argparse
import random
import sqlite3
import sys
import time

from sbclient import Player

DB = r"C:\Users\PC\Documents\321-football\app\assets\db\321_football.db"

# Since 006_accounts.sql a room is visible only to its two players, so the bot
# signs in anonymously exactly like the app and gets its own auth user (and a
# profile called --name, so match results land on it).
bot = None


def rpc(fn, **params):
    return bot.rpc(fn, **params)


def get_room(code):
    return bot.get_room(code)


def patch(code, body):
    return bot.patch_room(code, body)


# ---------------------------------------------------------------------------
# The football bits, read from the same database the app ships
# ---------------------------------------------------------------------------
db = sqlite3.connect(DB)


def pick_club(avoid_id=None):
    """A famous club that actually has players, so rounds stay playable."""
    rows = db.execute("""
        SELECT c.club_id, c.canonical_name FROM clubs c
         WHERE c.is_reserve_or_b_team = 0
           AND c.canonical_name <> c.wikidata_qid
           AND c.fame_score > 90
           AND EXISTS (SELECT 1 FROM player_club_spells s
                        WHERE s.club_id = c.club_id)
           AND (? IS NULL OR c.club_id <> ?)
         ORDER BY RANDOM() LIMIT 1
    """, (avoid_id, avoid_id)).fetchone()
    return rows


def mutual_answer(club_a, club_b):
    """The most famous player who played for both, or None."""
    row = db.execute("""
        SELECT p.display_name FROM players p
         WHERE p.player_id IN (
             SELECT player_id FROM player_club_spells WHERE club_id = ?
             INTERSECT
             SELECT player_id FROM player_club_spells WHERE club_id = ?
         )
         ORDER BY p.fame_score DESC LIMIT 1
    """, (club_a, club_b)).fetchone()
    return row[0] if row else None


# ---------------------------------------------------------------------------
def play(code, me, seat, slow):
    other = "host" if seat == "guest" else "guest"
    print("bot is %s in room %s" % (seat, code))
    last_phase = None
    last_round = None

    while True:
        room = get_room(code)
        if room is None:
            print("room vanished")
            return

        phase, rnd = room["phase"], room["round"]
        if (phase, rnd) != (last_phase, last_round):
            print("  [%s] round %s   %s %d-%d %s" % (
                phase, rnd, room["host_name"], room["host_score"],
                room["guest_score"], room["guest_name"]))
            last_phase, last_round = phase, rnd

        if phase == "match_over":
            print("  match over: %s wins (%s)" % (room["winner"],
                                                  room["ended_reason"]))
            return

        if phase == "picking" and room[seat + "_club_id"] is None:
            time.sleep(random.uniform(0.8, 2.0))   # look human
            club = pick_club(room[other + "_club_id"])
            patch(code, {seat + "_club_id": club[0],
                         seat + "_club_name": club[1]})
            print("    picked %s" % club[1])

        elif phase == "answering" and room[seat + "_elapsed_ms"] is None:
            answer = mutual_answer(room["host_club_id"], room["guest_club_id"])
            if answer is None:
                print("    no mutual player exists - waiting it out")
            else:
                delay = random.uniform(5.5, 8.0) if slow \
                    else random.uniform(1.5, 3.5)
                time.sleep(delay)
                elapsed = int(delay * 1000)
                patch(code, {seat + "_answer": answer,
                             seat + "_elapsed_ms": elapsed})
                print("    answered %s after %d ms" % (answer, elapsed))

        rpc("touch_seen", p_code=code, p_seat=seat)
        time.sleep(0.5)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("code", nargs="?")
    ap.add_argument("--host", action="store_true")
    ap.add_argument("--slow", action="store_true")
    ap.add_argument("--name", default="Bot")
    args = ap.parse_args()

    global bot
    bot = Player()
    status, prof = bot.rpc("create_profile", p_username=args.name)
    if status != 200:
        sys.exit("could not create the bot's profile: %s" % prof)
    print("bot is %s#%s" % (prof["username"], prof["tag"]))
    me = bot.id

    if args.host:
        status, room = rpc("create_room", p_host_id=me, p_host_name=args.name)
        print("ROOM CODE: %s" % room["code"])
        print("join it from the app, then the bot will start the match")
        code, seat = room["code"], "host"
        while True:
            r = get_room(code)
            if r and r["guest_id"]:
                print("guest joined: %s" % r["guest_name"])
                break
            time.sleep(1)
        rpc("start_match", p_code=code)
    else:
        if not args.code:
            sys.exit("give a room code, or use --host")
        code, seat = args.code, "guest"
        status, room = rpc("join_room", p_code=code, p_guest_id=me,
                           p_guest_name=args.name)
        if status != 200:
            sys.exit("could not join: %s" % room)
        print("joined %s as %s" % (code, args.name))

    play(code, me, seat, args.slow)


if __name__ == "__main__":
    main()
