"""
STEP 4 — compute fame scores and assign difficulty bands.

WHY WE BUILD OUR OWN RANKING
----------------------------
There is no authoritative public "most influential football clubs" list, and
the ones that exist (UEFA coefficients, IFFHS rankings) measure recent
sporting performance rather than how RECOGNISABLE a club is — which is what
actually makes a question easy or hard in this game. Bayer Leverkusen might
out-rank Nottingham Forest on coefficients while being no more famous to a
casual player.

So we compute a composite from three signals we already have:

    distinct_player_count  how much football history flows through the club
    trophy_count           prestige
    top_division_seasons   sustained presence at the top

Each is log-scaled (these distributions have brutal long tails — Real Madrid
has orders of magnitude more of everything than Başakşehir), z-scored, then
blended and converted to a PERCENTILE rank 0-100.

Percentile rather than min-max matters: with min-max, Real Madrid sits at 100
and 95% of clubs bunch below 10, so the difficulty bands would be useless.
With percentile, "easy = 75-100" genuinely means "the most famous quarter of
clubs", which is what you asked for.
"""

from __future__ import annotations

import math
import sys

import config
import db


def zscore(values: list[float]) -> list[float]:
    n = len(values)
    if n == 0:
        return []
    mean = sum(values) / n
    variance = sum((v - mean) ** 2 for v in values) / n
    stdev = math.sqrt(variance)
    if stdev == 0:
        return [0.0] * n
    return [(v - mean) / stdev for v in values]


def to_percentile(values: list[float]) -> list[float]:
    """
    Convert raw scores to 0-100 percentile ranks.
    Ties share the average rank, so a big block of identical scores doesn't
    get arbitrarily split across a difficulty boundary.
    """
    n = len(values)
    if n == 0:
        return []
    if n == 1:
        return [50.0]

    indexed = sorted(range(n), key=lambda i: values[i])
    percentiles = [0.0] * n

    i = 0
    while i < n:
        j = i
        while j + 1 < n and values[indexed[j + 1]] == values[indexed[i]]:
            j += 1
        # average rank position for this tie group
        avg_rank = (i + j) / 2
        pct = (avg_rank / (n - 1)) * 100
        for k in range(i, j + 1):
            percentiles[indexed[k]] = round(pct, 2)
        i = j + 1

    return percentiles


def band_for_sitelinks(sitelink_count: int) -> str:
    """
    Assign a difficulty band from the absolute language count.
    See the reasoning in config.DIFFICULTY_SITELINK_THRESHOLDS.
    """
    thresholds = config.DIFFICULTY_SITELINK_THRESHOLDS
    if sitelink_count >= thresholds["easy"]:
        return "easy"
    if sitelink_count >= thresholds["medium"]:
        return "medium"
    return "hard"


def band_for(score: float) -> str:
    """Percentile-based banding — kept only for the sitelink-less fallback."""
    for name, (low, high) in config.DIFFICULTY_BANDS.items():
        if low <= score <= high:
            return name
    return "medium"


def compute_club_fame(conn) -> int:
    db.ensure_column(conn, "clubs", "sitelink_count", "INTEGER NOT NULL DEFAULT 0")

    rows = conn.execute("""
        SELECT club_id, distinct_player_count, trophy_count,
               top_division_seasons, sitelink_count
        FROM clubs WHERE is_reserve_or_b_team = 0
    """).fetchall()

    if not rows:
        return 0

    have_sitelinks = sum(1 for r in rows if r["sitelink_count"] > 0)

    trophies = zscore([math.log1p(r["trophy_count"]) for r in rows])
    seasons = zscore([math.log1p(r["top_division_seasons"]) for r in rows])

    if have_sitelinks >= len(rows) * 0.5:
        # Preferred model. Sitelinks measure RECOGNITION, which is what makes a
        # question easy or hard.
        #
        # Trophies are deliberately EXCLUDED. Wikidata records them for only 54
        # of 865 clubs, so instead of being a mild prestige signal it acted as a
        # large arbitrary bonus for whichever 6% happened to have the data —
        # which is how Samsunspor (42 languages) outscored Sheffield United (68).
        # A signal present for 6% of rows is worse than no signal at all.
        #
        # Squad depth is excluded for the same class of reason: it measures how
        # thoroughly Wikidata documents a club, not how famous the club is.
        sitelinks = zscore([math.log1p(r["sitelink_count"]) for r in rows])
        raw = [
            0.75 * sitelinks[i] + 0.25 * seasons[i]
            for i in range(len(rows))
        ]
    else:
        # Fallback for a database enriched before sitelinks existed. Noticeably
        # worse — squad depth is a coverage artefact, not fame — so say so
        # rather than quietly producing a bad difficulty ranking.
        print("  WARNING: sitelink counts are missing, falling back to squad depth.")
        print("           Difficulty bands will be unreliable. Re-run step 3 to fix.")
        players = zscore([math.log1p(r["distinct_player_count"]) for r in rows])
        raw = [
            0.45 * players[i] + 0.35 * trophies[i] + 0.20 * seasons[i]
            for i in range(len(rows))
        ]

    scores = to_percentile(raw)

    # fame_score stays a percentile — it's the right shape for ordering search
    # results and for scoring players. The BAND, though, comes from the
    # absolute language count.
    use_absolute = have_sitelinks >= len(rows) * 0.5
    conn.executemany(
        "UPDATE clubs SET fame_score = ?, difficulty_band = ? WHERE club_id = ?",
        [(
            scores[i],
            band_for_sitelinks(rows[i]["sitelink_count"]) if use_absolute
            else band_for(scores[i]),
            rows[i]["club_id"],
        ) for i in range(len(rows))],
    )
    conn.commit()
    return len(rows)


