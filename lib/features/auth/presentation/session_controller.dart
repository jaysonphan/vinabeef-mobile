import 'package:flutter/foundation.dart';

import '../../../composition_root.dart';
import '../../../core/canonical_json.dart';
import '../../../core/config.dart';
import '../../capture/application/ports.dart';
import '../../capture/application/work_session_service.dart';
import '../../capture/data/local_database.dart';
import '../../capture/data/simulator/simulated_health_backend.dart';
import '../../capture/domain/cattle.dart';
import '../../capture/domain/work_session.dart';
import '../domain/auth_session.dart';

/// Mode, login state and the offline work session (capture window).
class SessionController extends ChangeNotifier {
  SessionController({
    required this.localDb,
    required this.simulator,
    required this.workSessions,
    Clock? clock,
  }) : clock = clock ?? DateTime.now;

  final LocalDatabase localDb;
  final SimulatedHealthBackend simulator;
  final WorkSessionStore workSessions;
  final Clock clock;

  AppMode mode = AppMode.demo;
  late Dependencies deps;
  WorkSession? workSession;
  bool busy = false;
  String? error;

  Principal? get principal => deps.auth.principal;
  bool get needsReauth => deps.auth.needsReauth;

  bool get captureAllowed => workSession?.isValidFor(principal?.username, clock()) ?? false;

  Future<void> init() async {
    mode = AppMode.fromKey(await localDb.getMeta('mode'));
    deps = buildDependencies(mode, simulator);
    await deps.auth.restore();
    workSession = await workSessions.load(mode.key);
    notifyListeners();
  }

  Future<void> setMode(AppMode m) async {
    if (principal != null || m == mode) return;
    mode = m;
    await localDb.setMeta('mode', m.key);
    deps = buildDependencies(mode, simulator);
    await deps.auth.restore();
    workSession = await workSessions.load(mode.key);
    error = null;
    notifyListeners();
  }

  Future<T?> _run<T>(Future<T> Function() action) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      return await action();
    } catch (e) {
      error = e.toString();
      return null;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> login({String? username, String? password}) async {
    final previous = principal?.username;
    final p = await _run(() => deps.auth.login(username: username, password: password));
    if (p == null) return false;
    if (previous != null && previous != p.username) {
      // Another user on a shared device: the previous work session must not be reused.
      await workSessions.clear(mode.key);
      workSession = null;
    }
    notifyListeners();
    return true;
  }

  /// Keeps drafts/pending on the device (they belong to their owner); clears the cached
  /// cattle list so nothing sensitive stays readable for the next user.
  Future<void> logout() async {
    await _run(() async {
      await deps.auth.logout();
      await workSessions.clear(mode.key);
      workSession = null;
    });
  }

  Future<bool> prepareWorkSession() async {
    final user = principal?.username;
    if (user == null) return false;
    final s = await _run(() => WorkSessionService(
          directory: deps.directory,
          store: workSessions,
          clock: clock,
        ).prepare(mode: mode.key, username: user));
    if (s == null) return false;
    workSession = s;
    notifyListeners();
    return true;
  }

  Cattle? lookupRfid(String rfid) => captureAllowed ? workSession!.byRfid(rfid) : null;

  /// After sync: the server bumped resourceVersion of animals with an accepted record and closed
  /// their scheduled doses. Updating the cache keeps the next capture for the same animal from
  /// being sent with a stale expectedVersion. Already-queued intents are immutable and unaffected.
  Future<void> applyAcceptedOutcomes(Map<String, int> versions, Set<String> completedSchedules) async {
    final ws = workSession;
    if (ws == null || (versions.isEmpty && completedSchedules.isEmpty)) return;
    final updated = WorkSession(
      username: ws.username,
      preparedAt: ws.preparedAt,
      expiresAt: ws.expiresAt,
      cattle: [
        for (final c in ws.cattle)
          c.copyWith(
            resourceVersion: versions[c.cattleId],
            schedules: c.schedules.where((s) => !completedSchedules.contains(s.scheduleId)).toList(),
          ),
      ],
    );
    await workSessions.save(mode.key, updated);
    workSession = updated;
    notifyListeners();
  }

  void flagNeedsReauth() {
    deps.auth.markNeedsReauth();
    notifyListeners();
  }

  void clearError() {
    error = null;
    notifyListeners();
  }
}
