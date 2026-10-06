"""
STEP 3 — enrichment.

Three things, none of which the core scrape covers:

  1. trophy_count         : major honours won (P2522 "victory") — a prestige
                            signal for the fame score
  2. top_division_seasons : seasons spent in a tier-1 league since the cutoff,
                            derived from our own club_leagues table
  3. player aliases       : the REAL alternate names Wikidata holds for each
                            player (skos:altLabel), in several languages

(3) matters more than it sounds. A player stored as "Ronaldo Luís Nazário de
Lima" will never be matched by someone typing "Ronaldo" unless we have his
actual alternate names — and the generated variants (surname, initial+surname)
don't cover nicknames like "Ronaldinho", "Kaká" or "Pelé". Pulling the real
aliases is what makes the answer box feel fair.

Together, (1) and (2) stop the difficulty ranking from degenerating into "how
much does Wikidata happen to know about this club", which would rate a
well-documented small club as famous.
"""

from __future__ import annotations

import sys

import db
from names import normalize_name, name_variants
from wikidata_client import (
    run_chunked, run_sparql, qid_from_uri, value, get_entity_labels, QueryTooBig,
)

TROPHIES_QUERY_TEMPLATE = """
SELECT ?club (COUNT(DISTINCT ?title) AS ?titles) WHERE {{
  VALUES ?club {{ {clubs} }}
  ?club wdt:P2522 ?title .     # victory (competitions won)
}}
GROUP BY ?club
"""


def build_trophy_query(qids: list[str]) -> str:
    return TROPHIES_QUERY_TEMPLATE.format(clubs=" ".join(f"wd:{q}" for q in qids))


def enrich_trophies(conn) -> int:
    clubs = conn.execute(
        "SELECT club_id, wikidata_qid FROM clubs WHERE is_reserve_or_b_team = 0"
    ).fetchall()
    qid_to_id = {row["wikidata_qid"]: row["club_id"] for row in clubs}

    print(f"Fetching trophy counts for {len(qid_to_id)} clubs...")
    rows = run_chunked(list(qid_to_id), build_trophy_query, label="trophy chunk")

    updated = 0
    for row in rows:
        qid = qid_from_uri(value(row, "club"))
        club_id = qid_to_id.get(qid)
        if club_id is None:
            continue
        try:
            count = int(value(row, "titles") or 0)
        except ValueError:
            continue
        conn.execute("UPDATE clubs SET trophy_count = ? WHERE club_id = ?", (count, club_id))
        updated += 1

    conn.commit()
    return updated


# How many language Wikipedias carry an article about this club.
#
# This is the single best available proxy for FAME, which is what the game
# actually needs. Squad depth measures how thoroughly Wikidata documents a
# club, not how well known it is — which is why an initial run put Hibernian
# and Samsunspor above Manchester United. Sitelinks measure recognition
# directly: Real Madrid appears in ~180 languages, Sheffield United ~50,
# Samsunspor ~25. That ordering is the one a player's intuition agrees with.
SITELINKS_QUERY_TEMPLATE = """
SELECT ?club ?sitelinks WHERE {{
  VALUES ?club {{ {clubs} }}
  ?club wikibase:sitelinks ?sitelinks .
}}
"""


def build_sitelinks_query(qids: list[str]) -> str:
    return SITELINKS_QUERY_TEMPLATE.format(clubs=" ".join(f"wd:{q}" for q in qids))


def enrich_sitelinks(conn) -> int:
    db.ensure_column(conn, "clubs", "sitelink_count", "INTEGER NOT NULL DEFAULT 0")

    clubs = conn.execute(
        "SELECT club_id, wikidata_qid FROM clubs WHERE is_reserve_or_b_team = 0"
    ).fetchall()
    qid_to_id = {row["wikidata_qid"]: row["club_id"] for row in clubs}
    if not qid_to_id:
        return 0

    print(f"Fetching Wikipedia language coverage for {len(qid_to_id)} clubs...")
    rows = run_chunked(list(qid_to_id), build_sitelinks_query,
                       chunk_size=200, label="sitelink chunk")

    updated = 0
    for row in rows:
        qid = qid_from_uri(value(row, "club"))
        club_id = qid_to_id.get(qid)
        if club_id is None:
            continue
        try:
            count = int(value(row, "sitelinks") or 0)
        except ValueError:
            continue
        conn.execute("UPDATE clubs SET sitelink_count = ? WHERE club_id = ?",
                     (count, club_id))
        updated += 1

    conn.commit()
    return updated