def compute_player_fame(conn) -> int:
    """
    A player's fame leads with HIS OWN recognition: the number of Wikipedia
    languages with a page about him (players.sitelink_count, fetched by
    enrich_players.py) - the same signal the clubs use.

    Until 6 Oct 2026 this was the clubs alone (0.6 x best club + 0.4 x average
    club), so anyone with two famous clubs scored ~99: a 1910s Real Madrid
    amateur level with Zidane, Bertram Goode top of Villa x Liverpool. The
    club signal stays at 30% so that, among players nobody wrote about, the
    one who played for bigger clubs still ranks first.
    """
    db.ensure_column(conn, "players", "sitelink_count", "INTEGER NOT NULL DEFAULT 0")
    rows = conn.execute("""
        SELECT p.player_id,
               p.sitelink_count,
               MAX(c.fame_score) AS max_fame,
               AVG(c.fame_score) AS avg_fame
        FROM players p
        JOIN player_club_spells s ON s.player_id = p.player_id
        JOIN clubs c              ON c.club_id  = s.club_id
        WHERE c.is_reserve_or_b_team = 0
        GROUP BY p.player_id
    """).fetchall()

    if not rows:
        return 0

    own = zscore([math.log1p(r["sitelink_count"] or 0) for r in rows])
    club = zscore([0.6 * (r["max_fame"] or 0) + 0.4 * (r["avg_fame"] or 0) for r in rows])
    raw = [0.7 * own[i] + 0.3 * club[i] for i in range(len(rows))]
    scores = to_percentile(raw)

    conn.executemany(
        "UPDATE players SET fame_score = ? WHERE player_id = ?",
        [(scores[i], rows[i]["player_id"]) for i in range(len(rows))],
    )
    conn.commit()
    return len(rows)


def report(conn) -> None:
    print("\nMost famous clubs (should look like the household names):")
    for row in conn.execute("""
        SELECT canonical_name, fame_score, difficulty_band, sitelink_count, trophy_count
        FROM clubs WHERE is_reserve_or_b_team = 0
        ORDER BY fame_score DESC LIMIT 15
    """):
        print(f"   {row['fame_score']:6.2f}  {row['difficulty_band']:<7} "
              f"{row['canonical_name']:<32} "
              f"({row['sitelink_count']} languages, {row['trophy_count']} trophies)")

    print("\nLeast famous clubs (should look obscure — these drive Hard mode):")
    for row in conn.execute("""
        SELECT canonical_name, fame_score, difficulty_band, sitelink_count, distinct_player_count
        FROM clubs WHERE is_reserve_or_b_team = 0 AND distinct_player_count > 0
        ORDER BY fame_score ASC LIMIT 10
    """):
        print(f"   {row['fame_score']:6.2f}  {row['difficulty_band']:<7} "
              f"{row['canonical_name']:<32} ({row['sitelink_count']} languages)")

    print("\nSpot check — these should read as easy / medium / hard in that order:")
    for name in ("Real Madrid", "Liverpool", "Sheffield United", "Burnley",
                 "Başakşehir", "Samsunspor", "Hibernian"):
        row = conn.execute("""
            SELECT canonical_name, fame_score, difficulty_band, sitelink_count
            FROM clubs WHERE normalized_name LIKE ? AND is_reserve_or_b_team = 0
            ORDER BY sitelink_count DESC LIMIT 1
        """, (f"%{name.lower().replace('ş', 's').replace('ı', 'i').replace('ğ', 'g')}%",)).fetchone()
        if row:
            print(f"   {row['fame_score']:6.2f}  {row['difficulty_band']:<7} "
                  f"{row['canonical_name']:<32} ({row['sitelink_count']} languages)")

    print("\nBand distribution:")
    for row in conn.execute("""
        SELECT difficulty_band, COUNT(*) AS n FROM clubs
        WHERE is_reserve_or_b_team = 0 GROUP BY difficulty_band ORDER BY n DESC
    """):
        print(f"   {str(row['difficulty_band']):<8} {row['n']} clubs")


def main() -> int:
    conn = db.connect()
    db.refresh_counters(conn)

    clubs = compute_club_fame(conn)
    print(f"fame_score computed for {clubs} clubs")

    players = compute_player_fame(conn)
    print(f"fame_score computed for {players} players")

    if clubs:
        report(conn)

    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
