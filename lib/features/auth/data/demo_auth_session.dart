import '../../capture/data/simulator/simulated_health_backend.dart';
import '../domain/auth_session.dart';

/// Demo-mode login against the simulator (same synthetic users as the Keycloak dev realm).
/// Tokens live only in memory, so an app restart needs a re-login – like an expired token –
/// while the last user and their pending intents stay on the device.
class DemoAuthSession implements AuthSession {
  DemoAuthSession(this._sim);

  final SimulatedHealthBackend _sim;
  Principal? _principal;
  String? _token;
  bool _needsReauth = false;

  @override
  Principal? get principal => _principal;

  @override
  bool get needsReauth => _needsReauth;

  @override
  void markNeedsReauth() => _needsReauth = true;

  static Principal _toPrincipal(SimUser u) =>
      Principal(username: u.username, displayName: u.displayName, roles: [u.role]);

  @override
  Future<Principal?> restore() async {
    final last = await _sim.lastDemoUser();
    final u = last == null ? null : SimulatedHealthBackend.users[last];
    if (u == null) return null;
    _principal = _toPrincipal(u);
    _needsReauth = true; // no token after restart
    return _principal;
  }

  @override
  Future<Principal> login({String? username, String? password}) async {
    final name = (username ?? '').trim();
    _token = await _sim.issueToken(name, password ?? '');
    _principal = _toPrincipal(SimulatedHealthBackend.users[name]!);
    _needsReauth = false;
    await _sim.setLastDemoUser(name);
    return _principal!;
  }

  @override
  Future<void> logout() async {
    _sim.revokeToken(_token);
    _token = null;
    _principal = null;
    _needsReauth = false;
    await _sim.setLastDemoUser(null);
  }

  @override
  Future<String?> accessToken() async => _token;
}
