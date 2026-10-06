import 'package:sqflite/sqflite.dart';

import '../models/models.dart';
import 'name_normalizer.dart';

/// Dart port of `game_queries.py`. `verify.py` tests against that module, so
/// if this matches it, it is correct. Keep the two in step.
class GameQueries {
  GameQueries(this._db);

  final Database _db;

  /// Mirrors `config.MAX_PLAYERS_SHARING_SURNAME`.
  static const maxPlayersSharingSurname = 20;

  // -----------------------------------------------------------------------
  // Team search (pick phase)
  // -----------------------------------------------------------------------
  /// Shortest prefix that produces team suggestions.
  ///
  /// Two, unlike [minPrefix] for players — and that is not an oversight. The
  /// player search scans 198,626 alias rows and had to be pushed to three
  /// characters; there are only 821 clubs, and this whole query measures
  /// 3-5 ms on the shipped database even at ONE character. The Figma typing
  /// frame shows team suggestions at two characters ("BA"), and here the app
  /// can actually match the design.
  static const clubMinPrefix = 2;

  /// The team picker.
  ///
  /// Three things here are load bearing:
  ///
  /// **Word-start ranking.** The previous version gave the prefix bonus only
  /// when the CANONICAL name started with the query, so typing "ba" returned
  /// Bayer Leverkusen, Barnsley and Balıkesirspor before FC Barcelona — which
  /// is stored as "FC Barcelona" and therefore scored as a mere substring
  /// match despite being the most famous club in the database. Matching at
  /// any word start fixes it ("ba" now gives Barcelona, Bayern, Bayer,
  /// Espanyol) and is the same rule the player suggestion highlighter uses.
  ///
  /// **Clubs with no spells are excluded.** 61 clubs in the shipped database
  /// have zero player spells, and they are not all the harmless defunct sides
  /// the notes claim: `FC Bayern München` (a duplicate of `FC Bayern Munich`,
  /// which holds all 497 players), `BV Borussia 09 Dortmund`, `FC Schalke 04`
  /// and `DSC Arminia Bielefeld` are all in the list. Practice never hit this
  /// because `practice_pairs` is pre-validated, but in PvP the player picks
  /// the club, so picking the empty Bayern would make every round unwinnable.
  /// A club that can never produce an answer must not be pickable. The
  /// duplicates themselves still want a proper merge pass upstream.
  ///
  /// **Two clubs are named after their own Wikidata ID** (`Q582342`,
  /// `Q97905955`) because `fix_names.py` never resolved a label for them.
  /// `canonical_name = wikidata_qid` catches exactly those two and nothing
  /// else.
  ///
  /// The LIMIT is applied in a subquery so the two league lookups run only
  /// for the handful of rows that survive it, not for every matching club.
  Future<List<Club>> searchClubs(String query, {int limit = 4}) async {
    final normalized = normalizeName(query);
    if (normalized.length < clubMinPrefix) return const [];

    final contains = '%$normalized%';
    final atStart = '$normalized%';
    final afterSpace = '% $normalized%';
    final afterHyphen = '%-$normalized%';

    final rows = await _db.rawQuery('''
      SELECT t.club_id, t.canonical_name, t.country, t.fame_score,
             t.crest_asset_url,
             (SELECT l.name FROM club_leagues cl
                JOIN leagues l ON l.league_id = cl.league_id
               WHERE cl.club_id = t.club_id
               ORDER BY cl.last_season DESC, l.tier ASC LIMIT 1) AS league_name,
             (SELECT l.country FROM club_leagues cl
                JOIN leagues l ON l.league_id = cl.league_id
               WHERE cl.club_id = t.club_id
               ORDER BY cl.last_season DESC, l.tier ASC LIMIT 1) AS league_country
      FROM (
        SELECT c.club_id, c.canonical_name, c.country, c.fame_score,
               c.crest_asset_url,
               MIN(CASE WHEN c.normalized_name LIKE ?
                          OR c.normalized_name LIKE ?
                          OR c.normalized_name LIKE ?
                          OR a.normalized_alias LIKE ?
                          OR a.normalized_alias LIKE ?
                          OR a.normalized_alias LIKE ?
                        THEN 0 ELSE 1 END) AS word_start
        FROM clubs c
        LEFT JOIN club_aliases a ON a.club_id = c.club_id
        WHERE c.is_reserve_or_b_team = 0
          AND c.canonical_name <> c.wikidata_qid
          AND (c.normalized_name LIKE ? OR a.normalized_alias LIKE ?)
          AND EXISTS (SELECT 1 FROM player_club_spells s
                       WHERE s.club_id = c.club_id)
        GROUP BY c.club_id
        ORDER BY word_start ASC, c.fame_score DESC
        LIMIT ?
      ) t
    ''', [
      atStart, afterSpace, afterHyphen,
      atStart, afterSpace, afterHyphen,
      contains, contains,
      limit,
    ]);

    return rows.map(Club.fromRow).toList();
  }

