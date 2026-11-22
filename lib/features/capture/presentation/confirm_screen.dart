import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers.dart';
import '../domain/health_intent.dart';
import 'widgets.dart';

/// Last check before the intent becomes immutable. The user must explicitly confirm the
/// animal; only then an intentId is generated and the body frozen.
class ConfirmScreen extends ConsumerStatefulWidget {
  const ConfirmScreen({super.key, required this.draft});

  final LocalIntent draft;

  @override
  ConsumerState<ConfirmScreen> createState() => _ConfirmScreenState();
}

class _ConfirmScreenState extends ConsumerState<ConfirmScreen> {
  bool _rightAnimal = false;
  bool _busy = false;
  List<String> _errors = const [];

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _errors = const [];
    });
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final queued = await ref.read(outboxProvider).confirm(widget.draft);
      messenger.showSnackBar(SnackBar(
        content: Text('Saved durably on this device (intent ${queued.intentId!.substring(0, 8)}…). '
            'This is NOT the final outcome yet – waiting for the server.'),
      ));
      nav.popUntil((r) => r.isFirst);
    } on CaptureValidationException catch (e) {
      setState(() => _errors = e.errors);
    } catch (e) {
      setState(() => _errors = [e.toString()]);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    final rows = <(String, String)>[
      ('Animal', d.cattleLabel),
      ('Type', d.recordType.label),
      ('Content', describeDetails(d.recordType, d.details)),
      if (d.scheduleId != null) ('Schedule', d.scheduleId!),
      if ((d.details['notes'] ?? '').toString().isNotEmpty) ('Notes', d.details['notes'].toString()),
      ('Performed at', fmtTime(d.occurredAt)),
      ('Captured on device at', fmtTime(d.capturedAt)),
      ('Animal record version', 'v${d.expectedVersion}'),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Confirm record')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Table(
                columnWidths: const {0: IntrinsicColumnWidth()},
                children: [
                  for (final (k, v) in rows)
                    TableRow(children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 4, 12, 4),
                        child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(v)),
                    ]),
                ],
              ),
            ),
          ),
          CheckboxListTile(
            value: _rightAnimal,
            onChanged: (v) => setState(() => _rightAnimal = v ?? false),
            title: Text('I confirm this is ${d.cattleLabel}'),
            subtitle: const Text('After confirming, the content can no longer be edited (only reconciled/corrected through review).'),
          ),
          for (final e in _errors)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('• $e', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: (!_rightAnimal || _busy) ? null : _confirm,
            icon: const Icon(Icons.lock),
            label: const Text('Confirm & queue for sync'),
          ),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Later (keep draft)'),
          ),
        ],
      ),
    );
  }
}
