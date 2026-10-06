/// Supabase connection details.
///
/// The anon key is SAFE to ship inside the app — that is what it is for. It
/// carries no privileges of its own; everything it can do is decided by the
/// grants and row level security policies on the server, and the client sends
/// it on every request by design. It is not a secret, and it is nothing like
/// the service_role key or the database password, neither of which may ever
/// appear in this repository.
///
/// Both values can still be overridden at build time without touching the
/// source, which is what a CI build or a second environment would use:
///
///     flutter build apk --dart-define=SUPABASE_URL=... \
///                       --dart-define=SUPABASE_PUBLISHABLE_KEY=...
class SupabaseConfig {
  SupabaseConfig._();

  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://yjdcsdikcrdupqmaqoqn.supabase.co',
  );

  /// The publishable key, which replaces the old anon JWT — `Supabase.initialize`
  /// now deprecates `anonKey` in favour of `publishableKey`. Same standing:
  /// public by design, no privileges of its own, everything it can do decided
  /// by grants and RLS on the server.
  ///
  /// The legacy anon JWT still works against the same project and is what
  /// `supabase/smoke_test.py` uses, so the two are interchangeable for now.
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_gGylTdpJ4aI3KU6u6UNr9Q_ZaUhHthO',
  );
}
