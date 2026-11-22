import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers.dart';
import '../domain/health_intent.dart';
import 'confirm_screen.dart';
import 'history_screen.dart';
import 'record_form_screen.dart';
import 'widgets.dart';

class IntentDetailScreen extends ConsumerWidget {
  const IntentDetailScreen({super.key, required this.localId});

  final int localId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outbox = ref.watch(outboxProvider);
    final session = ref.watch(sessionProvider);
    LocalIntent? i;
    for (final x in outbox.intents) {
      if (x.localId == localId) i = x;
    }
    if (i == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('This record no longer exists.')));
    }
    final it = i;
    final rows = <(String, String)>[
      ('Status', it.status.label),
      ('Animal', it.cattleLabel),
      ('Type', it.recordType.label),
      ('Content', describeDetails(it.recordType, it.details)),
      if (it.scheduleId != null) ('Schedule', it.scheduleId!),
      ('Performed at (occurredAt)', fmtTime(it.occurredAt)),
      ('Captured on device (capturedAt)', fmtTime(it.capturedAt)),
      ('Confirmed at', fmtTime(it.submittedAt)),
      ('intentId', it.intentId ?? '– (not confirmed)'),
      ('Send attempts', '${it.attempts}'),
      if (it.lastAttemptAt != null) ('Last attempt', fmtTime(it.lastAttemptAt)),
      if (it.outcomeUnknown) ('Previous outcome', 'Unknown – next sync checks the receipt first'),
      if (it.lastError != null) ('Temporary error', it.lastError!),
      if (it.serverRecordId != null) ('Server record ID', it.serverRecordId!),
      if (it.committedAt != null) ('Server committed at', fmtTime(it.committedAt)),
      if (it.reason != null) ('Reason', reasonText(it.reason)),
      if (it.readerObservationId != null) ('observationId', it.readerObservationId!),
    ];

    final cattle = session.lookupRfid(it.rfid);

    return Scaffold(
      appBar: AppBar(title: const Text('Record details')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Align(alignment: Alignment.centerLeft, child: IntentStatusChip(it.status)),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                for (final (k, v) in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(width: 150, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
                      Expanded(child: SelectableText(v)),
                    ]),
                  ),
              ]),
            ),
          ),
          if (it.status == IntentStatus.needsReview)
            const Card(
              child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('The original record is kept as is. The farm manager reconciles it centrally; '
                    'do not change the animal/custody on the device to make it pass.'),
              ),
            ),
          if (it.status == IntentStatus.draft) ...[
            const SizedBox(height: 8),
            if (cattle == null)
              const Text('Work session expired or animal not in it – prepare the session again to edit or confirm.'),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: cattle == null
                      ? null
                      : () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => RecordFormScreen(cattle: cattle, draft: it),
                          )),
                  icon: const Icon(Icons.edit),
                  label: const Text('Edit'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: cattle == null
                      ? null
                      : () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => ConfirmScreen(draft: it),
                          )),
                  icon: const Icon(Icons.check),
                  label: const Text('Confirm'),
                ),
              ),
            ]),
            TextButton.icon(
              onPressed: () async {
                final nav = Navigator.of(context);
                await outbox.discard(it);
                nav.pop();
              },
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete draft'),
            ),
          ],
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => HistoryScreen(cattleId: it.cattleId, label: it.cattleLabel),
            )),
            icon: const Icon(Icons.history),
            label: const Text('History of this animal'),
          ),
        ],
      ),
    );
  }
}
