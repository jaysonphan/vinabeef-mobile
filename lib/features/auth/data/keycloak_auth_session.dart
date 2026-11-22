import 'dart:convert';

import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/config.dart';
import '../domain/auth_session.dart';

/// Authorization Code + PKCE against the Keycloak public client `vinabeef-mobile`.
/// No client secret in the app. Refresh token in secure storage; access token only in memory.
/// Tokens and clinical content are never logged.
class KeycloakAuthSession implements AuthSession {
  KeycloakAuthSession({FlutterAppAuth? appAuth, FlutterSecureStorage? storage})
      : _appAuth = appAuth ?? const FlutterAppAuth(),
        _storage = storage ?? const FlutterSecureStorage();

  final FlutterAppAuth _appAuth;
  final FlutterSecureStorage _storage;

  static const _kRefresh = 'vb_live_refresh_token';
  static const _kPrincipal = 'vb_live_principal';

  String? _access;
  DateTime? _accessExpiresAt;
  Principal? _principal;
  bool _needsReauth = false;

  @override
  Principal? get principal => _principal;

  @override
  bool get needsReauth => _needsReauth;

  @override
  void markNeedsReauth() => _needsReauth = true;

  @override
  Future<Principal?> restore() async {
    final p = await _storage.read(key: _kPrincipal);
    if (p == null) return null;
    _principal = Principal.fromJson(Map<String, dynamic>.from(jsonDecode(p) as Map));
    // Token is refreshed lazily in accessToken(); offline restart still shows the user so
    // capture inside a valid work session keeps working.
    return _principal;
  }

  @override
  Future<Principal> login({String? username, String? password}) async {
    final AuthorizationTokenResponse? r = await _appAuth.authorizeAndExchangeCode(
      AuthorizationTokenRequest(
        AppConfig.oidcClientId,
        AppConfig.oidcRedirectUri,
        issuer: AppConfig.oidcIssuer,
        scopes: const ['openid', 'profile'],
        allowInsecureConnections: true, // local-dev http issuer only (demo-tls uses https)
      ),
    );
    if (r == null || r.accessToken == null) {
      throw const AuthLoginException('Keycloak sign-in failed.');
    }
    return _apply(r.accessToken!, r.accessTokenExpirationDateTime, r.refreshToken);
  }

  Future<Principal> _apply(String access, DateTime? expiresAt, String? refresh) async {
    _access = access;
    _accessExpiresAt = expiresAt;
    if (refresh != null) await _storage.write(key: _kRefresh, value: refresh);
    final claims = _decodeJwt(access);
    final realmAccess = claims['realm_access'];
    final roles = realmAccess is Map && realmAccess['roles'] is List
        ? (realmAccess['roles'] as List)
            .map((e) => e.toString())
            .where(const {'BS', 'FM', 'SA', 'EM'}.contains)
            .toList()
        : <String>[];
    final p = Principal(
      username: (claims['preferred_username'] ?? claims['sub'] ?? 'unknown') as String,
      displayName: (claims['name'] ?? claims['preferred_username'] ?? 'unknown') as String,
      roles: roles,
    );
    _principal = p;
    _needsReauth = false;
    await _storage.write(key: _kPrincipal, value: jsonEncode(p.toJson()));
    return p;
  }

  @override
  Future<String?> accessToken() async {
    final exp = _accessExpiresAt;
    if (_access != null &&
        (exp == null || DateTime.now().isBefore(exp.subtract(const Duration(seconds: 30))))) {
      return _access;
    }
    final refresh = await _storage.read(key: _kRefresh);
    if (refresh == null) {
      _needsReauth = true;
      return null;
    }
    try {
      final TokenResponse? r = await _appAuth.token(TokenRequest(
        AppConfig.oidcClientId,
        AppConfig.oidcRedirectUri,
        issuer: AppConfig.oidcIssuer,
        refreshToken: refresh,
        scopes: const ['openid', 'profile'],
        allowInsecureConnections: true,
      ));
      if (r == null || r.accessToken == null) return null;
      await _apply(r.accessToken!, r.accessTokenExpirationDateTime, r.refreshToken);
      return _access;
    } catch (_) {
      // Either offline or refresh token rejected. Either way the caller cannot sync now;
      // pending intents stay untouched.
      return null;
    }
  }

  @override
  Future<void> logout() async {
    _access = null;
    _accessExpiresAt = null;
    _principal = null;
    _needsReauth = false;
    await _storage.delete(key: _kRefresh);
    await _storage.delete(key: _kPrincipal);
  }

  static Map<String, dynamic> _decodeJwt(String token) {
    final parts = token.split('.');
    if (parts.length < 2) return const {};
    final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
    return Map<String, dynamic>.from(jsonDecode(payload) as Map);
  }
}

class AuthLoginException implements Exception {
  const AuthLoginException(this.message);
  final String message;
  @override
  String toString() => message;
}
