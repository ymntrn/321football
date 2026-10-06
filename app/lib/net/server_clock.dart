import 'package:supabase_flutter/supabase_flutter.dart';

/// Maps server instants onto this device's clock.
///
/// Every deadline in a match — when the pick window closes, when the 3-2-1
/// ends and input unlocks, when the answer window closes — is written by
/// Postgres as `now() + interval`, so both phones read the *same* instant.
/// Each phone then has to work out when that instant falls on its own clock,
/// because two phones' clocks are not synchronised: a few hundred
/// milliseconds of NTP drift is ordinary and a user can set the clock by hand.
///
/// Firebase's Realtime Database ships `.info/serverTimeOffset` for exactly
/// this. Supabase has no equivalent, so this measures it the way NTP does:
///
///     t0     = local time just before the request
///     server = the server's own clock, from server_now()
///     t1     = local time just after the reply
///     offset = server - (t0 + t1) / 2
///
/// The midpoint assumes the request and the reply take the same time, which
/// is wrong by however asymmetric the path is — so the sample with the
/// SMALLEST round trip is kept and the rest discarded. A fast round trip has
/// less room to hide asymmetry, which is why the best sample beats an average
/// of all of them: averaging lets one slow, lopsided sample drag the result.
///
/// Measured against the Frankfurt region from Belgium: ~16 ms.
///
/// None of this decides who won a round. That is settled by comparing two
/// durations each phone measured against its own monotonic clock, where drift
/// between the phones cancels out entirely. The offset only exists so the
/// countdown *looks* simultaneous.
class ServerClock {
  ServerClock(this._client);

  final SupabaseClient _client;

  Duration _offset = Duration.zero;
  Duration? _bestRtt;

  /// How far ahead of this device the server's clock is.
  Duration get offset => _offset;

  /// Round trip of the sample the offset came from. Useful to show, and a
  /// sanity check: an offset measured over a 2-second round trip is worth
  /// very little.
  Duration? get bestRoundTrip => _bestRtt;

  bool get isMeasured => _bestRtt != null;

  /// Takes [samples] measurements and keeps the best one.
  ///
  /// Safe to call again later; it only replaces the stored offset if it finds
  /// a faster round trip than the one already recorded, so a re-sync on a
  /// congested connection cannot make the estimate worse.
  Future<void> sync({int samples = 5}) async {
    for (var i = 0; i < samples; i++) {
      try {
        final t0 = DateTime.now();
        final result = await _client.rpc('server_now');
        final t1 = DateTime.now();

        final serverMs = (result as num).toInt();
        final rtt = t1.difference(t0);
        final midpoint =
            (t0.millisecondsSinceEpoch + t1.millisecondsSinceEpoch) ~/ 2;

        if (_bestRtt == null || rtt < _bestRtt!) {
          _bestRtt = rtt;
          _offset = Duration(milliseconds: serverMs - midpoint);
        }
      } catch (_) {
        // A failed sample is not fatal — the offset is a refinement, not a
        // requirement. An unmeasured clock leaves the offset at zero, which
        // is the same behaviour as trusting the device clock outright.
      }
    }
  }

  /// A server instant, expressed on this device's clock.
  DateTime toLocal(DateTime serverTime) => serverTime.subtract(_offset);

  /// This device's clock, expressed as the server would read it. Used only
  /// for display and diagnostics; never write this back to the database.
  DateTime nowOnServer() => DateTime.now().add(_offset);
}
