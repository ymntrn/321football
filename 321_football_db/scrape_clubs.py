"""
STEP 1 — discover every club that has played in each league since the cutoff.

WHY THIS GOES THROUGH SEASONS RATHER THAN "current league"
----------------------------------------------------------
The obvious query is `?club wdt:P118 wd:Q9448` ("club's league is the Premier
League"). That returns the 20 clubs in it RIGHT NOW — which would silently
throw away Blackburn, Bolton, Wigan, Portsmouth, Charlton and every other side
that has been in the Premier League since 1990 and since dropped out. For a
game built on players from the last 30+ years, that would gut the database.

So we instead walk the league's SEASONS (P3450 "sports season of league or
competition") and collect each season's participating teams (P1923). That
gives the full historical membership. We still union in the P118 current
members as a safety net for leagues whose season items are sparse.
"""

from __future__ import annotations

import re
import sys

import config
import db
from wikidata_client import (
    run_sparql, qid_from_uri, value, year_from_iso, QueryTooBig,
)

# Label patterns that suggest a reserve/B/youth side when the structural
# check misses it. Deliberately anchored so we don't eat real clubs
# (e.g. "Hertha BSC" must not match " B", "Boca Juniors II" must).
RESERVE_LABEL_PATTERNS = [
    r"\bII\b", r"\bB\s*team\b", r"\breserves?\b", r"\bamateure?\b",
    r"\bacademy\b", r"\byouth\b", r"\bU-?\s?(16|17|18|19|20|21|23)\b",
    r"\bjuvenil\b", r"\bjunior(s)?\b", r"\bcastilla\b", r"\batlètic\b",
    r"\batletic\b", r"\bfutbol base\b", r"\bsub-?\d{2}\b",
]
_RESERVE_RE = re.compile("|".join(RESERVE_LABEL_PATTERNS), re.IGNORECASE)

# A trailing standalone " B" ("FC Barcelona B", "Bayern Munich B").
_TRAILING_B_RE = re.compile(r"\s+B$")

SEASON_YEAR_RE = re.compile(r"(19|20)\d{2}")


# The cutoff is applied INSIDE the query, not afterwards in Python. Several of
# these leagues own 100+ season items (Belgium 139, Eredivisie 138, Serie A
# 125); pulling all of them and then discarding the pre-1990 ones means asking
# WDQS for tens of thousands of rows it will often refuse to compute inside its
# 60-second budget. Filtering here cuts Belgium from 139 seasons to ~36.
#
# The !BOUND clause keeps seasons that have no recorded start date rather than
# silently dropping them — undated seasons are still filtered later in Python
# once we've tried to parse a year out of the season's label.
CLUBS_FOR_LEAGUE_QUERY = """
SELECT DISTINCT ?club ?clubLabel ?seasonLabel ?seasonStart ?countryLabel
                ?founded ?partOf ?typeLabel WHERE {{
  {{
    ?season wdt:P3450 wd:{league_qid} .
    ?season wdt:P1923 ?club .
    OPTIONAL {{ ?season wdt:P580 ?seasonStart . }}
    FILTER (!BOUND(?seasonStart) || YEAR(?seasonStart) >= {cutoff_year})
  }}
  UNION
  {{
    # p:/ps: rather than wdt:, deliberately. wdt: exposes only a property's
    # BEST-RANKED value, so a club that is currently in the Premiership and
    # was previously in the SPL only reports the Premiership — its historical
    # league statements are invisible. Walking the full statement node picks
    # up every league a club has ever been recorded in, which is exactly what
    # a database covering 1990-onward needs.
    ?club p:P118 ?leagueStatement .
    ?leagueStatement ps:P118 wd:{league_qid} .
  }}
  ?club wdt:P31/wdt:P279* wd:Q476028 .   # must be an association football club
  OPTIONAL {{ ?club wdt:P17 ?country . }}
  OPTIONAL {{ ?club wdt:P571 ?founded . }}
  OPTIONAL {{ ?club wdt:P361 ?partOf . }}
  OPTIONAL {{ ?club wdt:P31 ?type . }}
  SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en". }}
}}
"""

# Last resort when even the filtered query is too expensive. Drops every
# OPTIONAL and the subclass walk, keeping only what we cannot do without:
# which clubs, and which season they appeared in. Country/founded/reserve
# detection degrade to "unknown", which is survivable — a club with a missing
# founding year still works perfectly well in the game.
CLUBS_MINIMAL_QUERY = """
SELECT DISTINCT ?club ?clubLabel ?seasonStart WHERE {{
  ?season wdt:P3450 wd:{league_qid} .
  ?season wdt:P1923 ?club .
  OPTIONAL {{ ?season wdt:P580 ?seasonStart . }}
  FILTER (!BOUND(?seasonStart) || YEAR(?seasonStart) >= {cutoff_year})
  SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en". }}
}}
"""

