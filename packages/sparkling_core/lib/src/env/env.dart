/// Build-time configuration from `--dart-define` / `--dart-define-from-file`
/// (see docs/ARCHITECTURE.md "Environments").
///
/// ```sh
/// flutter run --dart-define-from-file=env/dev.json
/// # env/dev.json: { "API_BASE_URL": "...", "SUPABASE_URL": "...", "SUPABASE_ANON_KEY": "...", "DEMO_MODE": "false", "APP_NAME": "customer" }
/// ```
abstract final class Env {
  /// REST base URL including `/v1`, e.g.
  /// `https://europe-west1-sparkling-4e89d.cloudfunctions.net/api/v1`.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:5001/sparkling-4e89d/europe-west1/api/v1',
  );

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  /// When `true` the apps run entirely on in-memory demo repositories
  /// (no Firebase / Supabase / network).
  static const bool demoMode = bool.fromEnvironment(
    'DEMO_MODE',
    defaultValue: false,
  );

  /// 'customer' | 'staff' | 'admin' — sent as `X-Client-App`.
  static const String appName = String.fromEnvironment(
    'APP_NAME',
    defaultValue: 'customer',
  );

  /// Sent as `X-Client-Version` (ENG-005), e.g. `1.0.0+1`.
  static const String appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '0.1.0+1',
  );

  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Human-readable summary for debug screens (never includes secrets).
  static Map<String, Object> describe() => {
    'API_BASE_URL': apiBaseUrl,
    'SUPABASE_URL': supabaseUrl,
    'SUPABASE_ANON_KEY': supabaseAnonKey.isEmpty ? '(unset)' : '(set)',
    'DEMO_MODE': demoMode,
    'APP_NAME': appName,
    'APP_VERSION': appVersion,
  };
}
