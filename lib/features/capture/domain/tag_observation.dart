import '../../../core/canonical_json.dart';

/// One raw RFID read (contracts/events/tag-observation.v1.schema.json, readerKind MOBILE).
/// A scan only identifies an animal. It never implies a passage and never creates a health record.
class TagObservation {
  const TagObservation({
    required this.observationId,
    required this.readerId,
    required this.seq,
    required this.tagId,
    required this.observedAt,
  });

  final String observationId;
  final String readerId;
  final int seq;
  final String tagId;
  final DateTime observedAt;

  /// MOBILE observations never carry `direction`.
  Map<String, Object?> toJson() => {
        'schemaVersion': 'tag-observation.v1',
        'observationId': observationId,
        'readerId': readerId,
        'readerKind': 'MOBILE',
        'seq': seq,
        'tagId': tagId,
        'observedAt': isoUtc(observedAt),
      };
}