# Fallback used when the season-based query returns suspiciously little:
# some leagues' season items don't use P1923 at all, and instead the clubs
# carry P118 with a qualifier, or the season lists teams via P527 (has part).
CLUBS_FALLBACK_QUERY = """
SELECT DISTINCT ?club ?clubLabel ?seasonLabel ?seasonStart ?countryLabel
                ?founded ?partOf ?typeLabel WHERE {{
  ?season wdt:P3450 wd:{league_qid} .
  ?season wdt:P527 ?club .
  ?club wdt:P31/wdt:P279* wd:Q476028 .
  OPTIONAL {{ ?season wdt:P580 ?seasonStart . }}
  OPTIONAL {{ ?club wdt:P17 ?country . }}
  OPTIONAL {{ ?club wdt:P571 ?founded . }}
  OPTIONAL {{ ?club wdt:P361 ?partOf . }}
  OPTIONAL {{ ?club wdt:P31 ?type . }}
  SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en". }}
}}
"""


def looks_like_reserve_team(label: str, part_of: str | None, type_label: str | None) -> tuple[bool, str | None]:
    """
    Returns (is_reserve, detection_method).

    IMPORTANT: "part of" (P361) is NOT used as a standalone signal, even though
    B-teams do use it. Enormous numbers of perfectly real first teams are also
    "part of" something — every European multi-sport club works this way.
    Galatasaray, Fenerbahçe and Beşiktaş are multi-sport institutions whose
    football team is a part of the parent club, as are Barcelona, Bayern,
    Olympiacos and dozens more. Treating P361 as proof of a B-team deletes
    exactly the clubs a football trivia game cannot live without.

    So we require the NAME or the TYPE to say reserve/B/youth. P361 is only
    accepted as corroboration alongside a suggestive label, never on its own.
    A genuine B-team essentially always announces itself in its name — that is
    the whole point of calling it "B".
    """
    if type_label and "reserve" in type_label.lower():
        return True, "type_label"

    label_says_reserve = bool(_RESERVE_RE.search(label) or _TRAILING_B_RE.search(label))
    if label_says_reserve:
        return True, "part_of+label" if part_of else "label_hint"

    return False, None


def season_year(row: dict) -> int | None:
    """Prefer the season's structured start date; fall back to its label."""
    year = year_from_iso(value(row, "seasonStart"))
    if year:
        return year
    label = value(row, "seasonLabel") or ""
    match = SEASON_YEAR_RE.search(label)
    return int(match.group(0)) if match else None