  /// A club to pick on the player's behalf when the 15 seconds run out.
  ///
  /// Restricted to well-known clubs that actually have players, because a
  /// forfeited pick should not also hand the opponent an unanswerable round.
  /// Excluding the club the opponent already took avoids the degenerate
  /// Barcelona-versus-Barcelona round, where every player in the squad is a
  /// correct answer.
  Future<Club?> randomPickableClub({int? excludeClubId}) async {
    final rows = await _db.rawQuery('''
      SELECT c.club_id, c.canonical_name, c.country, c.fame_score,
             c.crest_asset_url,
             (SELECT l.name FROM club_leagues cl
                JOIN leagues l ON l.league_id = cl.league_id
               WHERE cl.club_id = c.club_id
               ORDER BY cl.last_season DESC, l.tier ASC LIMIT 1) AS league_name,
             (SELECT l.country FROM club_leagues cl
                JOIN leagues l ON l.league_id = cl.league_id
               WHERE cl.club_id = c.club_id
               ORDER BY cl.last_season DESC, l.tier ASC LIMIT 1) AS league_country
      FROM clubs c
      WHERE c.is_reserve_or_b_team = 0
        AND c.canonical_name <> c.wikidata_qid
        AND c.fame_score > 85
        AND (? IS NULL OR c.club_id <> ?)
        AND EXISTS (SELECT 1 FROM player_club_spells s
                     WHERE s.club_id = c.club_id)
      ORDER BY RANDOM() LIMIT 1
    ''', [excludeClubId, excludeClubId]);
    if (rows.isEmpty) return null;
    return Club.fromRow(rows.first);
  }

  /// One club by id, with the same league sub-line [searchClubs] returns, so
  /// a club restored from a room record renders identically to one just
  /// picked from the list.
  Future<Club?> clubById(int clubId) async {
    final rows = await _db.rawQuery('''
      SELECT c.club_id, c.canonical_name, c.country, c.fame_score,
             c.crest_asset_url,
             (SELECT l.name FROM club_leagues cl
                JOIN leagues l ON l.league_id = cl.league_id
               WHERE cl.club_id = c.club_id
               ORDER BY cl.last_season DESC, l.tier ASC LIMIT 1) AS league_name,
             (SELECT l.country FROM club_leagues cl
                JOIN leagues l ON l.league_id = cl.league_id
               WHERE cl.club_id = c.club_id
               ORDER BY cl.last_season DESC, l.tier ASC LIMIT 1) AS league_country
      FROM clubs c WHERE c.club_id = ?
    ''', [clubId]);
    if (rows.isEmpty) return null;
    return Club.fromRow(rows.first);
  }

  // -----------------------------------------------------------------------
  // Player suggestions (display aid only)
  // -----------------------------------------------------------------------
  /// Exclusive upper bound for a prefix range: the prefix with its last code
  /// unit incremented, so `[prefix, successor)` is exactly the set of strings
  /// starting with `prefix`.
  static String _prefixSuccessor(String prefix) {
    final units = List<int>.from(prefix.codeUnits);
    units[units.length - 1] = units.last + 1;
    return String.fromCharCodes(units);
  }

