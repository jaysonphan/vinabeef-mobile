// Ports (ISP/DIP): the application layer depends only on these small interfaces.
// Adapters: data/ (sqlite, HTTP, simulator, fake reader). Wiring: lib/composition_root.dart.

import '../domain/cattle.dart';
import '../domain/health_intent.dart';
import '../domain/tag_observation.dart';
import '../domain/work_session.dart';

/// Source of raw RFID reads. A scanner only scans: no submit, no heartbeat.
abstract interface class TagReadSource {
  Stream<TagObservation> get observations;
}

/// Online only: cattle in the caller's current scope (used to prepare a work session).
abstract interface class CattleDirectory {
  Future<List<Cattle>> fetchScope();
}

/// Sends one immutable intent body. Returns the final outcome, or throws
/// [TransientSyncFailure] / [AuthRequiredException].
abstract interface class HealthSubmitter {
  Future<SubmitResult> submit(String intentId, String body);
}

/// Reads a receipt for an intent whose outcome is unknown. Null = server never saw it.
abstract interface class ReceiptReader {
  Future<SubmitResult?> readReceipt(String intentId);
}

abstract interface class HistoryReader {
  Future<List<HealthRecord>> history(String cattleId);
}

/// Durable local store. Enforces the state machine: only DRAFT rows can be edited/deleted,
/// the submitted body is written once on confirm and never updated.
abstract interface class DraftStore {
  Future<LocalIntent> insertDraft(LocalIntent draft);
  Future<LocalIntent> updateDraft(LocalIntent draft);
  Future<void> deleteDraft(int localId);
  Future<LocalIntent> confirm(int localId,
      {required String intentId, required String submittedBody, required DateTime submittedAt});
  Future<LocalIntent?> get(int localId);
  Future<List<LocalIntent>> list({required String mode, required String owner});
  Future<List<LocalIntent>> pending({required String mode, required String owner});
  Future<void> markAttempt(int localId,
      {required DateTime at, required bool outcomeUnknown, String? error});
  Future<void> recordOutcome(int localId, SubmitResult result, DateTime at);
}

abstract interface class WorkSessionStore {
  Future<WorkSession?> load(String mode);
  Future<void> save(String mode, WorkSession session);
  Future<void> clear(String mode);
}