def scrape_league_clubs(conn, league_row) -> dict:
    league_qid = league_row["wikidata_qid"]
    league_id = league_row["league_id"]
    league_name = league_row["name"]

    batch_id = db.start_batch(conn, target_type="league",
                              target_qid=league_qid, target_label=league_name)

    degraded = False
    try:
        rows = run_sparql(CLUBS_FOR_LEAGUE_QUERY.format(
            league_qid=league_qid, cutoff_year=config.CUTOFF_YEAR))
    except QueryTooBig:
        # Rather than abandoning the league, retry with everything optional
        # stripped out. Losing a club's founding year is a far better outcome
        # than losing the club.
        print("      full query too heavy — retrying with the minimal query")
        try:
            rows = run_sparql(CLUBS_MINIMAL_QUERY.format(
                league_qid=league_qid, cutoff_year=config.CUTOFF_YEAR))
            degraded = True
        except QueryTooBig:
            print("      minimal query also timed out — skipping, safe to re-run later")
            db.finish_batch(conn, batch_id, status="failed", flagged=True,
                            notes="SPARQL timeout on club discovery, even minimal query")
            return {"league": league_name, "clubs": 0, "failed": True}

    if len({qid_from_uri(value(r, "club")) for r in rows}) < config.MIN_EXPECTED_CLUBS_PER_LEAGUE:
        print(f"      only {len(rows)} rows from the season query — trying the P527 fallback")
        try:
            rows += run_sparql(CLUBS_FALLBACK_QUERY.format(league_qid=league_qid))
        except Exception as exc:  # noqa: BLE001 — the fallback is best-effort
            print(f"      fallback query failed ({exc.__class__.__name__}), continuing")

    # ---- fold rows (one club can appear once per season) into club records
    clubs: dict[str, dict] = {}
    for row in rows:
        club_uri = value(row, "club")
        if not club_uri:
            continue
        qid = qid_from_uri(club_uri)
        label = value(row, "clubLabel") or qid

        entry = clubs.setdefault(qid, {
            "qid": qid,
            "label": label,
            "country": value(row, "countryLabel"),
            "founded": year_from_iso(value(row, "founded")),
            "part_of": value(row, "partOf"),
            "type_label": value(row, "typeLabel"),
            "seasons": set(),
        })
        # Keep any non-null detail we encounter across rows.
        entry["country"] = entry["country"] or value(row, "countryLabel")
        entry["founded"] = entry["founded"] or year_from_iso(value(row, "founded"))
        entry["part_of"] = entry["part_of"] or value(row, "partOf")

        year = season_year(row)
        if year:
            entry["seasons"].add(year)

    # ---- filter and persist
    inserted = 0
    skipped_reserve = 0
    skipped_pre_cutoff = 0

    for entry in clubs.values():
        is_reserve, method = looks_like_reserve_team(
            entry["label"], entry["part_of"], entry["type_label"]
        )
        if is_reserve and config.EXCLUDE_RESERVE_TEAMS:
            skipped_reserve += 1
            continue

        seasons = entry["seasons"]
        # A club whose every recorded season predates the cutoff is out of
        # scope. A club with NO recorded seasons is kept — it came from the
        # P118 current-members branch, so it's in the league today.
        if seasons and max(seasons) < config.CUTOFF_YEAR:
            skipped_pre_cutoff += 1
            continue

        club_id = db.upsert_club(
            conn, qid=entry["qid"], name=entry["label"],
            country=entry["country"], founded_year=entry["founded"],
            is_reserve=False, reserve_method=None,
        )
        db.add_club_alias(conn, club_id, entry["label"])

        relevant = [y for y in seasons if y >= config.CUTOFF_YEAR] or [None]
        for year in relevant:
            db.link_club_league(conn, club_id, league_id, year)
        inserted += 1

    conn.commit()

    flagged = inserted < config.MIN_EXPECTED_CLUBS_PER_LEAGUE
    notes = []
    if flagged:
        notes.append(f"only {inserted} clubs found — check the league QID is right")
    if degraded:
        notes.append("minimal query used: country/founded/reserve-detection unavailable")

    db.finish_batch(
        conn, batch_id,
        status="needs_review" if flagged else "success",
        flagged=flagged,
        notes="; ".join(notes) or None,
        clubs_found=inserted, clubs_skipped_reserve=skipped_reserve,
    )

    return {
        "league": league_name,
        "clubs": inserted,
        "skipped_reserve": skipped_reserve,
        "skipped_pre_cutoff": skipped_pre_cutoff,
        "flagged": flagged,
        "degraded": degraded,
        "failed": False,
    }


def main() -> int:
    conn = db.connect()
    db.init_schema(conn)

    leagues = conn.execute("SELECT * FROM leagues ORDER BY tier, name").fetchall()
    if not leagues:
        print("No leagues in the database. Run resolve_leagues.py first.")
        return 1

    print(f"Discovering clubs for {len(leagues)} leagues "
          f"(seasons from {config.CUTOFF_YEAR} onward)\n")

    total = 0
    flagged_leagues = []
    for league_row in leagues:
        print(f"  {league_row['name']} ({league_row['country']})...", flush=True)
        result = scrape_league_clubs(conn, league_row)
        total += result["clubs"]
        marker = "  !! FLAGGED" if result.get("flagged") or result.get("failed") else ""
        if marker:
            flagged_leagues.append(result["league"])
        degraded_note = "  [minimal query]" if result.get("degraded") else ""
        print(f"      {result['clubs']} clubs "
              f"({result.get('skipped_reserve', 0)} reserve/B teams excluded, "
              f"{result.get('skipped_pre_cutoff', 0)} pre-{config.CUTOFF_YEAR} only)"
              f"{degraded_note}{marker}")

    db.refresh_counters(conn)

    distinct = conn.execute("SELECT COUNT(*) AS n FROM clubs").fetchone()["n"]
    print(f"\n{distinct} distinct clubs in the database "
          f"({total} league-memberships recorded).")

    if flagged_leagues:
        print(f"\n{len(flagged_leagues)} league(s) returned suspiciously few clubs:")
        for name in flagged_leagues:
            print(f"   - {name}")
        print("Check those league QIDs on wikidata.org before scraping players.")

    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