  /// Prefix search for the suggestion panel above the keyboard.
  ///
  /// This is a DISPLAY AID and nothing more. It must never be allowed to
  /// soften [validateAnswer], which stays exact-match: if the suggestion list
  /// were treated as the answer key, a player could tap a name that does not
  /// actually link the two clubs and expect a point.
  ///
  /// The bounds are a RANGE COMPARISON, not `LIKE 'x%'`, and that is load
  /// bearing. SQLite's LIKE is case-insensitive by default, so it cannot use
  /// a BINARY-collated index — `LIKE` here made this a full scan of all
  /// 198,626 rows of player_aliases, about 31 ms on a laptop and far worse on
  /// a phone, fired on EVERY keystroke. That was enough to hang the app.
  /// Both normalized columns are already lowercase, so the range form is
  /// exactly equivalent and uses idx_players_normalized /
  /// idx_player_aliases_norm: 0.3 ms, a hundredfold better.
  ///
  /// If you ever reintroduce LIKE here, check `EXPLAIN QUERY PLAN` first —
  /// tools/explain.py does it.
  /// Shortest prefix that will produce suggestions.
  ///
  /// Measured on the shipped database (tools/explain.py), counting the
  /// candidate ids the IN(...) set has to materialise and sort by fame before
  /// LIMIT 4 applies:
  ///
  ///     "a"    8,126 candidates   187 ms
  ///     "ro"   1,899 candidates    52 ms
  ///     "ron"    112 candidates    12 ms
  ///     "sne"      9 candidates   0.2 ms
  ///
  /// Those are laptop numbers; a phone is several times slower. At two
  /// characters the panel was still empty a full second after typing, and the
  /// four names it eventually showed were the four most famous of ~1,900 —
  /// not predictive of anything the player was typing toward. Three
  /// characters is both fast and actually useful.
  ///
  /// The Figma typing frame shows suggestions at two characters ("BA"). If
  /// that matters more than the latency, set this to 2 — but fix the query
  /// first (fame is not available inside the alias branch, so the whole
  /// candidate set gets sorted; denormalising fame_score into player_aliases
  /// would let the LIMIT push down).
  static const minPrefix = 3;

  Future<List<Player>> suggestPlayers(String typed, {int limit = 4}) async {
    final lo = normalizeName(typed);
    if (lo.length < minPrefix) return const [];
    final hi = _prefixSuccessor(lo);

    // first_year / last_year feed the suggestion sub-line. They are
    // correlated subqueries rather than a join so they run only for the four
    // rows that survive the LIMIT, and both hit idx_spells_player_club.
    final rows = await _db.rawQuery('''
      SELECT p.player_id, p.display_name, p.nationality, p.fame_score,
             (SELECT MIN(s.start_year) FROM player_club_spells s
               WHERE s.player_id = p.player_id) AS first_year,
             (SELECT MAX(s.end_year) FROM player_club_spells s
               WHERE s.player_id = p.player_id) AS last_year
      FROM players p
      WHERE p.player_id IN (
          SELECT player_id FROM players
            WHERE normalized_name >= ? AND normalized_name < ?
          UNION
          SELECT player_id FROM player_aliases
            WHERE normalized_alias >= ? AND normalized_alias < ?
      )
      ORDER BY p.fame_score DESC
      LIMIT ?
    ''', [lo, hi, lo, hi, limit]);

    return rows.map(Player.fromRow).toList();
  }

  // -----------------------------------------------------------------------
  // Mutual players
  // -----------------------------------------------------------------------
  /// Every player who played for both clubs. This is the answer key.
  Future<List<Player>> getMutualPlayers(int clubAId, int clubBId) async {
    final rows = await _db.rawQuery('''
      SELECT p.player_id, p.display_name, p.nationality, p.fame_score
      FROM players p
      WHERE p.player_id IN (
          SELECT player_id FROM player_club_spells WHERE club_id = ?
          INTERSECT
          SELECT player_id FROM player_club_spells WHERE club_id = ?
      )
      ORDER BY p.fame_score DESC
    ''', [clubAId, clubBId]);

    return rows.map(Player.fromRow).toList();
  }

