-- =========================================================================
-- 321 Football Challenge — database schema (SQLite)
--
-- Design goal: answer "which player played for BOTH club A and club B?" in
-- milliseconds on a phone, while keeping every fact traceable back to a
-- Wikidata statement so a single wrong row can be re-verified or re-scraped
-- without rebuilding everything.
-- =========================================================================

PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;

-- -------------------------------------------------------------------------
-- LEAGUES
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS leagues (
    league_id      INTEGER PRIMARY KEY AUTOINCREMENT,
    key            TEXT NOT NULL UNIQUE,      -- 'eng_pl', matches leagues.py
    wikidata_qid   TEXT NOT NULL UNIQUE,
    name           TEXT NOT NULL,
    country        TEXT NOT NULL,
    country_qid    TEXT,
    tier           INTEGER NOT NULL,
    region         TEXT,
    club_count     INTEGER NOT NULL DEFAULT 0,
    resolved_at    TEXT NOT NULL DEFAULT (datetime('now'))
);

-- -------------------------------------------------------------------------
-- CLUBS
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS clubs (
    club_id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    wikidata_qid             TEXT NOT NULL UNIQUE,
    canonical_name           TEXT NOT NULL,   -- the ONE display name, e.g. "Inter Milan"
    normalized_name          TEXT NOT NULL,   -- accent/case-folded, for search
    country                  TEXT,
    founded_year             INTEGER,

    is_reserve_or_b_team     INTEGER NOT NULL DEFAULT 0,
    reserve_detection_method TEXT,            -- 'part_of' | 'label_hint' | NULL — auditable

    -- Fame inputs (see compute_fame_scores.py)
    trophy_count             INTEGER NOT NULL DEFAULT 0,
    top_division_seasons     INTEGER NOT NULL DEFAULT 0,
    distinct_player_count    INTEGER NOT NULL DEFAULT 0,
    -- How many language Wikipedias have an article about this club. The
    -- primary fame signal: it measures recognition, whereas player count only
    -- measures how thoroughly Wikidata documents the club.
    sitelink_count           INTEGER NOT NULL DEFAULT 0,
    fame_score               REAL NOT NULL DEFAULT 0,   -- normalized 0-100
    difficulty_band          TEXT,                       -- 'easy' | 'medium' | 'hard'

    crest_asset_url          TEXT,

    -- Resumability: the orchestrator skips clubs already marked 'done'
    scrape_status            TEXT NOT NULL DEFAULT 'pending'
                             CHECK (scrape_status IN ('pending','done','failed','needs_review')),
    scraped_at               TEXT,

    created_at               TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at               TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_clubs_fame        ON clubs(fame_score);
CREATE INDEX IF NOT EXISTS idx_clubs_band        ON clubs(difficulty_band);
CREATE INDEX IF NOT EXISTS idx_clubs_status      ON clubs(scrape_status);
CREATE INDEX IF NOT EXISTS idx_clubs_normalized  ON clubs(normalized_name);

-- Which leagues a club has appeared in since the cutoff. A club can appear in
-- several (promoted/relegated between Premier League and Championship).
CREATE TABLE IF NOT EXISTS club_leagues (
    club_id      INTEGER NOT NULL REFERENCES clubs(club_id) ON DELETE CASCADE,
    league_id    INTEGER NOT NULL REFERENCES leagues(league_id) ON DELETE CASCADE,
    first_season INTEGER,
    last_season  INTEGER,
    PRIMARY KEY (club_id, league_id)
);

-- Former names / alternate spellings, all resolving to one canonical club.
-- ("Internazionale" -> Inter Milan, per your rule that renames are irrelevant.)
CREATE TABLE IF NOT EXISTS club_aliases (
    alias_id        INTEGER PRIMARY KEY AUTOINCREMENT,
    club_id         INTEGER NOT NULL REFERENCES clubs(club_id) ON DELETE CASCADE,
    alias_name      TEXT NOT NULL,
    normalized_alias TEXT NOT NULL,
    UNIQUE (club_id, alias_name)
);
CREATE INDEX IF NOT EXISTS idx_club_aliases_norm ON club_aliases(normalized_alias);

-- -------------------------------------------------------------------------
-- PLAYERS
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS players (
    player_id       INTEGER PRIMARY KEY AUTOINCREMENT,
    wikidata_qid    TEXT NOT NULL UNIQUE,
    full_name       TEXT NOT NULL,
    display_name    TEXT NOT NULL,
    normalized_name TEXT NOT NULL,   -- accent/case-folded — what typed answers match against
    nationality     TEXT,            -- per spec: nationality only, no other biographical data
    club_count      INTEGER NOT NULL DEFAULT 0,
    -- Marks that this player's real Wikidata alternate names have been
    -- fetched, so the enrichment step can resume instead of restarting.
    aliases_fetched INTEGER NOT NULL DEFAULT 0,
    -- Set when Wikidata's label service returned a Q-number instead of a
    -- name. The player and his spells are real; only the name lookup failed,
    -- and the enrichment step repairs it via rdfs:label.
    needs_label     INTEGER NOT NULL DEFAULT 0,
    fame_score      REAL NOT NULL DEFAULT 0,
    created_at      TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_players_normalized ON players(normalized_name);
CREATE INDEX IF NOT EXISTS idx_players_fame       ON players(fame_score);

CREATE TABLE IF NOT EXISTS player_aliases (
    alias_id         INTEGER PRIMARY KEY AUTOINCREMENT,
    player_id        INTEGER NOT NULL REFERENCES players(player_id) ON DELETE CASCADE,
    alias_name       TEXT NOT NULL,
    normalized_alias TEXT NOT NULL,
    UNIQUE (player_id, alias_name)
);
CREATE INDEX IF NOT EXISTS idx_player_aliases_norm ON player_aliases(normalized_alias);

-- -------------------------------------------------------------------------
-- PLAYER <-> CLUB SPELLS   (the table the whole game runs on)
-- -------------------------------------------------------------------------
-- One row per stint. Loans are NOT distinguished from permanent moves, per
-- your rule that every official appearance counts. A player can legitimately
-- have several rows at one club (left and returned) — matching is done on
-- DISTINCT (player_id, club_id) so that's harmless.
CREATE TABLE IF NOT EXISTS player_club_spells (
    spell_id            INTEGER PRIMARY KEY AUTOINCREMENT,
    player_id           INTEGER NOT NULL REFERENCES players(player_id) ON DELETE CASCADE,
    club_id             INTEGER NOT NULL REFERENCES clubs(club_id) ON DELETE CASCADE,
    start_year          INTEGER,
    end_year            INTEGER,          -- NULL = still at the club (current club counts, per spec)

    -- 'exact'   : both dates known
    -- 'partial' : one date known
    -- 'unknown' : neither known — kept only if KEEP_UNDATED_SPELLS is on,
    --             and reported by verify.py so you can judge the risk
    date_confidence     TEXT NOT NULL DEFAULT 'exact'
                        CHECK (date_confidence IN ('exact','partial','unknown')),

    source              TEXT NOT NULL DEFAULT 'wikidata',
    source_statement_id TEXT,             -- Wikidata statement GUID, for re-verification
    scraped_at          TEXT NOT NULL DEFAULT (datetime('now'))
);

-- THE performance-critical index. Given two club_ids we need every player_id
-- under both; a covering index on (club_id, player_id) lets both sides of the
-- INTERSECT run as pure index scans with no table lookups.
CREATE INDEX IF NOT EXISTS idx_spells_club_player ON player_club_spells(club_id, player_id);
CREATE INDEX IF NOT EXISTS idx_spells_player_club ON player_club_spells(player_id, club_id);

-- Stops a re-run from duplicating rows. COALESCE because NULL != NULL in SQL,
-- which would otherwise let undated spells duplicate freely.
CREATE UNIQUE INDEX IF NOT EXISTS uq_spell_identity ON player_club_spells(
    player_id, club_id, COALESCE(start_year, -1), COALESCE(end_year, -1)
);

-- -------------------------------------------------------------------------
-- PRACTICE PAIRS  (precomputed, so Practice mode is instant AND always fair)
-- -------------------------------------------------------------------------
-- Every row is a club pair that is GUARANTEED to have at least one mutual
-- player. Without this, Practice mode could serve an unanswerable question.
CREATE TABLE IF NOT EXISTS practice_pairs (
    pair_id         INTEGER PRIMARY KEY AUTOINCREMENT,
    club_a_id       INTEGER NOT NULL REFERENCES clubs(club_id) ON DELETE CASCADE,
    club_b_id       INTEGER NOT NULL REFERENCES clubs(club_id) ON DELETE CASCADE,
    difficulty      TEXT NOT NULL CHECK (difficulty IN ('easy','medium','hard')),
    mutual_count    INTEGER NOT NULL,
    -- lowest fame_score among the mutual players: a pair whose only shared
    -- player is obscure is harder than the club fame alone suggests
    min_answer_fame REAL,
    generated_at    TEXT NOT NULL DEFAULT (datetime('now')),
    CHECK (club_a_id < club_b_id)   -- canonical ordering, prevents A/B + B/A duplicates
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_practice_pair ON practice_pairs(club_a_id, club_b_id);
CREATE INDEX IF NOT EXISTS idx_practice_difficulty ON practice_pairs(difficulty);

-- -------------------------------------------------------------------------
-- SCRAPE PROVENANCE  (this is what makes "double-check every batch" real)
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS scrape_batches (
    batch_id               INTEGER PRIMARY KEY AUTOINCREMENT,
    target_type            TEXT NOT NULL CHECK (target_type IN ('league','club_chunk','enrichment')),
    target_qid             TEXT,
    target_label           TEXT,
    clubs_found            INTEGER NOT NULL DEFAULT 0,
    players_found          INTEGER NOT NULL DEFAULT 0,
    spells_found           INTEGER NOT NULL DEFAULT 0,
    spells_inserted        INTEGER NOT NULL DEFAULT 0,
    spells_skipped_precutoff INTEGER NOT NULL DEFAULT 0,
    spells_skipped_undated INTEGER NOT NULL DEFAULT 0,
    clubs_skipped_reserve  INTEGER NOT NULL DEFAULT 0,
    parse_errors           INTEGER NOT NULL DEFAULT 0,
    flagged_for_review     INTEGER NOT NULL DEFAULT 0,
    review_notes           TEXT,
    started_at             TEXT NOT NULL,
    finished_at            TEXT,
    status                 TEXT NOT NULL DEFAULT 'running'
                           CHECK (status IN ('running','success','failed','needs_review'))
);

CREATE INDEX IF NOT EXISTS idx_batches_status ON scrape_batches(status);

-- =========================================================================
-- REFERENCE: the query this whole schema exists to serve
-- =========================================================================
-- Mutual players between two clubs:
--
--   SELECT p.player_id, p.display_name
--   FROM players p
--   WHERE p.player_id IN (
--       SELECT player_id FROM player_club_spells WHERE club_id = :a
--       INTERSECT
--       SELECT player_id FROM player_club_spells WHERE club_id = :b
--   );
--
-- Validating one typed answer (the in-match hot path) — resolve the typed
-- string to candidate player_ids via normalized_name / aliases first, then:
--
--   SELECT 1 FROM player_club_spells WHERE player_id = :p AND club_id = :a
--   INTERSECT
--   SELECT 1 FROM player_club_spells WHERE player_id = :p AND club_id = :b;
