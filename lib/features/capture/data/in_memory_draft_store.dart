import '../application/ports.dart';
import '../domain/health_intent.dart';
import 'sqlite_draft_store.dart' show outcomeColumns;

/// Same guards as [SqliteDraftStore], in memory. For unit tests only: it is NOT durable and
/// must never be used to claim restart/crash durability (plan T10 note).
class InMemoryDraftStore implements DraftStore {
  final Map<int, LocalIntent> _rows = {};
  int _nextId = 1;

  LocalIntent _rebuild(
    LocalIntent b, {
    IntentStatus? status,
    String? intentId,
    String? submittedBody,
    DateTime? submittedAt,
    DateTime? lastAttemptAt,
    DateTime? committedAt,
    int? attempts,
    bool? outcomeUnknown,
    String? serverRecordId,
    String? reason,
    String? lastError,
    bool clearError = false,
  }) =>
      LocalIntent(
        localId: b.localId,
        mode: b.mode,
        owner: b.owner,
        intentId: intentId ?? b.intentId,
        status: status ?? b.status,
        cattleId: b.cattleId,
        rfid: b.rfid,
        cattleLabel: b.cattleLabel,
        recordType: b.recordType,
        details: b.details,
        scheduleId: b.scheduleId,
        expectedVersion: b.expectedVersion,
        readerObservationId: b.readerObservationId,
        occurredAt: b.occurredAt,
        capturedAt: b.capturedAt,
        submittedBody: submittedBody ?? b.submittedBody,
        submittedAt: submittedAt ?? b.submittedAt,
        lastAttemptAt: lastAttemptAt ?? b.lastAttemptAt,
        committedAt: committedAt ?? b.committedAt,
        attempts: attempts ?? b.attempts,
        outcomeUnknown: outcomeUnknown ?? b.outcomeUnknown,
        serverRecordId: serverRecordId ?? b.serverRecordId,
        reason: reason ?? b.reason,
        lastError: clearError ? null : (lastError ?? b.lastError),
      );

  @override
  Future<LocalIntent> insertDraft(LocalIntent draft) async {
    if (draft.status != IntentStatus.draft) {
      throw const IllegalIntentTransition('insertDraft only accepts DRAFT');
    }
    final row = draft.copyWith(localId: _nextId++);
    _rows[row.localId!] = row;
    return row;
  }

  @override
  Future<LocalIntent> updateDraft(LocalIntent draft) async {
    final cur = _rows[draft.localId];
    if (cur == null || cur.status != IntentStatus.draft) {
      throw const IllegalIntentTransition('This record is no longer a draft and cannot be edited.');
    }
    _rows[draft.localId!] = draft.copyWith(status: IntentStatus.draft);
    return _rows[draft.localId!]!;
  }

  @override
  Future<void> deleteDraft(int localId) async {
    final cur = _rows[localId];
    if (cur == null || cur.status != IntentStatus.draft) {
      throw const IllegalIntentTransition('Only drafts can be deleted.');
    }
    _rows.remove(localId);
  }

  @override
  Future<LocalIntent> confirm(int localId,
      {required String intentId, required String submittedBody, required DateTime submittedAt}) async {
    final cur = _rows[localId];
    if (cur == null || cur.status != IntentStatus.draft) {
      throw const IllegalIntentTransition('Only drafts can be confirmed.');
    }
    final row = _rebuild(cur,
        status: IntentStatus.pendingSync,
        intentId: intentId,
        submittedBody: submittedBody,
        submittedAt: submittedAt);
    _rows[localId] = row;
    return row;
  }

  @override
  Future<LocalIntent?> get(int localId) async => _rows[localId];

  @override
  Future<List<LocalIntent>> list({required String mode, required String owner}) async =>
      _rows.values.where((r) => r.mode == mode && r.owner == owner).toList()
        ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));

  @override
  Future<List<LocalIntent>> pending({required String mode, required String owner}) async =>
      _rows.values
          .where((r) => r.mode == mode && r.owner == owner && r.status == IntentStatus.pendingSync)
          .toList()
        ..sort((a, b) => a.submittedAt!.compareTo(b.submittedAt!));

  @override
  Future<void> markAttempt(int localId,
      {required DateTime at, required bool outcomeUnknown, String? error}) async {
    final cur = _rows[localId];
    if (cur == null || cur.status != IntentStatus.pendingSync) return;
    _rows[localId] = _rebuild(cur,
        attempts: cur.attempts + 1, lastAttemptAt: at, outcomeUnknown: outcomeUnknown, lastError: error);
  }

  @override
  Future<void> recordOutcome(int localId, SubmitResult result, DateTime at) async {
    final cur = _rows[localId];
    if (cur == null || cur.status != IntentStatus.pendingSync) return;
    final c = outcomeColumns(result);
    _rows[localId] = _rebuild(cur,
        status: c.status,
        serverRecordId: c.recordId,
        committedAt: c.committedAt,
        reason: c.reason,
        attempts: cur.attempts + 1,
        lastAttemptAt: at,
        outcomeUnknown: false,
        clearError: true);
  }
}
