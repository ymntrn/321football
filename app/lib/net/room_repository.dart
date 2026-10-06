import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import '../models/room.dart';
import 'server_clock.dart';

/// Why joining a room failed, in terms the UI can put on screen.
enum JoinFailure {
  /// No room with that code. Almost always a typo.
  notFound,

  /// The room exists but the match has already started.
  inProgress,

  /// Two players are already in it.
  full,

  /// Could not reach Supabase at all.
  network,
}

class JoinException implements Exception {
  const JoinException(this.failure, [this.detail]);
  final JoinFailure failure;
  final String? detail;

  /// Turkish copy. Each case gets its own message — "kod yanlış" for a room
  /// that is merely full would send the player hunting for a typo that is not
  /// there.
  String get message {
    switch (failure) {
      case JoinFailure.notFound:
        return 'Böyle bir oda yok';
      case JoinFailure.inProgress:
        return 'Maç çoktan başladı';
      case JoinFailure.full:
        return 'Oda dolu';
      case JoinFailure.network:
        return 'Bağlantı kurulamadı';
    }
  }

  @override
  String toString() => 'JoinException($failure, $detail)';
}

/// Everything this app does to a room.
///
/// Phase transitions go through the RPCs in `003_match_flow.sql` rather than
/// plain updates, because each of them has to stamp a deadline with the
/// SERVER's clock. A player's own pick and answer are ordinary updates — they
/// carry no timestamp the other side has to agree with.
class RoomRepository {
  RoomRepository(this._client, this.clock);

  final SupabaseClient _client;
  final ServerClock clock;

  /// Realtime can drop a message, and a room whose updates stop arriving looks
  /// exactly like a frozen game. A slow poll alongside the subscription costs
  /// a couple of requests a second for the few minutes a match lasts and
  /// removes that whole class of failure. Updates that the poll and the
  /// subscription both deliver are de-duplicated by `updated_at`.
  static const _pollInterval = Duration(seconds: 2);

  Future<Room> create({
    required String playerId,
    required String name,
  }) async {
    final row = await _client.rpc('create_room', params: {
      'p_host_id': playerId,
      'p_host_name': name,
    });
    return Room.fromRow(Map<String, dynamic>.from(row as Map));
  }

  Future<Room> join({
    required String code,
    required String playerId,
    required String name,
  }) async {
    try {
      final row = await _client.rpc('join_room', params: {
        'p_code': code,
        'p_guest_id': playerId,
        'p_guest_name': name,
      });
      return Room.fromRow(Map<String, dynamic>.from(row as Map));
    } on PostgrestException catch (e) {
      final message = e.message;
      if (message.contains('room_not_found')) {
        throw const JoinException(JoinFailure.notFound);
      }
      if (message.contains('room_in_progress')) {
        throw const JoinException(JoinFailure.inProgress);
      }
      if (message.contains('room_full')) {
        throw const JoinException(JoinFailure.full);
      }
      throw JoinException(JoinFailure.network, message);
    } catch (e) {
      throw JoinException(JoinFailure.network, '$e');
    }
  }

  Future<Room?> fetch(String code) async {
    final row = await _client
        .from('rooms')
        .select()
        .eq('code', code)
        .maybeSingle();
    return row == null ? null : Room.fromRow(row);
  }

  /// The room as a live stream: the current row first, then every change.
  ///
  /// Cancelling the subscription tears down both the realtime channel and the
  /// poll.
  Stream<Room> watch(String code) {
    late final StreamController<Room> controller;
    RealtimeChannel? channel;
    Timer? poll;
    DateTime? lastSeen;

    void emit(Room room) {
      // Out-of-order delivery is possible when a poll response overtakes a
      // realtime message. updated_at is maintained by a trigger, so it is a
      // reliable ordering key; a stale row is simply dropped.
      if (lastSeen != null && !room.updatedAt.isAfter(lastSeen!)) return;
      lastSeen = room.updatedAt;
      if (!controller.isClosed) controller.add(room);
    }

    Future<void> start() async {
      try {
        final current = await fetch(code);
        if (current != null) emit(current);
      } catch (e, s) {
        if (!controller.isClosed) controller.addError(e, s);
      }

      channel = _client.channel('room-$code')
        ..onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'rooms',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'code',
            value: code,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            if (row.isEmpty) return;
            emit(Room.fromRow(Map<String, dynamic>.from(row)));
          },
        )
        ..subscribe();

