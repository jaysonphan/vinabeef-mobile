import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config.dart';
import '../../../providers.dart';
import '../domain/cattle.dart';
import '../domain/tag_observation.dart';
import 'record_form_screen.dart';

/// Scan -> identify -> the user confirms the animal. A scan never creates a record.
/// Several tags in one scan window -> the user must pick; unknown tags are never matched.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _Candidate {
  _Candidate(this.observation, this.cattle);
  final TagObservation observation;
  final Cattle? cattle;
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  StreamSubscription<TagObservation>? _sub;
  final List<TagObservation> _window = [];
  Timer? _windowTimer;
  List<_Candidate> _candidates = const [];
  _Candidate? _selected;

  @override
  void initState() {
    super.initState();
    _sub = ref.read(tagReaderProvider).observations.listen(_onRead);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _windowTimer?.cancel();
    super.dispose();
  }

  void _onRead(TagObservation o) {
    if (_windowTimer == null) {
      _window.clear();
      _windowTimer = Timer(AppConfig.scanWindow, _closeWindow);
    }
    _window.add(o);
  }

  void _closeWindow() {
    _windowTimer = null;
    final session = ref.read(sessionProvider);
    // One candidate per distinct tag (duplicate reads of the same tag collapse).
    final byTag = <String, TagObservation>{};
    for (final o in _window) {
      byTag.putIfAbsent(o.tagId, () => o);
    }
    final list = byTag.values.map((o) => _Candidate(o, session.lookupRfid(o.tagId))).toList();
    if (!mounted) return;
    setState(() {
      _candidates = list;
      // Auto-select only when exactly one KNOWN tag was read; the user still has to confirm.
      _selected = (list.length == 1 && list.first.cattle != null) ? list.first : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final reader = ref.read(tagReaderProvider);
    final cattle = session.workSession?.cattle ?? const <Cattle>[];
    final sampleTags = cattle.take(3).map((c) => c.rfid).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Scan RFID tag')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Simulated reader · ${reader.readerId}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const Text('No hardware/SDK yet: the buttons below emit TagObservation v1 (MOBILE).',
                    style: TextStyle(fontSize: 12)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final t in sampleTags)
                    ActionChip(label: Text(t), avatar: const Icon(Icons.nfc, size: 16), onPressed: () => reader.emit([t])),
                  ActionChip(
                    label: const Text('Unknown tag'),
                    avatar: const Icon(Icons.help_outline, size: 16),
                    onPressed: () => reader.emit(['RFID-UNKNOWN-99']),
                  ),
                  ActionChip(
                    label: const Text('Out-of-scope animal'),
                    avatar: const Icon(Icons.do_not_disturb, size: 16),
                    onPressed: () => reader.emit(['RFID-DL-1002']),
                  ),
                  if (sampleTags.length >= 2)
                    ActionChip(
                      label: const Text('2 tags at once'),
                      avatar: const Icon(Icons.warning_amber, size: 16),
                      onPressed: () => reader.emit([sampleTags[0], sampleTags[1]]),
                    ),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          if (_candidates.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Hold the reader near the ear tag…', textAlign: TextAlign.center),
            ),
          if (_candidates.length > 1)
            Card(
              color: Colors.amber.shade100,
              child: const ListTile(
                leading: Icon(Icons.warning_amber),
                title: Text('Multiple tags read at once'),
                subtitle: Text('Pick the animal you are recording. The app never picks the last tag automatically.'),
              ),
            ),
          for (final c in _candidates)
            Card(
              child: c.cattle == null
                  ? ListTile(
                      leading: const Icon(Icons.error_outline, color: Colors.red),
                      title: Text('Tag ${c.observation.tagId}'),
                      subtitle: const Text('Not in your work session scope – cannot record.'),
                    )
                  : RadioListTile<_Candidate>(
                      value: c,
                      groupValue: _selected,
                      onChanged: (v) => setState(() => _selected = v),
                      title: Text(c.cattle!.label),
                      subtitle: Text('${c.cattle!.cattleId} · ${c.cattle!.location} · seq ${c.observation.seq}'),
                    ),
            ),
          if (_selected != null) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.check),
              label: Text('This is the animal: ${_selected!.cattle!.name}'),
              onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(
                builder: (_) => RecordFormScreen(
                  cattle: _selected!.cattle!,
                  readerObservationId: _selected!.observation.observationId,
                ),
              )),
            ),
          ],
          if (_candidates.isNotEmpty)
            TextButton(
              onPressed: () => setState(() {
                _candidates = const [];
                _selected = null;
              }),
              child: const Text('Scan again'),
            ),
        ],
      ),
    );
  }
}
