import 'package:flutter_test/flutter_test.dart';
import 'package:vinabeef_mobile/features/capture/application/capture_service.dart';
import 'package:vinabeef_mobile/features/capture/application/ports.dart';
import 'package:vinabeef_mobile/features/capture/application/sync_coordinator.dart';
import 'package:vinabeef_mobile/features/capture/data/in_memory_draft_store.dart';
import 'package:vinabeef_mobile/features/capture/domain/cattle.dart';
import 'package:vinabeef_mobile/features/capture/domain/health_intent.dart';

const cow = Cattle(
    cattleId: 'C-1', rfid: 'R-1', name: 'Cow 1', farmId: 'F', barnId: 'B', custodyVersion: 1);

/// Scripted server: each call pops the next behaviour. Records every (id, body) it received.
class ScriptedServer implements HealthSubmitter, ReceiptReader {
  final List<Object> submitScript = [];
  final Map<String, SubmitResult> receipts = {};
  final List<(String, String)> submitted = [];
  int receiptReads = 0;

  @override
  Future<SubmitResult> submit(String intentId, String body) async {
    submitted.add((intentId, body));
    final next = submitScript.removeAt(0);
    if (next is Exception) throw next;
    return next as SubmitResult;
  }

  @override
  Future<SubmitResult?> readReceipt(String intentId) async {
    receiptReads++;
    return receipts[intentId];
  }
}

void main() {
  late InMemoryDraftStore store;
  late CaptureService capture;
  late ScriptedServer server;
  late SyncCoordinator sync;
  var t = DateTime.utc(2026, 11, 21, 8);
  var n = 0;

  setUp(() {
    store = InMemoryDraftStore();
    server = ScriptedServer();
    n = 0;
    t = DateTime.utc(2026, 11, 21, 8);
    capture = CaptureService(
        store: store, clock: () => t, deviceId: 'MOB-1', newIntentId: () => 'id-${++n}');
    sync = SyncCoordinator(store: store, submitter: server, receipts: server, clock: () => t);
  });

  Future<LocalIntent> queued() async {
    t = t.add(const Duration(seconds: 1));
    final d = await capture.saveDraft(
      mode: 'demo',
      owner: 'bs',
      cattle: cow,
      recordType: RecordType.vaccination,
      details: {'vaccineCode': 'FMD', 'doseNumber': 1},
      occurredAt: t.subtract(const Duration(minutes: 1)),
    );
    return capture.confirm(d);
  }

  Future<LocalIntent> reload(LocalIntent i) async => (await store.get(i.localId!))!;

  test('offline: stays PENDING_SYNC, later accepted once with the same id and body', () async {
    final a = await queued();
    server.submitScript.add(const TransientSyncFailure('offline', maybeDelivered: false));
    final r1 = await sync.syncPending(mode: 'demo', owner: 'bs');
    expect(r1.stillPending, 1);
    expect((await reload(a)).status, IntentStatus.pendingSync);
    expect((await reload(a)).outcomeUnknown, isFalse);

    server.submitScript.add(AcceptedResult(recordId: 'HR-1', committedAt: t));
    final r2 = await sync.syncPending(mode: 'demo', owner: 'bs');
    expect(r2.accepted, 1);
    final done = await reload(a);
    expect(done.status, IntentStatus.accepted);
    expect(done.serverRecordId, 'HR-1');
    expect(server.submitted.map((s) => s.$1).toSet(), {'id-1'});
    expect(server.submitted.map((s) => s.$2).toSet(), {a.submittedBody});
  });

  test('response lost: next run reads the receipt instead of resubmitting', () async {
    final a = await queued();
    server.submitScript.add(const TransientSyncFailure('lost', maybeDelivered: true));
    await sync.syncPending(mode: 'demo', owner: 'bs');
    expect((await reload(a)).outcomeUnknown, isTrue);

    server.receipts['id-1'] = AcceptedResult(recordId: 'HR-9', committedAt: t);
    await sync.syncPending(mode: 'demo', owner: 'bs');
    expect(server.receiptReads, 1);
    expect(server.submitted.length, 1, reason: 'no second POST after a known commit');
    expect((await reload(a)).status, IntentStatus.accepted);
  });

  test('response lost but server never saw it: receipt 404 -> resubmit same body', () async {
    final a = await queued();
    server.submitScript.add(const TransientSyncFailure('timeout', maybeDelivered: true));
    await sync.syncPending(mode: 'demo', owner: 'bs');
    server.submitScript.add(AcceptedResult(recordId: 'HR-2', committedAt: t));
    await sync.syncPending(mode: 'demo', owner: 'bs');
    expect(server.submitted.length, 2);
    expect(server.submitted[0], server.submitted[1]);
    expect((await reload(a)).status, IntentStatus.accepted);
  });

  test('auth expired: everything stays pending, report asks for re-login', () async {
    final a = await queued();
    final b = await queued();
    server.submitScript.add(const AuthRequiredException());
    final r = await sync.syncPending(mode: 'demo', owner: 'bs');
    expect(r.needsReauth, isTrue);
    expect(r.stillPending, 2);
    expect((await reload(a)).status, IntentStatus.pendingSync);
    expect((await reload(b)).status, IntentStatus.pendingSync);
  });

  test('final outcomes keep their reason; terminal intents are not resent', () async {
    final a = await queued();
    final b = await queued();
    server.submitScript
      ..add(const RejectedResult('out of scope'))
      ..add(const NeedsReviewResult('custody changed'));
    final r = await sync.syncPending(mode: 'demo', owner: 'bs');
    expect(r.rejected, 1);
    expect(r.needsReview, 1);
    expect((await reload(a)).reason, 'out of scope');
    expect((await reload(b)).status, IntentStatus.needsReview);

    final again = await sync.syncPending(mode: 'demo', owner: 'bs');
    expect(again.isEmpty, isTrue);
    expect(server.submitted.length, 2);
  });

  test('accepted outcome reports the new animal version for the work-session cache', () async {
    await queued();
    server.submitScript.add(AcceptedResult(recordId: 'HR-3', committedAt: t, currentVersion: 4));
    final r = await sync.syncPending(mode: 'demo', owner: 'bs');
    expect(r.acceptedVersions, {'C-1': 4});
  });

  test('only the owner\'s intents of the current mode are synced', () async {
    await queued();
    final r = await sync.syncPending(mode: 'live', owner: 'bs');
    expect(r.isEmpty, isTrue);
    final r2 = await sync.syncPending(mode: 'demo', owner: 'someone-else');
    expect(r2.isEmpty, isTrue);
    expect(server.submitted, isEmpty);
  });
}
