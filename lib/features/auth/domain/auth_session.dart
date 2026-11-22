/// Identity shown in the UI. Roles are for display only: authorization is decided by the
/// server from the verified token and current grants, never by the app.
class Principal {
  const Principal({required this.username, required this.displayName, this.roles = const []});

  final String username;
  final String displayName;
  final List<String> roles;

  Map<String, Object?> toJson() => {'username': username, 'displayName': displayName, 'roles': roles};

  factory Principal.fromJson(Map<String, dynamic> j) => Principal(
        username: j['username'] as String,
        displayName: (j['displayName'] ?? j['username']) as String,
        roles: ((j['roles'] as List?) ?? const []).map((e) => e.toString()).toList(),
      );
}

abstract interface class AuthSession {
  /// Last authenticated user on this device (kept across restarts, even offline).
  Principal? get principal;

  /// True when the token can no longer be used; pending intents are kept until re-login.
  bool get needsReauth;

  Future<Principal?> restore();

  /// Demo mode uses username/password against the simulator; Live uses Keycloak PKCE.
  Future<Principal> login({String? username, String? password});

  Future<void> logout();

  /// Valid bearer token, refreshing if needed. Null = log in again.
  Future<String?> accessToken();

  void markNeedsReauth();
}