  /// A mutual player's spells at the two clubs of a pair, in career order,
  /// for the "Takım 1 (2009–13) → Takım 2 (2013–17)" line on GOOOL, the
  /// practice Doğru popup and the answer list.
  ///
  /// The room row only carries the scorer's DISPLAY NAME, so the player is
  /// found among the pair's mutual players by that name (most famous first,
  /// should two share it).
  ///
  /// One entry per spell, NOT one per club: Steve Staunton went Liverpool →
  /// Villa → Liverpool → Villa, and collapsing each club to its earliest start
  /// and latest end printed "Liverpool (1986–2000) → Aston Villa (1991–2003)",
  /// which is a career he never had. Only back-to-back spells at the SAME club
  /// (a contract renewal split into two rows) are joined. An open end (still
  /// at the club) stays null.
  Future<List<({int clubId, int? from, int? to})>> mutualSpells(
    String displayName,
    int clubAId,
    int clubBId,
  ) async {
    final rows = await _db.rawQuery('''
      SELECT s.club_id, s.start_year AS from_year, s.end_year AS to_year
      FROM player_club_spells s
      WHERE s.club_id IN (?, ?)
        AND s.player_id = (
            SELECT p.player_id FROM players p
            WHERE p.display_name = ?
              AND p.player_id IN (
                  SELECT player_id FROM player_club_spells WHERE club_id = ?
                  INTERSECT
                  SELECT player_id FROM player_club_spells WHERE club_id = ?
              )
            ORDER BY p.fame_score DESC
            LIMIT 1
        )
      ORDER BY s.start_year IS NULL, s.start_year, s.end_year IS NULL, s.end_year
    ''', [clubAId, clubBId, displayName, clubAId, clubBId]);

    final spells = <({int clubId, int? from, int? to})>[];
    for (final r in rows) {
      final spell = (
        clubId: r['club_id'] as int,
        from: r['from_year'] as int?,
        to: r['to_year'] as int?,
      );
      final last = spells.isEmpty ? null : spells.last;
      if (last != null && last.clubId == spell.clubId) {
        // Back-to-back at the same club: one spell, the later end wins
        // (null = still there, which is the latest of all).
        final int? to = (last.to == null || spell.to == null)
            ? null
            : (spell.to! > last.to! ? spell.to : last.to);
        spells[spells.length - 1] = (clubId: last.clubId, from: last.from, to: to);
      } else {
        spells.add(spell);
      }
    }
    return spells;
  }

