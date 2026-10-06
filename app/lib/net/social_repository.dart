import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile.dart';
import 'account.dart';

/// One row of `my_friends()` (008_friends.sql).
class FriendEntry {
  const FriendEntry({
    required this.id,
    required this.username,
    required this.tag,
    required this.trophies,
    required this.accepted,
    required this.incoming,
  });

  final String id;
  final String username;
  final String tag;
  final int trophies;

  /// False while it is still a request.
  final bool accepted;

  /// For a request: true when THEY asked ME.
  final bool incoming;

  factory FriendEntry.fromRow(Map<String, dynamic> row) => FriendEntry(
        id: row['id'] as String,
        username: row['username'] as String,
        tag: row['tag'] as String,
        trophies: (row['trophies'] as int?) ?? 0,
        accepted: row['status'] == 'accepted',
        incoming: row['incoming'] == true,
      );
}

/// What sending a friend request did.
enum FriendRequestResult { sent, accepted, alreadySent, alreadyFriends }

class SocialException implements Exception {
  const SocialException(this.message);
  final String message;
  @override
  String toString() => 'SocialException($message)';
}

/// Leaderboards and friends. Every read is safe offline (empty / null);
/// writes throw [SocialException] with Turkish copy.
class SocialRepository {
  SocialRepository._();
  static final SocialRepository instance = SocialRepository._();

  static const globalLimit = 100;

  Future<SupabaseClient?> _online() async {
    if (!await Account.instance.ensureOnline()) return null;
    return Supabase.instance.client;
  }

  /// Global: the top 100 by trophies, in the order `my_rank()` counts.
  Future<List<Profile>> globalTop() async {
    final c = await _online();
    if (c == null) return const [];
    try {
      final rows = await c
          .from('profiles')
          .select()
          .order('trophies', ascending: false)
          .order('id', ascending: true)
          .limit(globalLimit);
      return [for (final r in rows) Profile.fromRow(r)];
    } catch (e) {
      debugPrint('globalTop failed: $e');
      return const [];
    }
  }

  Future<int?> myRank() async {
    final c = await _online();
    if (c == null) return null;
    try {
      return await c.rpc('my_rank') as int?;
    } catch (e) {
      debugPrint('myRank failed: $e');
      return null;
    }
  }

  /// Arkadaş: this player and their accepted friends, by trophies.
  Future<List<Profile>> friendsLeaderboard() async {
    final c = await _online();
    if (c == null) return const [];
    try {
      final rows = await c.rpc('friends_leaderboard') as List;
      return [
        for (final r in rows) Profile.fromRow(Map<String, dynamic>.from(r as Map))
      ];
    } catch (e) {
      debugPrint('friendsLeaderboard failed: $e');
      return const [];
    }
  }

  Future<List<FriendEntry>> friends() async {
    final c = await _online();
    if (c == null) return const [];
    try {
      final rows = await c.rpc('my_friends') as List;
      return [
        for (final r in rows)
          FriendEntry.fromRow(Map<String, dynamic>.from(r as Map))
      ];
    } catch (e) {
      debugPrint('friends failed: $e');
      return const [];
    }
  }

  /// The number on Ana Sayfa's `İstek Rozeti`.
  Future<int> incomingRequestCount() async {
    final all = await friends();
    return all.where((f) => !f.accepted && f.incoming).length;
  }

  /// The Arkadaş Ekle preview: who `name#TAG` is, or null.
  Future<Profile?> findPlayer(String username, String tag) async {
    final c = await _online();
    if (c == null) throw const SocialException('Bağlantı kurulamadı');
    final row = await c.rpc('find_player', params: {
      'p_username': username,
      'p_tag': tag,
    });
    if (row == null) return null;
    final map = Map<String, dynamic>.from(row as Map);
    if (map['id'] == null) return null;
    return Profile.fromRow(map);
  }

  Future<FriendRequestResult> sendRequest(String username, String tag) async {
    final c = await _online();
    if (c == null) throw const SocialException('Bağlantı kurulamadı');
    try {
      final r = await c.rpc('send_friend_request', params: {
        'p_username': username,
        'p_tag': tag,
      });
      return switch (r as String) {
        'accepted' => FriendRequestResult.accepted,
        'already_sent' => FriendRequestResult.alreadySent,
        'already_friends' => FriendRequestResult.alreadyFriends,
        _ => FriendRequestResult.sent,
      };
    } on PostgrestException catch (e) {
      if (e.message.contains('player_not_found')) {
        throw const SocialException('Böyle bir oyuncu yok');
      }
      if (e.message.contains('cannot_add_self')) {
        throw const SocialException('Bu senin kimliğin');
      }
      throw SocialException(e.message);
    }
  }

  Future<void> respond(String requesterId, {required bool accept}) async {
    final c = await _online();
    if (c == null) throw const SocialException('Bağlantı kurulamadı');
    await c.rpc('respond_friend_request', params: {
      'p_requester': requesterId,
      'p_accept': accept,
    });
  }

  Future<void> remove(String otherId) async {
    final c = await _online();
    if (c == null) throw const SocialException('Bağlantı kurulamadı');
    await c.rpc('remove_friend', params: {'p_other': otherId});
  }
}
