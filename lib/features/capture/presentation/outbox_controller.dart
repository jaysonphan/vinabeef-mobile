import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/canonical_json.dart';
import '../../../core/config.dart';
import '../../auth/presentation/session_controller.dart';
import '../application/capture_service.dart';
import '../application/ports.dart';
import '../application/sync_coordinator.dart';
import '../domain/cattle.dart';
import '../domain/health_intent.dart';

/// Local intents of the current user/mode + the foreground sync loop.
/// Sync runs on app start, on a timer, after each confirm, and on the Sync button.
/// Connectivity is never the only trigger: the server answer decides.
class OutboxController extends ChangeNotifier {
  OutboxController({
    required this.session,
    required this.store,
    required this.deviceId,
    Clock? clock,
  }) : clock = clock ?? DateTime.now {
    session.addListener(_onSessionChanged);
  }

  final SessionController session;
  final DraftStore store;
  final String deviceId;
  final Clock clock;

  List<LocalIntent> intents = const [];
  bool syncing = false;
  SyncReport? lastReport;
  DateTime? lastSyncAt;
  Timer? _timer;
  String? _lastKey;

  String get _mode => session.mode.key;
  String? get _owner => session.principal?.username;

  CaptureService get _capture => CaptureService(
        store: store,
        clock: clock,
        deviceId: deviceId,
        newIntentId: () => const Uuid().v4(),
      );

  int count(IntentStatus s) => intents.where((i) => i.status == s).length;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(AppConfig.syncInterval, (_) => syncNow());
    unawaited(syncNow());
  }

  void _onSessionChanged() {
    final key = '$_mode|$_owner|${session.needsReauth}';
    if (key == _lastKey) return;
    _lastKey = key;
    unawaited(refresh().then((_) => syncNow()));
  }

  Future<void> refresh() async {
    final owner = _owner;
    intents = owner == null ? const [] : await store.list(mode: _mode, owner: owner);
    notifyListeners();
  }

  Future<SyncReport?> syncNow() async {
    final owner = _owner;
    if (owner == null || syncing || session.needsReauth) return null;
    syncing = true;
    notifyListeners();
    try {
      final report = await SyncCoordinator(
        store: store,
        submitter: session.deps.submitter,
        receipts: session.deps.receipts,
        clock: clock,
      ).syncPending(mode: _mode, owner: owner);
      lastReport = report;
      lastSyncAt = clock();
      await session.applyAcceptedOutcomes(report.acceptedVersions, report.completedSchedules);
      if (report.needsReauth) session.flagNeedsReauth();
      return report;
    } finally {
      syncing = false;
      await refresh();
    }
  }

  Future<LocalIntent> saveDraft({
    int? localId,
    required Cattle cattle,
    required RecordType recordType,
    required Map<String, dynamic> details,
    String? scheduleId,
    required DateTime occurredAt,
    String? readerObservationId,
  }) async {
    final owner = _owner;
    if (owner == null) throw StateError('Not signed in');
    if (!session.captureAllowed) {
      throw StateError('Work session expired – prepare it again when online.');
    }
    final saved = await _capture.saveDraft(
      localId: localId,
      mode: _mode,
      owner: owner,
      cattle: cattle,
      recordType: recordType,
      details: details,
      scheduleId: scheduleId,
      occurredAt: occurredAt,
      readerObservationId: readerObservationId,
    );
    await refresh();
    return saved;
  }

  Future<LocalIntent> confirm(LocalIntent draft) async {
    final queued = await _capture.confirm(draft);
    await refresh();
    unawaited(syncNow());
    return queued;
  }

  Future<void> discard(LocalIntent draft) async {
    await _capture.discard(draft);
    await refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    session.removeListener(_onSessionChanged);
    super.dispose();
  }
}
