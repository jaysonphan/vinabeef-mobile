import '../../../core/canonical_json.dart';
import '../../../core/config.dart';
import '../domain/cattle.dart';
import '../domain/health_intent.dart';
import 'ports.dart';

/// Validation of a capture before it becomes an immutable intent.
/// Changes when clinical form rules change (SRP) – not when transport or storage changes.
class CaptureValidator {
  const CaptureValidator();

  List<String> validate({
    required RecordType recordType,
    required Map<String, dynamic> details,
    required DateTime occurredAt,
    required DateTime now,
  }) {
    final errors = <String>[];
    if (occurredAt.isAfter(now.add(AppConfig.futureTolerance))) {
      errors.add('Time of treatment cannot be in the future.');
    }
    switch (recordType) {
      case RecordType.vaccination:
        final code = (details['vaccineCode'] as String?)?.trim() ?? '';
        final dose = details['doseNumber'];
        if (code.isEmpty) errors.add('Vaccine code is required.');
        if (dose is! int || dose < 1) errors.add('Dose number must be an integer ≥ 1.');
      case RecordType.healthObservation:
        final temp = details['temperatureC'];
        final symptoms = (details['symptoms'] as String?)?.trim() ?? '';
        if (temp == null && symptoms.isEmpty) {
          errors.add('Enter a temperature or symptoms.');
        }
        if (temp != null && (temp is! num || temp < 30 || temp > 45)) {
          errors.add('Temperature must be between 30 and 45 °C.');
        }
    }
    return errors;
  }
}

/// Use case: capture a draft at the barn and turn it into an immutable, queued intent.
/// Scanning never calls this; the user must pick the animal and confirm the content.
class CaptureService {
  CaptureService({
    required this.store,
    required this.clock,
    required this.deviceId,
    required this.newIntentId,
    this.validator = const CaptureValidator(),
  });

  final DraftStore store;
  final Clock clock;
  final String deviceId;
  final String Function() newIntentId;
  final CaptureValidator validator;

  /// Saves (or updates) a DRAFT durably. Drafts may be incomplete.
  Future<LocalIntent> saveDraft({
    int? localId,
    required String mode,
    required String owner,
    required Cattle cattle,
    required RecordType recordType,
    required Map<String, dynamic> details,
    String? scheduleId,
    required DateTime occurredAt,
    String? readerObservationId,
  }) {
    final draft = LocalIntent(
      localId: localId,
      mode: mode,
      owner: owner,
      status: IntentStatus.draft,
      cattleId: cattle.cattleId,
      rfid: cattle.rfid,
      cattleLabel: '${cattle.label} (${cattle.location})',
      recordType: recordType,
      details: details,
      scheduleId: scheduleId,
      expectedVersion: cattle.resourceVersion,
      readerObservationId: readerObservationId,
      occurredAt: occurredAt,
      capturedAt: clock(),
    );
    return localId == null ? store.insertDraft(draft) : store.updateDraft(draft);
  }

  /// DRAFT -> PENDING_SYNC. Generates the stable intentId and freezes the body.
  Future<LocalIntent> confirm(LocalIntent draft) async {
    if (draft.status != IntentStatus.draft || draft.localId == null) {
      throw const IllegalIntentTransition('Only a saved draft can be confirmed.');
    }
    final now = clock();
    final errors = validator.validate(
      recordType: draft.recordType,
      details: draft.details,
      occurredAt: draft.occurredAt,
      now: now,
    );
    if (errors.isNotEmpty) throw CaptureValidationException(errors);

    final intentId = newIntentId();
    final body = buildSubmissionBody(draft, intentId: intentId, deviceRef: deviceId);
    return store.confirm(draft.localId!,
        intentId: intentId, submittedBody: body, submittedAt: now);
  }

  Future<void> discard(LocalIntent draft) async {
    if (draft.status != IntentStatus.draft || draft.localId == null) {
      throw const IllegalIntentTransition('Only drafts can be deleted.');
    }
    return store.deleteDraft(draft.localId!);
  }
}

/// herd-health `HealthIntentRequest` (contracts/openapi/herd-health.v1.yaml). The server rejects
/// unknown fields, so the shape must match exactly:
/// * exactly one of cattleId / rfid -> we send cattleId (the animal the user confirmed)
/// * actor/role/farm are NOT sent: the server takes them from the verified token
/// * capture provenance (capturedAt, reader observation) travels inside the clinical payload
/// * expectedVersion = animal resourceVersion seen at capture time
String buildSubmissionBody(LocalIntent draft, {required String intentId, required String deviceRef}) {
  final payload = <String, dynamic>{
    for (final e in draft.details.entries)
      if (e.value != null) e.key: e.value,
    'capturedAt': isoUtc(draft.capturedAt),
    if (draft.readerObservationId != null) 'readerObservationId': draft.readerObservationId,
  };
  return canonicalJson({
    'intentId': intentId,
    'cattleId': draft.cattleId,
    'type': draft.recordType.wire,
    'payload': payload,
    'occurredAt': isoUtc(draft.occurredAt),
    'deviceRef': deviceRef,
    'expectedVersion': draft.expectedVersion,
    if (draft.recordType == RecordType.vaccination && draft.scheduleId != null)
      'scheduleId': draft.scheduleId,
  });
}