def compute_top_division_seasons(conn) -> int:
    """
    Derived locally from club_leagues — no extra scraping needed.

    We count the span of seasons a club has recorded in any tier-1 league.
    It's an approximation (a club could miss a season mid-span) but it's a
    solid prestige proxy and it costs nothing.
    """
    conn.execute("""
        UPDATE clubs SET top_division_seasons = COALESCE((
            SELECT SUM(
                CASE
                    WHEN cl.first_season IS NULL OR cl.last_season IS NULL THEN 1
                    ELSE (cl.last_season - cl.first_season) + 1
                END
            )
            FROM club_leagues cl
            JOIN leagues l ON l.league_id = cl.league_id
            WHERE cl.club_id = clubs.club_id AND l.tier = 1
        ), 0)
    """)
    conn.commit()
    return conn.execute(
        "SELECT COUNT(*) AS n FROM clubs WHERE top_division_seasons > 0"
    ).fetchone()["n"]


# -------------------------------------------------------------------------
# Player aliases — the real ones, from Wikidata
# -------------------------------------------------------------------------
# Several languages, because the name a player is commonly known by often
# isn't the English one: Turkish players in tr, Brazilians in pt, and so on.
ALIAS_LANGS = ("en", "tr", "es", "it", "de", "pt", "nl", "fr")

ALIASES_QUERY_TEMPLATE = """
SELECT ?player ?alias WHERE {{
  VALUES ?player {{ {players} }}
  ?player skos:altLabel ?alias .
  FILTER (LANG(?alias) IN ({langs}))
}}
"""


def build_alias_query(qids: list[str]) -> str:
    langs = ", ".join(f'"{code}"' for code in ALIAS_LANGS)
    return ALIASES_QUERY_TEMPLATE.format(
        players=" ".join(f"wd:{q}" for q in qids), langs=langs
    )


# Preference order for a recovered name: English first, then the languages of
# the leagues we cover.
#
# Two lessons are baked into this list. English alone recovered ZERO of 1,217
# players — obscure Saudi, Turkish and Russian footballers routinely have a
# Wikidata item labelled only in their own language, and a name in Turkish
# beats "Q12345" (the normalizer folds Turkish characters anyway, so it stays
# typeable). And these labels are fetched through the wbgetentities API rather
# than SPARQL: two separate SPARQL attempts returned nothing, while the API is
# built for exactly this lookup.
LABEL_LANGS = ("en", "tr", "es", "pt", "it", "de", "fr", "nl", "ru", "ar", "el", "sv")




