"""
Central configuration for the 321 Football Challenge database pipeline.

Everything tunable lives here so you never have to hunt through the scrapers
to change a rule.
"""

import os

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(BASE_DIR, "321_football.db")
SCHEMA_PATH = os.path.join(BASE_DIR, "schema.sql")
RESOLVED_LEAGUES_PATH = os.path.join(BASE_DIR, "leagues_resolved.json")
CACHE_DIR = os.path.join(BASE_DIR, ".sparql_cache")

# ---------------------------------------------------------------------------
# Wikidata
# ---------------------------------------------------------------------------
WIKIDATA_SPARQL_ENDPOINT = "https://query.wikidata.org/sparql"
WIKIDATA_API_ENDPOINT = "https://www.wikidata.org/w/api.php"

# WDQS asks that every client identify itself with a real contact address.
# Anonymous/spoofed agents get blocked. Change the email if you prefer.
USER_AGENT = "321FootballChallenge/1.0 (https://github.com/yourname/321-football; yamanturan6@gmail.com) python-requests"

# Politeness + resilience. WDQS enforces a 60s query timeout and throttles
# heavy clients; these defaults keep us comfortably inside its limits.
REQUEST_TIMEOUT_SECONDS = 180
PAUSE_BETWEEN_QUERIES_SECONDS = 1.2
MAX_RETRIES = 5
RETRY_BACKOFF_BASE_SECONDS = 4  # 4, 8, 16, 32, 64

# How many clubs to ask about in a single SPARQL query. Larger = fewer round
# trips but bigger responses, and WDQS will sometimes cut off a large response
# mid-transfer. The client halves the chunk and retries automatically when
# that happens, so this is only a starting point — 10 keeps typical responses
# comfortably under the size where truncation starts showing up.
CLUB_CHUNK_SIZE = 10

# Cache raw SPARQL responses on disk. Makes re-runs nearly instant and means
# a crash halfway through doesn't cost you the queries already paid for.
ENABLE_SPARQL_CACHE = True
CACHE_TTL_DAYS = 30

# ---------------------------------------------------------------------------
# Data rules  (these encode the gameplay decisions)
# ---------------------------------------------------------------------------

# The era cutoff. See INCLUDE_SPELL_RULE below for exactly how it's applied.
CUTOFF_YEAR = 1990

# How the cutoff is applied to a player's spell at a club:
#
#   "overlaps"  -> keep the spell if the player was at the club at ANY point
#                  from CUTOFF_YEAR onward. A 1988-1992 spell is KEPT (he was
#                  there in 1990, 1991, 1992). A spell ending 1985 is dropped.
#
#   "starts_after" -> keep only spells that STARTED in CUTOFF_YEAR or later.
#                  A 1988-1992 spell is DROPPED.
#
# "overlaps" is the default because it matches "there is no strict edge" and
# it matches how a player actually feels to a fan: someone at Inter in 1991
# is an Inter player, regardless of when he signed.
INCLUDE_SPELL_RULE = "overlaps"

# Wikidata's date coverage is patchy — plenty of real spells have no start or
# end date recorded at all. Dropping them silently loses a lot of legitimate
# data; keeping them blindly risks admitting pre-1990 spells.
#
#   True  -> keep undated spells, flagged date_confidence='unknown'.
#            verify.py reports how many there are per club so you can judge.
#   False -> drop them (and count them in the batch log).
KEEP_UNDATED_SPELLS = True

# Reserve / B / youth teams are excluded from the game entirely.
EXCLUDE_RESERVE_TEAMS = True

# A club whose scrape returns fewer than this many distinct players since the
# cutoff is almost certainly a data problem (wrong QID, thin Wikidata
# coverage) rather than reality. Flagged for review, not silently trusted.
MIN_EXPECTED_PLAYERS_PER_CLUB = 12

# A league returning fewer clubs than this is similarly suspicious.
MIN_EXPECTED_CLUBS_PER_LEAGUE = 8

# ---------------------------------------------------------------------------
# Practice mode difficulty bands
# ---------------------------------------------------------------------------
# fame_score is normalized 0-100 across all clubs in the database.
# A practice pair is drawn so that BOTH clubs fall inside the band.
DIFFICULTY_BANDS = {
    # Kept for reference/display only — difficulty is assigned by the ABSOLUTE
    # thresholds below, not by percentile rank. See why in the next block.
    "easy":   (85, 100),
    "medium": (50, 85),
    "hard":   (0, 50),
}

# Difficulty is assigned from a club's ABSOLUTE Wikipedia language count, not
# from its percentile rank among the clubs we happen to have scraped.
#
# Percentiles were the original approach and they were wrong here. The
# database contains 400+ near-anonymous lower-division clubs, which drags the
# distribution down so far that a merely well-documented side looks elite by
# comparison — Sheffield United landed in the top 15% and was rated "easy".
#
# Fame is an absolute property, not a relative one. A club known in 150
# languages is a household name whether or not we also scraped 400 clubs
# nobody has heard of, and one known in 40 is obscure regardless of company.
DIFFICULTY_SITELINK_THRESHOLDS = {
    "easy": 100,    # >= 100 languages: Real Madrid, Barça, Bayern, Milan, Liverpool
    "medium": 50,   # 50-99: Sheffield United, Burnley, Başakşehir, Rennes
    # below 50 = hard: Samsunspor, Gaziantep, lower-division sides everywhere
}

# A practice pair is only offered if it has at least this many mutual
# players — otherwise the question is unfair (or impossible).
MIN_MUTUAL_PLAYERS_EASY = 3
MIN_MUTUAL_PLAYERS_MEDIUM = 2
MIN_MUTUAL_PLAYERS_HARD = 1

# ---------------------------------------------------------------------------
# Answer matching
# ---------------------------------------------------------------------------
# A bare surname is accepted as an answer only if fewer than this many players
# share it. "Sneijder" identifies one man; "Silva" is shared by hundreds of
# Brazilian and Portuguese players, so typing it blind would score a point
# whenever ANY Silva happens to link the two clubs — knowledge of nothing.
#
# Above the threshold the player is asked for a first name too, rather than
# being told they're wrong. Set very high to disable the guard entirely.
MAX_PLAYERS_SHARING_SURNAME = 20
