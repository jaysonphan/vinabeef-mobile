import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabeef_mobile/features/capture/application/capture_service.dart';
import 'package:vinabeef_mobile/features/capture/data/in_memory_draft_store.dart';
import 'package:vinabeef_mobile/features/capture/domain/cattle.dart';
import 'package:vinabeef_mobile/features/capture/domain/health_intent.dart';

const cow = Cattle(
  cattleId: '10000000-0000-4000-8000-000000000001',
  rfid: 'RFID-DL-1001',
  name: 'Cow DL 1001',
  farmId: 'FARM-DL',
  barnId: 'BARN-DL-01',
  resourceVersion: 3,
  custodyVersion: 7,
);

void main() {
  late InMemoryDraftStore store;
  late CaptureService capture;
  final now = DateTime.utc(2026, 11, 21, 8);
  var ids = 0;

  setUp(() {
    store = InMemoryDraftStore();
    ids = 0;
    capture = CaptureService(
      store: store,
      clock: () => now,
      deviceId: 'MOB-TEST0001',
      newIntentId: () => 'intent-${++ids}',
    );
  });

  Future<LocalIntent> draft({Map<String, dynamic>? details}) => capture.saveDraft(
        mode: 'demo',
        owner: 'bs.demo',
        cattle: cow,
        recordType: RecordType.vaccination,
        details: details ?? {'vaccineCode': 'FMD', 'doseNumber': 1},
        scheduleId: 'SCH-1',
        occurredAt: now.subtract(const Duration(minutes: 10)),
        readerObservationId: 'obs-1',
      );

  test('confirm freezes a herd-health HealthIntentRequest body with a stable intentId', () async {
    final d = await draft();
    expect(d.status, IntentStatus.draft);
    expect(d.intentId, isNull);

    final q = await capture.confirm(d);
    expect(q.status, IntentStatus.pendingSync);
    expect(q.intentId, 'intent-1');
    final body = jsonDecode(q.submittedBody!) as Map<String, dynamic>;
    // Exactly the OpenAPI fields; the server rejects unknown ones.
    expect(body.keys.toSet(), {
      'intentId', 'cattleId', 'type', 'payload', 'occurredAt', 'deviceRef', 'expectedVersion', 'scheduleId'
    });
    expect(body['intentId'], 'intent-1');
    expect(body['cattleId'], cow.cattleId);
    expect(body['type'], 'VACCINATION');
    expect(body['expectedVersion'], 3, reason: 'resourceVersion, not custodyVersion');
    expect(body['deviceRef'], 'MOB-TEST0001');
    expect(body['occurredAt'], '2026-11-21T07:50:00.000Z');
    expect(body['payload'], {
      'vaccineCode': 'FMD',
      'doseNumber': 1,
      'capturedAt': '2026-11-21T08:00:00.000Z',
      'readerObservationId': 'obs-1',
    });
  });

  test('health status intent never carries a scheduleId or null payload fields', () async {
    final d = await capture.saveDraft(
      mode: 'demo',
      owner: 'bs.demo',
      cattle: cow,
      recordType: RecordType.healthObservation,
      details: {'temperatureC': 39.5, 'symptoms': null},
      scheduleId: 'SCH-1',
      occurredAt: now.subtract(const Duration(minutes: 1)),
    );
    final body = jsonDecode((await capture.confirm(d)).submittedBody!) as Map<String, dynamic>;
    expect(body['type'], 'HEALTH_STATUS');
    expect(body.containsKey('scheduleId'), isFalse);
    expect((body['payload'] as Map).containsKey('symptoms'), isFalse);
  });

  test('a submitted intent cannot be edited, re-confirmed or deleted', () async {
    final q = await capture.confirm(await draft());
    await expectLater(store.updateDraft(q), throwsA(isA<IllegalIntentTransition>()));
    await expectLater(capture.confirm(q), throwsA(isA<IllegalIntentTransition>()));
    await expectLater(capture.discard(q), throwsA(isA<IllegalIntentTransition>()));
    expect((await store.get(q.localId!))!.submittedBody, q.submittedBody);
  });

  test('invalid vaccination is rejected before an intent exists', () async {
    final d = await draft(details: {'vaccineCode': '', 'doseNumber': null});
    await expectLater(capture.confirm(d), throwsA(isA<CaptureValidationException>()));
    expect((await store.get(d.localId!))!.status, IntentStatus.draft);
    expect(ids, 0);
  });

  test('occurredAt in the future is rejected', () async {
    final d = await capture.saveDraft(
      mode: 'demo',
      owner: 'bs.demo',
      cattle: cow,
      recordType: RecordType.healthObservation,
      details: {'temperatureC': 39.5},
      occurredAt: now.add(const Duration(hours: 1)),
    );
    await expectLater(capture.confirm(d), throwsA(isA<CaptureValidationException>()));
  });
}
