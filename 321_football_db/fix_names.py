"""
Replace non-Latin player names with their Latin-script equivalents.

WHY
---
The name-repair pass asked Wikidata for twelve languages and used whichever it
found first. For some players — David Beckham among them — English wasn't in
the response, so it stored the Russian label: "Дэвид Бекхэм", with only
Cyrillic spellings accepted. A player typing "Beckham" gets rejected.

This pass finds every player whose name is in a non-Latin script and asks
specifically for a Latin one, preferring English. The original name is KEPT as
an accepted spelling, so both "Beckham" and "Бекхэм" work — which is strictly
better than either alone.

    python fix_names.py             # report what would change
    python fix_names.py --apply     # fix them
"""

from __future__ import annotations

import sys
import unicodedata

import db
from names import normalize_name, name_variants
from wikidata_client import get_entity_labels

# Languages are requested from the API in SMALL TIERS, best first, and each
# tier only asks about players the previous tier couldn't resolve.
#
# This shape is deliberate and hard-won. One big request for twenty languages
# gets rejected outright; a request for ALL languages comes back silently
# incomplete, which is how David Beckham ended up named "Devid Bekhem" — the
# Azerbaijani label — while his English, Spanish, German and French labels
# were simply missing from the response.
#
# "mul" is Wikidata's multilingual label; for footballers it is usually the
# canonical Latin spelling, so it rides along in tier 1.
LANG_TIERS: tuple[tuple[str, ...] | None, ...] = (
    ("en", "mul"),
    ("es", "pt", "it", "de", "fr"),
    ("nl", "tr", "sv", "da", "pl"),
    ("ro", "hu", "cs", "hr", "sk"),
    ("sq", "az", "id", "ms", "vi"),
    None,   # last resort: whatever the API returns, judged purely by script
)

# Flattened, for reporting only.
LATIN_LANGS = tuple(
    lang for tier in LANG_TIERS if tier for lang in tier
)


def is_latin_text(text: str) -> bool:
    """
    True only if every letter in the string is Latin script.

    An ALLOWLIST, checked against Unicode's own character names. The first
    attempt at this was a blocklist of scripts to reject, which is unwinnable:
    Bengali and Ethiopic weren't on the list, so "ইয়াকুব বুয়াশ্চেকভোসস্কি" and
    "ኩዋውቴሞክ ብላንኮ" sailed through as Latin names. There are ~160 scripts in
    Unicode; enumerating the ones you want is finite, enumerating the ones you
    don't is not.
    """
    letters = [char for char in text if char.isalpha()]
    if not letters:
        return False
    for char in letters:
        try:
            if not unicodedata.name(char).startswith("LATIN"):
                return False
        except ValueError:  # unnamed codepoint
            return False
    return True


def is_non_latin(text: str) -> bool:
    """True if the string is not usable on a Latin keyboard."""
    return not is_latin_text(text)


def main() -> int:
    apply_changes = "--apply" in sys.argv
    conn = db.connect()

    players = [
        row for row in conn.execute(
            "SELECT player_id, wikidata_qid, display_name FROM players"
        ).fetchall()
        if is_non_latin(row["display_name"])
    ]

    total = conn.execute("SELECT COUNT(*) AS n FROM players").fetchone()["n"]
    print(f"{len(players):,} of {total:,} players have a non-Latin name\n")

    if not players:
        print("Nothing to fix.")
        conn.close()
        return 0

    for row in players[:8]:
        print(f"   {row['display_name']}  [{row['wikidata_qid']}]")
    if len(players) > 8:
        print(f"   ... and {len(players) - 8:,} more")

    qid_to_row = {row["wikidata_qid"]: row for row in players}

    resolved: dict[str, tuple[str, str]] = {}   # qid -> (name, language)
    remaining = list(qid_to_row)

    for tier_index, tier in enumerate(LANG_TIERS, start=1):
        if not remaining:
            break
        asked = ", ".join(tier) if tier else "any (last resort)"
        print(f"\ntier {tier_index}: asking for [{asked}] "
              f"for {len(remaining):,} player(s)")

        labels_by_qid = get_entity_labels(remaining, tier)

        still: list[str] = []
        for qid in remaining:
            labels = labels_by_qid.get(qid) or {}
            chosen = None
            chosen_lang = None

            order = tier if tier else sorted(labels)
            for lang in order:
                candidate = labels.get(lang)
                if candidate and is_latin_text(candidate):
                    chosen = candidate
                    chosen_lang = lang if tier else f"{lang}*"
                    break

            if chosen:
                resolved[qid] = (chosen, chosen_lang)
            else:
                still.append(qid)

        print(f"    resolved {len(remaining) - len(still):,}, "
              f"{len(still):,} still unnamed")
        remaining = still

    planned: list[tuple[int, str, str, str]] = []
    unfixable: list[str] = []

    for qid, row in qid_to_row.items():
        if qid in resolved:
            new_name, lang = resolved[qid]
            if new_name != row["display_name"]:
                planned.append((row["player_id"], row["display_name"], new_name, lang))
        else:
            unfixable.append(row["display_name"])

    print(f"\n{len(planned):,} name(s) can be replaced with a Latin-script version")
    print("   (* = language not in the preference list, chosen by script)")
    for _, old, new, lang in planned[:12]:
        print(f"   [{lang:<6}] {old}  ->  {new}")
    if len(planned) > 10:
        print(f"   ... and {len(planned) - 10:,} more")

    if unfixable:
        print(f"\n{len(unfixable):,} player(s) have NO Latin-script name on Wikidata.")
        print("They keep their current name and stay answerable in that script only.")

    if not apply_changes:
        print("\nNothing changed. To apply:")
        print("    python fix_names.py --apply")
        conn.close()
        return 0

    for player_id, old_name, new_name, _lang in planned:
        conn.execute(
            """UPDATE players SET full_name = ?, display_name = ?,
                      normalized_name = ?, updated_at = datetime('now')
               WHERE player_id = ?""",
            (new_name, new_name, normalize_name(new_name), player_id),
        )
        # Keep the old script as an accepted spelling — a Russian speaker
        # typing Бекхэм should still score.
        db.add_player_alias(conn, player_id, old_name)
        for variant in name_variants(old_name):
            db.add_player_alias(conn, player_id, variant)
        # And add the new Latin spellings.
        for variant in name_variants(new_name):
            db.add_player_alias(conn, player_id, variant)

    conn.commit()
    print(f"\nRenamed {len(planned):,} player(s). Both spellings are accepted.")
    print("\nRe-run verification:")
    print("    python build_database.py --from 6")

    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
