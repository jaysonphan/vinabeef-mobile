/// Runtime configuration. Values can be overridden with --dart-define.
///
/// Android emulator: run `adb reverse tcp:8080 tcp:8080 && adb reverse tcp:8081 tcp:8081`
/// so `localhost` on the phone is the host, and the OIDC issuer equals the token `iss`.
enum AppMode {
  /// In-app simulated Health server. Clearly labelled; used until herd-health exposes its API.
  demo,

  /// Keycloak (PKCE) + herd-health REST API from the compose stack.
  live;

  String get key => name;

  String get label => switch (this) {
        AppMode.demo => 'Demo – in-app simulated server',
        AppMode.live => 'Live – Keycloak + herd-health',
      };

  static AppMode fromKey(String? key) =>
      AppMode.values.firstWhere((m) => m.key == key, orElse: () => AppMode.demo);
}

class AppConfig {
  static const apiBaseUrl =
      String.fromEnvironment('VB_API_BASE_URL', defaultValue: 'http://localhost:8080');
  static const oidcIssuer = String.fromEnvironment('VB_OIDC_ISSUER',
      defaultValue: 'http://localhost:8081/realms/vinabeef');
  static const oidcClientId =
      String.fromEnvironment('VB_OIDC_CLIENT_ID', defaultValue: 'vinabeef-mobile');
  static const oidcRedirectUri = 'vn.edu.hcmut.vinabeef:/oauthredirect';

  /// How long a prepared work session (cattle-in-scope cache) allows offline capture.
  /// Proposal value (label P) – the team still has to agree on it.
  static const workSessionTtl = Duration(hours: 12);

  /// Foreground retry period while the app is open.
  static const syncInterval = Duration(seconds: 20);

  /// Reads arriving within this window are treated as one scan (multi-tag detection).
  static const scanWindow = Duration(milliseconds: 700);

  /// Max clock skew tolerated for occurredAt in the future.
  static const futureTolerance = Duration(minutes: 5);
}