def repair_missing_labels(conn) -> int:
    """
    Fill in names for players whose label came back as a bare Q-number.

    These players are real and their spells are real — only the name lookup
    failed. Recovering them here is what puts David Beckham back in the
    database.
    """
    db.ensure_column(conn, "players", "needs_label", "INTEGER NOT NULL DEFAULT 0")

    broken = conn.execute("""
        SELECT player_id, wikidata_qid FROM players
        WHERE needs_label = 1 OR display_name GLOB 'Q[0-9]*'
    """).fetchall()

    if not broken:
        return 0

    qid_to_id = {row["wikidata_qid"]: row["player_id"] for row in broken}
    print(f"Repairing names for {len(qid_to_id):,} players whose label lookup failed...")
    print(f"    sample QIDs: {', '.join(list(qid_to_id)[:5])}")

    labels_by_qid = get_entity_labels(list(qid_to_id))
    print(f"    Wikidata returned labels for {len(labels_by_qid):,} of "
          f"{len(qid_to_id):,} entities")

    # Pick the label highest up LABEL_LANGS — English when it exists — then
    # fall back to ANY label rather than leaving the player nameless. A name
    # in an unexpected language beats "Q12345"; fix_names.py later upgrades
    # non-Latin names to Latin ones where Wikidata has them.
    best: dict[str, str] = {}
    for qid, labels in labels_by_qid.items():
        if qid not in qid_to_id:
            continue

        def usable(text: str | None) -> bool:
            return bool(text) and not (text.startswith("Q") and text[1:].isdigit())

        for lang in LABEL_LANGS:
            if usable(labels.get(lang)):
                best[qid] = labels[lang]
                break
        else:
            for lang in sorted(labels):
                if usable(labels[lang]):
                    best[qid] = labels[lang]
                    break

    repaired = 0
    for qid, label in best.items():
        player_id = qid_to_id[qid]
        conn.execute(
            """UPDATE players SET full_name = ?, display_name = ?,
                      normalized_name = ?, needs_label = 0,
                      updated_at = datetime('now')
               WHERE player_id = ?""",
            (label, label, normalize_name(label), player_id),
        )
        # Now that we have a real name, the generated spellings are safe.
        for variant in name_variants(label):
            db.add_player_alias(conn, player_id, variant)
        repaired += 1

    conn.commit()

    still_broken = conn.execute(
        "SELECT COUNT(*) AS n FROM players WHERE needs_label = 1"
    ).fetchone()["n"]
    if still_broken:
        print(f"    {still_broken} player(s) still have no usable name "
              f"in any of: {', '.join(LABEL_LANGS)}")
        leftover = conn.execute("""
            SELECT wikidata_qid FROM players WHERE needs_label = 1 LIMIT 5
        """).fetchall()
        print(f"    check one by hand:  python debug_wikidata.py "
              f"{leftover[0]['wikidata_qid'] if leftover else 'Q…'}")

    return repaired


NATIONALITY_QUERY_TEMPLATE = """
SELECT ?player ?nationalityLabel WHERE {{
  VALUES ?player {{ {players} }}
  ?player wdt:P27 ?nationality .
  SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en". }}
}}
"""


def build_nationality_query(qids: list[str]) -> str:
    return NATIONALITY_QUERY_TEMPLATE.format(players=" ".join(f"wd:{q}" for q in qids))


def enrich_nationalities(conn) -> int:
    """
    Fetch each player's nationality — the one biographical field we store.

    Done here rather than during the spell scrape because nationality is a
    per-player fact: fetching it inline duplicated every spell row for anyone
    with dual nationality, bloating responses that were already large enough
    for WDQS to truncate.

    Players with several nationalities keep the first one returned; the game
    only uses this as a display detail, so picking one is fine.
    """
    players = conn.execute(
        "SELECT player_id, wikidata_qid FROM players WHERE nationality IS NULL"
    ).fetchall()
    qid_to_id = {row["wikidata_qid"]: row["player_id"] for row in players}

    if not qid_to_id:
        return 0

    print(f"Fetching nationality for {len(qid_to_id):,} players...")
    rows = run_chunked(list(qid_to_id), build_nationality_query,
                       chunk_size=150, label="nationality chunk")

    seen: set[int] = set()
    updated = 0
    for row in rows:
        qid = qid_from_uri(value(row, "player"))
        player_id = qid_to_id.get(qid)
        nationality = value(row, "nationalityLabel")
        if player_id is None or not nationality or player_id in seen:
            continue
        seen.add(player_id)
        conn.execute(
            "UPDATE players SET nationality = ? WHERE player_id = ?",
            (nationality, player_id),
        )
        updated += 1

    conn.commit()
    return updated


def ensure_alias_tracking(conn) -> None:
    """
    Add the aliases_fetched marker column if it isn't there yet.

    Needed so this step can resume. Without it, an interrupted alias fetch
    has no way to tell which players it already covered, and re-running would
    redo tens of thousands of queries from scratch.
    """
    columns = {row["name"] for row in conn.execute("PRAGMA table_info(players)")}
    if "aliases_fetched" not in columns:
        conn.execute(
            "ALTER TABLE players ADD COLUMN aliases_fetched INTEGER NOT NULL DEFAULT 0"
        )
        conn.commit()