  Future<int> countMutualPlayers(int clubAId, int clubBId) async {
    final rows = await _db.rawQuery('''
      SELECT COUNT(*) AS n FROM (
          SELECT player_id FROM player_club_spells WHERE club_id = ?
          INTERSECT
          SELECT player_id FROM player_club_spells WHERE club_id = ?
      )
    ''', [clubAId, clubBId]);
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  // -----------------------------------------------------------------------
  // Answer validation (the hot path)
  // -----------------------------------------------------------------------
  Future<int> _countPlayersSharingName(String normalized) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(DISTINCT player_id) AS n FROM player_aliases '
      'WHERE normalized_alias = ?',
      [normalized],
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  /// Resolve a typed string to candidate players.
  ///
  /// Matching is EXACT, on either the full normalized name or a stored alias.
  /// There is deliberately no fuzzy matching: under a clock, a near-miss that
  /// silently counts as correct feels worse than a rejection, and it would
  /// let "ronaldo" claim a point meant for "ronaldinho".
  ///
  /// Multi-word input is taken at its word. Single-word input is where the
  /// exploit lives — every player stores his bare surname as an alias, so
  /// "Silva" alone would match hundreds and a blind guess would score whenever
  /// any one of them happened to link the clubs. A bare surname shared by more
  /// than [maxPlayersSharingSurname] players is refused, unless it is
  /// somebody's actual full name ("Ronaldinho", "Kaká"), which is definitive.
  Future<(List<int>, AnswerReason)> _candidatePlayerIds(String typed) async {
    final normalized = normalizeName(typed);
    if (normalized.length < 3) return (<int>[], AnswerReason.tooShort);

    final ids = <int>[];
    final seen = <int>{};

    void add(List<Map<String, Object?>> rows) {
      for (final row in rows) {
        final id = row['player_id'] as int;
        if (seen.add(id)) ids.add(id);
      }
    }

    // 1. The whole string IS somebody's name — definitive, never ambiguous.
    final exact = await _db.rawQuery(
      'SELECT player_id FROM players WHERE normalized_name = ?',
      [normalized],
    );
    add(exact);

    // 2. Alias match. Guard the single-word case against common surnames.
    if (exact.isEmpty && !normalized.contains(' ')) {
      final shared = await _countPlayersSharingName(normalized);
      if (shared > maxPlayersSharingSurname) {
        return (<int>[], AnswerReason.surnameTooCommon);
      }
    }

    add(await _db.rawQuery(
      'SELECT player_id FROM player_aliases WHERE normalized_alias = ?',
      [normalized],
    ));

    return (ids, ids.isEmpty ? AnswerReason.unknownPlayer : AnswerReason.correct);
  }

  /// Judge a typed answer against a pair of clubs.
  Future<AnswerResult> validateAnswer(
    String typed,
    int clubAId,
    int clubBId,
  ) async {
    final (candidates, reason) = await _candidatePlayerIds(typed);
    if (candidates.isEmpty) {
      return AnswerResult(correct: false, reason: reason);
    }

    final placeholders = List.filled(candidates.length, '?').join(',');
    final hit = await _db.rawQuery('''
      SELECT p.player_id, p.display_name, p.nationality, p.fame_score
      FROM players p
      WHERE p.player_id IN ($placeholders)
        AND p.player_id IN (
            SELECT player_id FROM player_club_spells WHERE club_id = ?
            INTERSECT
            SELECT player_id FROM player_club_spells WHERE club_id = ?
        )
      ORDER BY p.fame_score DESC
      LIMIT 1
    ''', [...candidates, clubAId, clubBId]);

    if (hit.isNotEmpty) {
      return AnswerResult(
        correct: true,
        reason: AnswerReason.correct,
        player: Player.fromRow(hit.first),
      );
    }

    // ORDER BY fame_score is deliberate and is a FIX over game_queries.py,
    // which takes LIMIT 1 with no ordering here. SQLite then returns an
    // arbitrary namesake: typing "messi" against Bayern x Napoli reported
    // "Georges Parfait Mbida Messi never played for both", which reads as a
    // bug to anyone who meant Lionel. Naming the most famous candidate is the
    // only sane reading of an ambiguous surname.
    //
    // This changes only which name is DISPLAYED on a rejection. Whether the
    // answer is accepted is decided by the query above, which is unchanged,
    // so parity with the Python reference on correctness still holds.
    final known = await _db.rawQuery(
      'SELECT player_id, display_name, nationality, fame_score FROM players '
      'WHERE player_id IN ($placeholders) ORDER BY fame_score DESC LIMIT 1',
      candidates,
    );

    return AnswerResult(
      correct: false,
      reason: AnswerReason.notAMutualPlayer,
      player: known.isEmpty ? null : Player.fromRow(known.first),
    );
  }

  // -----------------------------------------------------------------------
  // Practice mode
  // -----------------------------------------------------------------------
  /// Draw a random Practice question. Every row in `practice_pairs` is
  /// pre-validated, so this can never serve an impossible question.
  Future<PracticePair?> randomPracticePair(Difficulty difficulty) async {
    final rows = await _db.rawQuery('''
      SELECT pp.pair_id, pp.mutual_count,
             ca.club_id AS club_a_id, ca.canonical_name AS club_a_name,
             cb.club_id AS club_b_id, cb.canonical_name AS club_b_name
      FROM practice_pairs pp
      JOIN clubs ca ON ca.club_id = pp.club_a_id
      JOIN clubs cb ON cb.club_id = pp.club_b_id
      WHERE pp.difficulty = ?
      ORDER BY RANDOM() LIMIT 1
    ''', [difficulty.dbValue]);

    if (rows.isEmpty) return null;
    return PracticePair.fromRow(rows.first);
  }

  // -----------------------------------------------------------------------
  // PvP helper
  // -----------------------------------------------------------------------
  /// Call the moment both PvP players lock in their clubs, BEFORE the 3-2-1
  /// countdown finishes. If this comes back false the round has no valid
  /// answer, and the UI shows Tur Bitti rather than running a clock nobody
  /// can beat.
  Future<({bool playable, int mutualCount})> checkPairIsPlayable(
    int clubAId,
    int clubBId,
  ) async {
    final count = await countMutualPlayers(clubAId, clubBId);
    return (playable: count > 0, mutualCount: count);
  }
}
