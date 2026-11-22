import '../../../core/canonical_json.dart';
import '../domain/health_intent.dart';
import 'ports.dart';

class SyncReport {
  int accepted = 0;
  int rejected = 0;
  int needsReview = 0;
  int stillPending = 0;
  bool needsReauth = false;

  /// Why the run stopped early (network, auth). Null = queue fully processed.
  String? interruptedBy;

  /// cattleId -> server resourceVersion after an accepted record (refreshes the work-session cache).
  final Map<String, int> acceptedVersions = {};

  /// Scheduled doses now completed by an accepted record.
  final Set<String> completedSchedules = {};

  bool get isEmpty => accepted + rejected + needsReview + stillPending == 0 && interruptedBy == null;

  String summary() {
    if (isEmpty) return 'Nothing to sync.';
    final parts = <String>[
      if (accepted > 0) '$accepted accepted',
      if (rejected > 0) '$rejected rejected',
      if (needsReview > 0) '$needsReview need review',
      if (stillPending > 0) '$stillPending still pending',
    ];
    final head = parts.isEmpty ? 'Sync ran' : parts.join(', ');
    return interruptedBy == null ? head : '$head — stopped: $interruptedBy';
  }
}

/// Sends PENDING_SYNC intents in submit order, each with its stored immutable body.
///
/// * outcome unknown from a previous attempt -> read receipt first, resubmit only if unseen
/// * transient failure -> keep PENDING_SYNC, remember "maybe delivered", stop the run
/// * auth required -> keep everything pending, ask for re-login
/// * final outcome -> ACCEPTED / REJECTED / NEEDS_REVIEW with reason
class SyncCoordinator {
  SyncCoordinator({
    required this.store,
    required this.submitter,
    required this.receipts,
    required this.clock,
  });

  final DraftStore store;
  final HealthSubmitter submitter;
  final ReceiptReader receipts;
  final Clock clock;

  Future<SyncReport> syncPending({required String mode, required String owner}) async {
    final report = SyncReport();
    final queue = await store.pending(mode: mode, owner: owner);
    for (var i = 0; i < queue.length; i++) {
      final item = queue[i];
      final intentId = item.intentId!;
      final body = item.submittedBody!;
      try {
        SubmitResult? result;
        if (item.outcomeUnknown) {
          result = await receipts.readReceipt(intentId);
        }
        result ??= await submitter.submit(intentId, body);
        await store.recordOutcome(item.localId!, result, clock());
        switch (result) {
          case final AcceptedResult accepted:
            report.accepted++;
            final version = accepted.currentVersion;
            if (version != null) report.acceptedVersions[item.cattleId] = version;
            if (item.scheduleId != null) report.completedSchedules.add(item.scheduleId!);
          case RejectedResult():
            report.rejected++;
          case NeedsReviewResult():
            report.needsReview++;
        }
      } on AuthRequiredException catch (e) {
        report.needsReauth = true;
        report.interruptedBy = e.message;
        report.stillPending += queue.length - i;
        break;
      } on TransientSyncFailure catch (e) {
        await store.markAttempt(item.localId!,
            at: clock(), outcomeUnknown: item.outcomeUnknown || e.maybeDelivered, error: e.message);
        report.interruptedBy = e.message;
        report.stillPending += queue.length - i;
        break;
      }
    }
    return report;
  }
}