def enrich_player_aliases(conn) -> int:
    """
    Fetch real alternate names, but ONLY for players who can actually be an
    answer.

    A player with a single club in the database can never be a mutual player
    between two clubs, so his nicknames are dead weight — fetching them was
    roughly tripling the size of this step and pushing us into WDQS rate
    limiting for no gain. Filtering to club_count >= 2 typically cuts the work
    by more than half.

    Progress is committed per chunk and each player is marked as done, so an
    interrupted run resumes instead of starting over.
    """
    ensure_alias_tracking(conn)

    players = conn.execute("""
        SELECT player_id, wikidata_qid FROM players
        WHERE club_count >= 2 AND aliases_fetched = 0
    """).fetchall()

    total_players = conn.execute("SELECT COUNT(*) AS n FROM players").fetchone()["n"]
    already = conn.execute(
        "SELECT COUNT(*) AS n FROM players WHERE aliases_fetched = 1"
    ).fetchone()["n"]

    if not players:
        print(f"  alternate names already fetched for every multi-club player "
              f"({already:,} done)")
        return 0

    qid_to_id = {row["wikidata_qid"]: row["player_id"] for row in players}
    skipped = total_players - len(qid_to_id) - already

    print(f"Fetching alternate names for {len(qid_to_id):,} players "
          f"({skipped:,} single-club players skipped — they can never be an answer"
          + (f"; {already:,} already done)" if already else ")"))

    chunk_size = 250
    added = 0
    qids = list(qid_to_id)
    index = 0

    while index < len(qids):
        chunk = qids[index:index + chunk_size]
        try:
            rows = run_sparql(build_alias_query(chunk))
        except QueryTooBig:
            if len(chunk) == 1:
                conn.execute(
                    "UPDATE players SET aliases_fetched = 1 WHERE player_id = ?",
                    (qid_to_id[chunk[0]],),
                )
                conn.commit()
                index += 1
                continue
            chunk_size = max(1, len(chunk) // 2)
            print(f"    chunk too big, dropping to {chunk_size}")
            continue
        except KeyboardInterrupt:
            conn.commit()
            print("\n  interrupted — progress saved, re-run step 3 to continue.")
            raise

        for row in rows:
            qid = qid_from_uri(value(row, "player"))
            player_id = qid_to_id.get(qid)
            alias = value(row, "alias")
            if player_id is None or not alias:
                continue
            # Too short to be a safe match — a two-letter "alias" would make
            # nonsense input count as a correct answer.
            if len(normalize_name(alias)) < 3:
                continue
            db.add_player_alias(conn, player_id, alias)
            added += 1

        # Mark this chunk done and commit, so an interrupt costs one chunk
        # rather than the whole step.
        conn.executemany(
            "UPDATE players SET aliases_fetched = 1 WHERE player_id = ?",
            [(qid_to_id[q],) for q in chunk],
        )
        conn.commit()

        index += len(chunk)
        if index % 2500 < chunk_size:
            print(f"    {index:,}/{len(qids):,} players  ({added:,} aliases so far)")

    return added


def main() -> int:
    conn = db.connect()

    if not conn.execute("SELECT COUNT(*) AS n FROM clubs").fetchone()["n"]:
        print("No clubs in the database. Run scrape_clubs.py first.")
        conn.close()
        return 1

    updated = enrich_trophies(conn)
    print(f"  trophy counts set for {updated} clubs")

    sitelinks = enrich_sitelinks(conn)
    print(f"  Wikipedia language coverage set for {sitelinks} clubs")

    with_seasons = compute_top_division_seasons(conn)
    print(f"  top-division season counts set for {with_seasons} clubs")

    # Name repair runs BEFORE the alias fetch, so a repaired player gets his
    # real alternate names in the same pass rather than needing another run.
    repaired = repair_missing_labels(conn)
    if repaired:
        print(f"  recovered names for {repaired:,} players")

    nationalities = enrich_nationalities(conn)
    print(f"  nationality set for {nationalities:,} players")

    aliases = enrich_player_aliases(conn)
    total_aliases = conn.execute("SELECT COUNT(*) AS n FROM player_aliases").fetchone()["n"]
    print(f"  {aliases:,} alternate names fetched ({total_aliases:,} aliases stored in total)")

    db.refresh_counters(conn)
    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
