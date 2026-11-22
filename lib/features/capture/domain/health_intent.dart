/// App-side lifecycle of a health intent (plan 4.3 "Draft state").
///
/// DRAFT --confirm--> PENDING_SYNC --server--> ACCEPTED | REJECTED | NEEDS_REVIEW
/// PENDING_SYNC stays PENDING_SYNC on timeout / network loss / expired login (retry same ID).
/// Only DRAFT is editable. Once PENDING_SYNC the submitted body is immutable.
enum IntentStatus {
  draft('DRAFT'),
  pendingSync('PENDING_SYNC'),
  accepted('ACCEPTED'),
  rejected('REJECTED'),
  needsReview('NEEDS_REVIEW');

  const IntentStatus(this.wire);
  final String wire;

  static IntentStatus fromWire(String wire) => values.firstWhere((s) => s.wire == wire);

  bool get isEditable => this == draft;
  bool get isFinal => this == accepted || this == rejected || this == needsReview;

  String get label => switch (this) {
        draft => 'Draft',
        pendingSync => 'Pending sync',
        accepted => 'Accepted by server',
        rejected => 'Rejected',
        needsReview => 'Needs review',
      };
}

enum RecordType {
  vaccination('VACCINATION'),
  healthObservation('HEALTH_STATUS');

  const RecordType(this.wire);

  /// herd-health `HealthRecordType`.
  final String wire;

  static RecordType fromWire(String wire) {
    // 'HEALTH_OBSERVATION' = local rows written before the herd-health contract was adopted.
    if (wire == 'HEALTH_OBSERVATION') return healthObservation;
    return values.firstWhere((t) => t.wire == wire);
  }

  String get label => switch (this) {
        vaccination => 'Vaccination',
        healthObservation => 'Health check',
      };
}

class IllegalIntentTransition implements Exception {
  const IllegalIntentTransition(this.message);
  final String message;
  @override
  String toString() => 'IllegalIntentTransition: $message';
}

class CaptureValidationException implements Exception {
  const CaptureValidationException(this.errors);
  final List<String> errors;
  @override
  String toString() => errors.join('\n');
}

/// A locally persisted capture. `owner` = username that captured it on this device.
class LocalIntent {
  const LocalIntent({
    this.localId,
    required this.mode,
    required this.owner,
    this.intentId,
    required this.status,
    required this.cattleId,
    required this.rfid,
    required this.cattleLabel,
    required this.recordType,
    required this.details,
    this.scheduleId,
    required this.expectedVersion,
    this.readerObservationId,
    required this.occurredAt,
    required this.capturedAt,
    this.submittedBody,
    this.submittedAt,
    this.lastAttemptAt,
    this.committedAt,
    this.attempts = 0,
    this.outcomeUnknown = false,
    this.serverRecordId,
    this.reason,
    this.lastError,
  });

  final int? localId;
  final String mode;
  final String owner;

  /// Stable intent ID, generated when the user confirms. Null while DRAFT.
  final String? intentId;
  final IntentStatus status;
  final String cattleId;
  final String rfid;
  final String cattleLabel;
  final RecordType recordType;
  final Map<String, dynamic> details;
  final String? scheduleId;

  /// Server resourceVersion of the animal when the user captured (`expectedVersion` on the wire).
  final int expectedVersion;
  final String? readerObservationId;

  /// When the treatment physically happened (not upload time).
  final DateTime occurredAt;
  final DateTime capturedAt;

  /// Exact JSON body sent on every attempt. Set once on confirm.
  final String? submittedBody;
  final DateTime? submittedAt;
  final DateTime? lastAttemptAt;
  final DateTime? committedAt;
  final int attempts;

  /// True when a previous attempt may have reached the server (timeout after send,
  /// lost response). The next attempt queries the receipt first.
  final bool outcomeUnknown;
  final String? serverRecordId;
  final String? reason;
  final String? lastError;

  LocalIntent copyWith({
    int? localId,
    String? intentId,
    IntentStatus? status,
    String? submittedBody,
    DateTime? submittedAt,
  }) =>
      LocalIntent(
        localId: localId ?? this.localId,
        mode: mode,
        owner: owner,
        intentId: intentId ?? this.intentId,
        status: status ?? this.status,
        cattleId: cattleId,
        rfid: rfid,
        cattleLabel: cattleLabel,
        recordType: recordType,
        details: details,
        scheduleId: scheduleId,
        expectedVersion: expectedVersion,
        readerObservationId: readerObservationId,
        occurredAt: occurredAt,
        capturedAt: capturedAt,
        submittedBody: submittedBody ?? this.submittedBody,
        submittedAt: submittedAt ?? this.submittedAt,
        lastAttemptAt: lastAttemptAt,
        committedAt: committedAt,
        attempts: attempts,
        outcomeUnknown: outcomeUnknown,
        serverRecordId: serverRecordId,
        reason: reason,
        lastError: lastError,
      );
}

/// Final server outcome of one intent. Transport problems are exceptions, not results.
sealed class SubmitResult {
  const SubmitResult();
}

final class AcceptedResult extends SubmitResult {
  const AcceptedResult({required this.recordId, required this.committedAt, this.currentVersion});
  final String recordId;
  final DateTime committedAt;

  /// Animal resourceVersion after this record (used to refresh the work-session cache).
  final int? currentVersion;
}

final class RejectedResult extends SubmitResult {
  const RejectedResult(this.reason);
  final String reason;
}

final class NeedsReviewResult extends SubmitResult {
  const NeedsReviewResult(this.reason);
  final String reason;
}

/// Network down, timeout, 5xx, endpoint missing. The intent stays PENDING_SYNC.
class TransientSyncFailure implements Exception {
  const TransientSyncFailure(this.message, {required this.maybeDelivered});
  final String message;

  /// The request may have been processed (timeout after send, lost response, 5xx).
  final bool maybeDelivered;
  @override
  String toString() => message;
}

/// Token missing/expired/invalid. Pending intents are kept; the user must log in again.
class AuthRequiredException implements Exception {
  const AuthRequiredException([this.message = 'Your session has expired']);
  final String message;
  @override
  String toString() => message;
}

/// Server refused a read (e.g. revoked grant, out of scope).
class AccessDeniedException implements Exception {
  const AccessDeniedException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Server-side committed health record (history view).
class HealthRecord {
  const HealthRecord({
    required this.recordId,
    this.intentId,
    required this.recordType,
    required this.details,
    required this.occurredAt,
    required this.committedAt,
    this.actor,
    this.scheduleId,
  });

  final String recordId;
  final String? intentId;
  final RecordType recordType;
  final Map<String, dynamic> details;
  final DateTime occurredAt;
  final DateTime committedAt;
  final String? actor;
  final String? scheduleId;

  /// herd-health `HealthRecord` (type, payload, recordedAt).
  factory HealthRecord.fromJson(Map<String, dynamic> j) => HealthRecord(
        recordId: j['recordId'] as String,
        intentId: j['intentId'] as String?,
        recordType: RecordType.fromWire((j['type'] ?? j['recordType']) as String),
        details: Map<String, dynamic>.from(((j['payload'] ?? j['details']) as Map?) ?? const {}),
        occurredAt: DateTime.parse(j['occurredAt'] as String),
        committedAt: DateTime.parse((j['recordedAt'] ?? j['committedAt']) as String),
        actor: j['actor'] as String?,
        scheduleId: j['scheduleId'] as String?,
      );
}
