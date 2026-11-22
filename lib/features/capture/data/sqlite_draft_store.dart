import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../application/ports.dart';
import '../domain/health_intent.dart';

class OutcomeColumns {
  const OutcomeColumns(this.status, this.recordId, this.committedAt, this.reason);
  final IntentStatus status;
  final String? recordId;
  final DateTime? committedAt;
  final String? reason;
}

OutcomeColumns outcomeColumns(SubmitResult result) {
  switch (result) {
    case final AcceptedResult r:
      return OutcomeColumns(IntentStatus.accepted, r.recordId, r.committedAt, null);
    case final RejectedResult r:
      return OutcomeColumns(IntentStatus.rejected, null, null, r.reason);
    case final NeedsReviewResult r:
      return OutcomeColumns(IntentStatus.needsReview, null, null, r.reason);
  }
}

/// Durable [DraftStore]. Every state guard is in the WHERE clause, so a stale UI cannot
/// edit a submitted intent or overwrite a final outcome.
class SqliteDraftStore implements DraftStore {
  SqliteDraftStore(this._db);

  final Database _db;
  static const _t = 'intents';

  static int? _ms(DateTime? t) => t?.millisecondsSinceEpoch;
  static DateTime? _dt(Object? v) => v == null ? null : DateTime.fromMillisecondsSinceEpoch(v as int);

  Map<String, Object?> _draftColumns(LocalIntent d) => {
        'mode': d.mode,
        'owner': d.owner,
        'status': IntentStatus.draft.wire,
        'cattle_id': d.cattleId,
        'rfid': d.rfid,
        'cattle_label': d.cattleLabel,
        'record_type': d.recordType.wire,
        'details_json': jsonEncode(d.details),
        'schedule_id': d.scheduleId,
        'expected_custody_version': d.expectedVersion, // column name kept from schema v1
        'reader_observation_id': d.readerObservationId,
        'occurred_at': _ms(d.occurredAt),
        'captured_at': _ms(d.capturedAt),
      };

  LocalIntent _fromRow(Map<String, Object?> r) => LocalIntent(
        localId: r['local_id'] as int,
        mode: r['mode'] as String,
        owner: r['owner'] as String,
        intentId: r['intent_id'] as String?,
        status: IntentStatus.fromWire(r['status'] as String),
        cattleId: r['cattle_id'] as String,
        rfid: r['rfid'] as String,
        cattleLabel: r['cattle_label'] as String,
        recordType: RecordType.fromWire(r['record_type'] as String),
        details: Map<String, dynamic>.from(jsonDecode(r['details_json'] as String) as Map),
        scheduleId: r['schedule_id'] as String?,
        expectedVersion: r['expected_custody_version'] as int,
        readerObservationId: r['reader_observation_id'] as String?,
        occurredAt: _dt(r['occurred_at'])!,
        capturedAt: _dt(r['captured_at'])!,
        submittedBody: r['submitted_body'] as String?,
        submittedAt: _dt(r['submitted_at']),
        lastAttemptAt: _dt(r['last_attempt_at']),
        committedAt: _dt(r['committed_at']),
        attempts: r['attempts'] as int,
        outcomeUnknown: (r['outcome_unknown'] as int) == 1,
        serverRecordId: r['server_record_id'] as String?,
        reason: r['reason'] as String?,
        lastError: r['last_error'] as String?,
      );

  @override
  Future<LocalIntent> insertDraft(LocalIntent draft) async {
    if (draft.status != IntentStatus.draft) {
      throw const IllegalIntentTransition('insertDraft only accepts DRAFT');
    }
    final id = await _db.insert(_t, _draftColumns(draft));
    return (await get(id))!;
  }

  @override
  Future<LocalIntent> updateDraft(LocalIntent draft) async {
    final count = await _db.update(_t, _draftColumns(draft),
        where: 'local_id = ? AND status = ?', whereArgs: [draft.localId, IntentStatus.draft.wire]);
    if (count != 1) {
      throw const IllegalIntentTransition('This record is no longer a draft and cannot be edited.');
    }
    return (await get(draft.localId!))!;
  }

  @override
  Future<void> deleteDraft(int localId) async {
    final count = await _db.delete(_t,
        where: 'local_id = ? AND status = ?', whereArgs: [localId, IntentStatus.draft.wire]);
    if (count != 1) throw const IllegalIntentTransition('Only drafts can be deleted.');
  }

  @override
  Future<LocalIntent> confirm(int localId,
      {required String intentId, required String submittedBody, required DateTime submittedAt}) async {
    final count = await _db.update(
      _t,
      {
        'intent_id': intentId,
        'status': IntentStatus.pendingSync.wire,
        'submitted_body': submittedBody,
        'submitted_at': _ms(submittedAt),
      },
      where: 'local_id = ? AND status = ?',
      whereArgs: [localId, IntentStatus.draft.wire],
    );
    if (count != 1) throw const IllegalIntentTransition('Only drafts can be confirmed.');
    return (await get(localId))!;
  }

  @override
  Future<LocalIntent?> get(int localId) async {
    final rows = await _db.query(_t, where: 'local_id = ?', whereArgs: [localId], limit: 1);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  @override
  Future<List<LocalIntent>> list({required String mode, required String owner}) async {
    final rows = await _db.query(_t,
        where: 'mode = ? AND owner = ?', whereArgs: [mode, owner], orderBy: 'captured_at DESC');
    return rows.map(_fromRow).toList();
  }

  @override
  Future<List<LocalIntent>> pending({required String mode, required String owner}) async {
    final rows = await _db.query(_t,
        where: 'mode = ? AND owner = ? AND status = ?',
        whereArgs: [mode, owner, IntentStatus.pendingSync.wire],
        orderBy: 'submitted_at ASC, local_id ASC');
    return rows.map(_fromRow).toList();
  }

  @override
  Future<void> markAttempt(int localId,
      {required DateTime at, required bool outcomeUnknown, String? error}) async {
    await _db.rawUpdate(
      'UPDATE $_t SET attempts = attempts + 1, last_attempt_at = ?, outcome_unknown = ?, '
      'last_error = ? WHERE local_id = ? AND status = ?',
      [_ms(at), outcomeUnknown ? 1 : 0, error, localId, IntentStatus.pendingSync.wire],
    );
  }

  @override
  Future<void> recordOutcome(int localId, SubmitResult result, DateTime at) async {
    final OutcomeColumns c = outcomeColumns(result);
    await _db.rawUpdate(
      'UPDATE $_t SET status = ?, server_record_id = ?, committed_at = ?, reason = ?, '
      'attempts = attempts + 1, last_attempt_at = ?, outcome_unknown = 0, last_error = NULL '
      'WHERE local_id = ? AND status = ?',
      [c.status.wire, c.recordId, _ms(c.committedAt), c.reason, _ms(at), localId,
        IntentStatus.pendingSync.wire],
    );
  }
}