      poll = Timer.periodic(_pollInterval, (_) async {
        try {
          final row = await fetch(code);
          if (row != null) emit(row);
        } catch (_) {
          // A failed poll is not worth surfacing; the next one is 2s away.
        }
      });
    }

    controller = StreamController<Room>.broadcast(
      onListen: start,
      onCancel: () async {
        poll?.cancel();
        final c = channel;
        channel = null;
        if (c != null) await _client.removeChannel(c);
      },
    );

    return controller.stream;
  }

  // -------------------------------------------------------------------------
  // Transitions the HOST drives
  // -------------------------------------------------------------------------
  Future<Room> startMatch(String code) => _flow('start_match', {'p_code': code});

  Future<Room> beginCountdown(String code) =>
      _flow('begin_countdown', {'p_code': code});

  Future<Room> openAnswers(String code) =>
      _flow('open_answers', {'p_code': code});

  Future<Room> finishRound({
    required String code,
    required Seat? winner,
    required RoundReason reason,
  }) =>
      _flow('finish_round', {
        'p_code': code,
        'p_winner': winner?.dbValue,
        'p_reason': reason.dbValue,
      });

  Future<Room> nextRound(String code) => _flow('next_round', {'p_code': code});

  Future<Room> forfeit({required String code, required Seat loser}) =>
      _flow('forfeit', {'p_code': code, 'p_loser': loser.dbValue});

  Future<Room> _flow(String fn, Map<String, dynamic> params) async {
    final row = await _client.rpc(fn, params: params);
    return Room.fromRow(Map<String, dynamic>.from(row as Map));
  }

  // -------------------------------------------------------------------------
  // Writes a player makes about ITSELF
  // -------------------------------------------------------------------------
  /// Locking in a club. Only ever touches this player's own two columns, so
  /// the two picks cannot clobber each other however close together they land.
  Future<void> pickClub({
    required String code,
    required Seat seat,
    required Club club,
  }) async {
    final prefix = seat.dbValue;
    await _client.from('rooms').update({
      '${prefix}_club_id': club.id,
      '${prefix}_club_name': club.name,
    }).eq('code', code);
  }

  /// A CORRECT answer, with the time it took.
  ///
  /// [elapsedMs] must come from a monotonic Stopwatch started at this
  /// device's unlock instant and stopped when GÖNDER was pressed — not from
  /// wall-clock arithmetic, and not from when validation returned.
  ///
  /// Wrong guesses are never written: they cost the player nothing but the
  /// seconds spent typing, and they must not tell the opponent anything.
  ///
  /// `is null` in the filter makes this a one-shot: a second submission
  /// cannot overwrite a faster first one, even if the UI somehow allows it.
  Future<void> submitAnswer({
    required String code,
    required Seat seat,
    required String answer,
    required int elapsedMs,
  }) async {
    final prefix = seat.dbValue;
    await _client
        .from('rooms')
        .update({
          '${prefix}_answer': answer,
          '${prefix}_elapsed_ms': elapsedMs,
        })
        .eq('code', code)
        .isFilter('${prefix}_elapsed_ms', null);
  }

  // -------------------------------------------------------------------------
  // Leaving, claiming, and coming back
  // -------------------------------------------------------------------------
  /// "My opponent has gone quiet — give me the match."
  ///
  /// The server decides, not this client. All a client can observe is that
  /// updates stopped arriving, and it cannot tell that apart from its OWN
  /// connection dropping — in which case the opponent is alive and playing.
  /// `claim_forfeit` checks the other seat's heartbeat against the one clock
  /// both players share and returns the row unchanged if they are still
  /// there, so a blip on this side cannot take the match.
  Future<Room> claimForfeit({
    required String code,
    required Seat claimant,
    int silenceSeconds = 20,
  }) =>
      _flow('claim_forfeit', {
        'p_code': code,
        'p_claimant': claimant.dbValue,
        'p_silence': silenceSeconds,
      });

  /// Deliberately walking out. No staleness check — this is the one case
  /// where the client knows something the server cannot infer.
  Future<Room> leaveMatch({required String code, required Seat seat}) =>
      _flow('leave_match', {'p_code': code, 'p_seat': seat.dbValue});

  /// Same two players, same room, scores back to nil. Lands in the lobby
  /// rather than straight into a round, so nobody is dropped into a pick
  /// phase they were not looking at.
  Future<Room> rematch(String code) => _flow('rematch', {'p_code': code});

  /// The match this device was in when it was last killed, if there is one.
  ///
  /// The player id lives in the device's own storage and survives a restart,
  /// so getting back in is a lookup rather than anything clever.
  Future<Room?> activeRoomFor(String playerId) async {
    final row = await _client.rpc('active_room_for', params: {
      'p_player_id': playerId,
    });
    if (row == null) return null;
    final map = Map<String, dynamic>.from(row as Map);
    if (map['code'] == null) return null;
    return Room.fromRow(map);
  }

  Future<void> touchSeen({required String code, required Seat seat}) async {
    await _client.rpc('touch_seen', params: {
      'p_code': code,
      'p_seat': seat.dbValue,
    });
  }
}
