import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers.dart';
import '../domain/health_intent.dart';
import 'widgets.dart';

/// Server history (authoritative) + this device's own intents for the same animal.
/// Offline: only the local part is shown, clearly marked as not server-confirmed.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key, required this.cattleId, required this.label});

  final String cattleId;
  final String label;

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  late Future<List<HealthRecord>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(sessionProvider).deps.history.history(widget.cattleId);
  }

  @override
  Widget build(BuildContext context) {
    final local = ref
        .watch(outboxProvider)
        .intents
        .where((i) => i.cattleId == widget.cattleId)
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text('History · ${widget.label}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('On server', style: Theme.of(context).textTheme.titleMedium),
          FutureBuilder<List<HealthRecord>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator());
              }
              if (snap.hasError) {
                return ListTile(
                  leading: const Icon(Icons.cloud_off),
                  title: const Text('Could not load server history'),
                  subtitle: Text('${snap.error}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () => setState(() {
                      _future = ref.read(sessionProvider).deps.history.history(widget.cattleId);
                    }),
                  ),
                );
              }
              final recs = snap.data!;
              if (recs.isEmpty) return const ListTile(title: Text('No accepted records yet.'));
              return Column(children: [
                for (final r in recs)
                  ListTile(
                    leading: const Icon(Icons.verified, color: Colors.green),
                    title: Text('${r.recordType.label} · ${describeDetails(r.recordType, r.details)}'),
                    subtitle: Text('${r.recordId} · performed ${fmtTime(r.occurredAt)} · '
                        'commit ${fmtTime(r.committedAt)} · ${r.actor ?? ''}'),
                  ),
              ]);
            },
          ),
          const Divider(height: 32),
          Text('On this device (${local.length})', style: Theme.of(context).textTheme.titleMedium),
          for (final i in local)
            ListTile(
              leading: Icon(statusIcon(i.status), color: statusColor(i.status)),
              title: Text('${i.recordType.label} · ${describeDetails(i.recordType, i.details)}'),
              subtitle: Text('Performed ${fmtTime(i.occurredAt)}'),
              trailing: IntentStatusChip(i.status),
            ),
        ],
      ),
    );
  }
}
