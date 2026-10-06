"""
Hand-set names for specific players, by Wikidata ID.

WHY THIS IS THE RIGHT ANSWER, NOT A HACK
----------------------------------------
Wikidata's label API is unreliable in ways that cost several attempts to pin
down: it rejects large language requests outright, and silently returns
incomplete label sets for open-ended ones. For 92,000 obscure players that
unreliability is tolerable. For David Beckham it is not — a football trivia
game that can't accept "Beckham" is broken in a way users will notice
immediately.

So for a small number of famous players, the name is stated here explicitly.
Deterministic, auditable, and immune to whatever the API does next. Every
entry is keyed by Wikidata ID rather than by name, so it can't drift onto the
wrong player.

    python manual_names.py                  # show what would change
    python manual_names.py --apply          # apply the overrides
    python manual_names.py --suspects       # find more players worth fixing

Add entries as you find them. The original name is always kept as an accepted
spelling, so nothing becomes less answerable.
"""

from __future__ import annotations

import sys

import db
from names import normalize_name, name_variants

# Wikidata ID -> the name the game should display and accept.
# Only add a QID you have actually confirmed (inspect_player.py QID shows the
# player's clubs, which is enough to identify him).
OVERRIDES: dict[str, str] = {
    "Q10520": "David Beckham",   # confirmed: Man Utd 1992-2003, Real Madrid 2003-2007
}


def apply_overrides(conn, dry_run: bool) -> int:
    changed = 0
    for qid, correct_name in OVERRIDES.items():
        row = conn.execute(
            "SELECT player_id, display_name FROM players WHERE wikidata_qid = ?",
            (qid,),
        ).fetchone()

        if not row:
            print(f"  {qid}: not in the database — skipped")
            continue

        if row["display_name"] == correct_name:
            print(f"  {qid}: already '{correct_name}'")
            continue

        print(f"  {qid}: '{row['display_name']}'  ->  '{correct_name}'")
        changed += 1

        if dry_run:
            continue

        conn.execute(
            """UPDATE players SET full_name = ?, display_name = ?,
                      normalized_name = ?, needs_label = 0,
                      updated_at = datetime('now')
               WHERE player_id = ?""",
            (correct_name, correct_name, normalize_name(correct_name), row["player_id"]),
        )
        # Keep whatever it was called before, so no existing answer breaks.
        db.add_player_alias(conn, row["player_id"], row["display_name"])
        for variant in name_variants(row["display_name"]):
            db.add_player_alias(conn, row["player_id"], variant)
        for variant in name_variants(correct_name):
            db.add_player_alias(conn, row["player_id"], variant)

    if not dry_run:
        conn.commit()
    return changed


def show_suspects(conn) -> None:
    """
    Famous players whose stored name looks wrong.

    High fame means the player turned out for well-known clubs, so a mangled
    name there is far more damaging than the same problem on a lower-league
    journeyman. These are the ones worth ten seconds of hand-checking.
    """
    from fix_names import is_latin_text

    print("Players with high fame whose name may be wrong")
    print("(check with: python inspect_player.py <QID>)\n")

    rows = conn.execute("""
        SELECT wikidata_qid, display_name, fame_score, club_count
        FROM players
        WHERE club_count >= 2 AND fame_score >= 85
        ORDER BY fame_score DESC
        LIMIT 4000
    """).fetchall()

    suspects = []
    for row in rows:
        name = row["display_name"]
        if not is_latin_text(name) or (name.startswith("Q") and name[1:].isdigit()):
            suspects.append(row)

    if not suspects:
        print("  None — every high-fame player has a Latin-script name.")
        return

    for row in suspects[:60]:
        print(f"  {row['fame_score']:5.1f}  {row['wikidata_qid']:<12} "
              f"{row['display_name']}  ({row['club_count']} clubs)")
    if len(suspects) > 60:
        print(f"  ... and {len(suspects) - 60} more")

    print(f"\n{len(suspects)} suspect(s). Add the ones that matter to OVERRIDES "
          f"in this file.")


def main() -> int:
    conn = db.connect()

    if "--suspects" in sys.argv:
        show_suspects(conn)
        conn.close()
        return 0

    dry_run = "--apply" not in sys.argv
    print(f"{len(OVERRIDES)} override(s) defined\n")
    changed = apply_overrides(conn, dry_run)

    if dry_run:
        print(f"\n{changed} would change. To apply:")
        print("    python manual_names.py --apply")
    else:
        print(f"\nApplied {changed} override(s). Both old and new spellings accepted.")
        print("\nRe-run verification:")
        print("    python build_database.py --from 6")

    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
