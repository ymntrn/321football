"""
Database access helpers — connection setup, schema creation, and the upserts
the scrapers share.
"""

from __future__ import annotations

import os
import sqlite3
from datetime import datetime, timezone

import config
from names import normalize_name


def utcnow() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def connect(db_path: str | None = None) -> sqlite3.Connection:
    conn = sqlite3.connect(db_path or config.DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA synchronous = NORMAL")   # much faster bulk inserts, still crash-safe with WAL
    return conn


def init_schema(conn: sqlite3.Connection, schema_path: str | None = None) -> None:
    path = schema_path or config.SCHEMA_PATH
    with open(path, "r", encoding="utf-8") as fh:
        conn.executescript(fh.read())
    conn.commit()


def database_exists() -> bool:
    return os.path.exists(config.DB_PATH) and os.path.getsize(config.DB_PATH) > 0


def ensure_column(conn, table: str, column: str, definition: str) -> bool:
    """
    Add a column if it isn't there yet. Returns True if it was added.

    Lets the pipeline evolve without forcing a full rebuild — a 235,000-row
    scrape is far too expensive to throw away over a schema addition.
    """
    columns = {row["name"] for row in conn.execute(f"PRAGMA table_info({table})")}
    if column in columns:
        return False
    conn.execute(f"ALTER TABLE {table} ADD COLUMN {column} {definition}")
    conn.commit()
    return True


# -------------------------------------------------------------------------
# Upserts
# -------------------------------------------------------------------------
def upsert_league(conn, *, key: str, qid: str, name: str, country: str,
                  country_qid: str | None, tier: int, region: str | None) -> int:
    row = conn.execute("SELECT league_id FROM leagues WHERE key = ?", (key,)).fetchone()
    if row:
        conn.execute(
            """UPDATE leagues SET wikidata_qid = ?, name = ?, country = ?,
                      country_qid = ?, tier = ?, region = ? WHERE league_id = ?""",
            (qid, name, country, country_qid, tier, region, row["league_id"]),
        )
        return row["league_id"]
    cur = conn.execute(
        """INSERT INTO leagues (key, wikidata_qid, name, country, country_qid, tier, region)
           VALUES (?, ?, ?, ?, ?, ?, ?)""",
        (key, qid, name, country, country_qid, tier, region),
    )
    return cur.lastrowid


def upsert_club(conn, *, qid: str, name: str, country: str | None = None,
                founded_year: int | None = None, is_reserve: bool = False,
                reserve_method: str | None = None) -> int:
    row = conn.execute("SELECT club_id FROM clubs WHERE wikidata_qid = ?", (qid,)).fetchone()
    if row:
        # Fill in any detail we didn't have the first time we saw this club,
        # without clobbering good data with NULLs from a thinner query.
        conn.execute(
            """UPDATE clubs SET
                 country      = COALESCE(?, country),
                 founded_year = COALESCE(?, founded_year),
                 updated_at   = datetime('now')
               WHERE club_id = ?""",
            (country, founded_year, row["club_id"]),
        )
        return row["club_id"]

    cur = conn.execute(
        """INSERT INTO clubs
             (wikidata_qid, canonical_name, normalized_name, country, founded_year,
              is_reserve_or_b_team, reserve_detection_method)
           VALUES (?, ?, ?, ?, ?, ?, ?)""",
        (qid, name, normalize_name(name), country, founded_year,
         1 if is_reserve else 0, reserve_method),
    )
    return cur.lastrowid


def add_club_alias(conn, club_id: int, alias: str) -> None:
    if not alias:
        return
    conn.execute(
        """INSERT OR IGNORE INTO club_aliases (club_id, alias_name, normalized_alias)
           VALUES (?, ?, ?)""",
        (club_id, alias, normalize_name(alias)),
    )


def link_club_league(conn, club_id: int, league_id: int,
                     season_year: int | None) -> None:
    row = conn.execute(
        "SELECT first_season, last_season FROM club_leagues WHERE club_id = ? AND league_id = ?",
        (club_id, league_id),
    ).fetchone()

    if row is None:
        conn.execute(
            """INSERT INTO club_leagues (club_id, league_id, first_season, last_season)
               VALUES (?, ?, ?, ?)""",
            (club_id, league_id, season_year, season_year),
        )
        return

    if season_year is None:
        return
    first = min(x for x in [row["first_season"], season_year] if x is not None)
    last = max(x for x in [row["last_season"], season_year] if x is not None)
    conn.execute(
        "UPDATE club_leagues SET first_season = ?, last_season = ? WHERE club_id = ? AND league_id = ?",
        (first, last, club_id, league_id),
    )


def upsert_player(conn, *, qid: str, full_name: str,
                  nationality: str | None = None) -> int:
    row = conn.execute("SELECT player_id FROM players WHERE wikidata_qid = ?", (qid,)).fetchone()
    if row:
        if nationality:
            conn.execute(
                "UPDATE players SET nationality = COALESCE(nationality, ?), updated_at = datetime('now') WHERE player_id = ?",
                (nationality, row["player_id"]),
            )
        return row["player_id"]

    cur = conn.execute(
        """INSERT INTO players (wikidata_qid, full_name, display_name, normalized_name, nationality)
           VALUES (?, ?, ?, ?, ?)""",
        (qid, full_name, full_name, normalize_name(full_name), nationality),
    )
    return cur.lastrowid


def add_player_alias(conn, player_id: int, alias: str) -> None:
    if not alias or len(alias) < 3:
        return
    conn.execute(
        """INSERT OR IGNORE INTO player_aliases (player_id, alias_name, normalized_alias)
           VALUES (?, ?, ?)""",
        (player_id, alias, normalize_name(alias)),
    )


def insert_spell(conn, *, player_id: int, club_id: int,
                 start_year: int | None, end_year: int | None,
                 date_confidence: str, statement_id: str | None) -> bool:
    """Returns True if a new row was actually inserted."""
    cur = conn.execute(
        """INSERT OR IGNORE INTO player_club_spells
             (player_id, club_id, start_year, end_year, date_confidence, source_statement_id)
           VALUES (?, ?, ?, ?, ?, ?)""",
        (player_id, club_id, start_year, end_year, date_confidence, statement_id),
    )
    return cur.rowcount > 0


# -------------------------------------------------------------------------
# Batch logging
# -------------------------------------------------------------------------
def start_batch(conn, *, target_type: str, target_qid: str | None,
                target_label: str | None) -> int:
    cur = conn.execute(
        """INSERT INTO scrape_batches (target_type, target_qid, target_label, started_at)
           VALUES (?, ?, ?, ?)""",
        (target_type, target_qid, target_label, utcnow()),
    )
    conn.commit()
    return cur.lastrowid


def finish_batch(conn, batch_id: int, *, status: str, flagged: bool = False,
                 notes: str | None = None, **counters) -> None:
    allowed = {
        "clubs_found", "players_found", "spells_found", "spells_inserted",
        "spells_skipped_precutoff", "spells_skipped_undated",
        "clubs_skipped_reserve", "parse_errors",
    }
    sets, values = [], []
    for key, val in counters.items():
        if key in allowed:
            sets.append(f"{key} = ?")
            values.append(val)

    sets += ["finished_at = ?", "status = ?", "flagged_for_review = ?", "review_notes = ?"]
    values += [utcnow(), status, 1 if flagged else 0, notes, batch_id]

    conn.execute(f"UPDATE scrape_batches SET {', '.join(sets)} WHERE batch_id = ?", values)
    conn.commit()


# -------------------------------------------------------------------------
# Denormalized counter refresh
# -------------------------------------------------------------------------
def refresh_counters(conn) -> None:
    """Recompute the cached counts used for fame scoring and QA."""
    conn.execute("""
        UPDATE clubs SET distinct_player_count = (
            SELECT COUNT(DISTINCT player_id) FROM player_club_spells s WHERE s.club_id = clubs.club_id
        )
    """)
    conn.execute("""
        UPDATE players SET club_count = (
            SELECT COUNT(DISTINCT club_id) FROM player_club_spells s WHERE s.player_id = players.player_id
        )
    """)
    conn.execute("""
        UPDATE leagues SET club_count = (
            SELECT COUNT(*) FROM club_leagues cl WHERE cl.league_id = leagues.league_id
        )
    """)
    conn.commit()
