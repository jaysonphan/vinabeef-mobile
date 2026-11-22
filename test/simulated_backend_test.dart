import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vinabeef_mobile/core/canonical_json.dart';
import 'package:vinabeef_mobile/features/capture/data/simulator/simulated_health_backend.dart';
import 'package:vinabeef_mobile/features/capture/domain/health_intent.dart';

/// The demo server must give the same outcomes/codes as herd-health for the same requests,
/// so Demo and Live behave alike. Evidence for the SIMULATOR only, not for herd-health.
void main() {
  sqfliteFfiInit();
  late SimulatedHealthBackend sim;
  late String token;
  final now = DateTime.utc(2026, 11, 21, 8);

  const cow1 = '10000000-0000-4000-8000-000000000001'; // BARN-DL-01, open FMD dose
  const cow2 = '10000000-0000-4000-8000-000000000002'; // BARN-DL-02
  const cow11 = '10000000-0000-4000-8000-000000000011'; // BARN-DL-01 (demo-only)
  const dose1 = '20000000-0000-4000-8000-000000000001';

  setUp(() async {
    sim = await SimulatedHealthBackend.open(
        factory: databaseFactoryFfi, path: inMemoryDatabasePath, clock: () => now);
    token = await sim.issueToken('bs.demo', 'bs-local');
  });

  tearDown(() => sim.close());

  String body(String id,
          {String cattle = cow1, String? schedule, int version = 0, String vaccine = 'FMD-BOOSTER'}) =>
      canonicalJson({
        'intentId': id,
        'cattleId': cattle,
        'type': 'VACCINATION',
        'payload': {'vaccineCode': vaccine},
        'occurredAt': isoUtc(now.subtract(const Duration(minutes: 5))),
        'deviceRef': 'MOB-TEST',
        'expectedVersion': version,
        if (schedule != null) 'scheduleId': schedule,
      });

  test('bs.demo work session = own barn only, with open doses', () async {
    final scope = await sim.fetchScope(token);
    expect(scope.map((c) => c.rfid).toSet(), {'RFID-DL-1001', 'RFID-DL-1011', 'RFID-DL-1012'});
    expect(scope.firstWhere((c) => c.cattleId == cow1).schedules.single.scheduleId, dose1);
  });

  test('same id + same body -> one record, same outcome (retry x3); version bumped', () async {
    final b = body('30000000-0000-4000-8000-000000000001');
    final first = await sim.submit(token, b) as AcceptedResult;
    expect(first.currentVersion, 1);
    for (var i = 0; i < 3; i++) {
      final again = await sim.submit(token, b) as AcceptedResult;
      expect(again.recordId, first.recordId);
    }
    expect(await sim.recordCount(), 1);
  });

  test('same id + different body -> IDEMPOTENCY_KEY_REUSED, no new record', () async {
    await sim.submit(token, body('30000000-0000-4000-8000-000000000002'));
    final r = await sim.submit(token, body('30000000-0000-4000-8000-000000000002', vaccine: 'LSD'));
    expect((r as NeedsReviewResult).reason, 'IDEMPOTENCY_KEY_REUSED');
    expect(await sim.recordCount(), 1);
  });

  test('response lost: committed once, receipt returns it', () async {
    sim.loseNextResponse = true;
    await expectLater(sim.submit(token, body('30000000-0000-4000-8000-000000000003')),
        throwsA(isA<TransientSyncFailure>().having((e) => e.maybeDelivered, 'maybeDelivered', true)));
    expect(await sim.readReceipt(token, '30000000-0000-4000-8000-000000000003'), isA<AcceptedResult>());
    expect(await sim.recordCount(), 1);
  });

  test('second intent for a completed scheduled dose -> REJECTED SCHEDULE_ALREADY_COMPLETED', () async {
    await sim.submit(token, body('30000000-0000-4000-8000-000000000004', schedule: dose1));
    final r = await sim.submit(token, body('30000000-0000-4000-8000-000000000005', schedule: dose1, version: 1));
    expect((r as RejectedResult).reason, 'SCHEDULE_ALREADY_COMPLETED');
    expect(await sim.recordCount(), 1);
  });

  test('two offline intents for the same cow: second has stale version -> NEEDS_REVIEW', () async {
    await sim.submit(token, body('30000000-0000-4000-8000-000000000006', cattle: cow11));
    final r = await sim.submit(token, body('30000000-0000-4000-8000-000000000007', cattle: cow11));
    expect((r as NeedsReviewResult).reason, 'RESOURCE_VERSION_CHANGED');
  });

  test('BS cannot write for a cow in another barn (403, nothing stored)', () async {
    final r = await sim.submit(token, body('30000000-0000-4000-8000-000000000008', cattle: cow2));
    expect((r as RejectedResult).reason, 'ACCESS_DENIED');
    expect(await sim.receiptCount(), 0);
  });

  test('custody moved out of BS barn before sync -> ACCESS_DENIED', () async {
    await sim.toggleCustody(cow1);
    final r = await sim.submit(token, body('30000000-0000-4000-8000-000000000009'));
    expect((r as RejectedResult).reason, 'ACCESS_DENIED');
    expect(await sim.recordCount(), 0);
  });

  test('unknown field is rejected like herd-health (INVALID_INPUT)', () async {
    final r = await sim.submit(token, canonicalJson({
      'intentId': '30000000-0000-4000-8000-000000000010', 'cattleId': cow1, 'type': 'VACCINATION',
      'payload': {}, 'occurredAt': isoUtc(now), 'deviceRef': 'x', 'expectedVersion': 0, 'actor': 'fm.demo',
    }));
    expect((r as RejectedResult).reason, 'INVALID_INPUT');
  });

  test('revoked grant -> rejected; expired token -> auth required', () async {
    await sim.setGrantRevoked('bs.demo', true);
    expect(await sim.submit(token, body('30000000-0000-4000-8000-000000000011')), isA<RejectedResult>());
    sim.expireAllTokens();
    await expectLater(
        sim.submit(token, body('30000000-0000-4000-8000-000000000012')), throwsA(isA<AuthRequiredException>()));
  });

  test('offline -> transient, nothing delivered', () async {
    sim.online = false;
    await expectLater(sim.submit(token, body('30000000-0000-4000-8000-000000000013')),
        throwsA(isA<TransientSyncFailure>().having((e) => e.maybeDelivered, 'maybeDelivered', false)));
    sim.online = true;
    expect(await sim.recordCount(), 0);
  });
}
