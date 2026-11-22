import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers.dart';
import '../domain/cattle.dart';
import '../domain/health_intent.dart';
import 'confirm_screen.dart';
import 'widgets.dart';

/// Clinical form bound to ONE confirmed animal. Changing the animal means leaving this form
/// (back to scan) – the content is never silently re-attached to another cow.
class RecordFormScreen extends ConsumerStatefulWidget {
  const RecordFormScreen({super.key, required this.cattle, this.readerObservationId, this.draft});

  final Cattle cattle;
  final String? readerObservationId;

  /// Existing DRAFT being edited.
  final LocalIntent? draft;

  @override
  ConsumerState<RecordFormScreen> createState() => _RecordFormScreenState();
}

class _RecordFormScreenState extends ConsumerState<RecordFormScreen> {
  late RecordType _type;
  String? _scheduleId;
  late DateTime _occurredAt;
  final _vaccine = TextEditingController();
  final _dose = TextEditingController(text: '1');
  final _batch = TextEditingController();
  final _temp = TextEditingController();
  final _symptoms = TextEditingController();
  final _notes = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final d = widget.draft;
    _type = d?.recordType ?? RecordType.vaccination;
    _occurredAt = d?.occurredAt ?? DateTime.now();
    _scheduleId = d?.scheduleId;
    final det = d?.details ?? const <String, dynamic>{};
    _vaccine.text = (det['vaccineCode'] ?? '').toString();
    _dose.text = (det['doseNumber'] ?? 1).toString();
    _batch.text = (det['batchNumber'] ?? det['batchNo'] ?? '').toString();
    _temp.text = det['temperatureC']?.toString() ?? '';
    _symptoms.text = (det['symptoms'] ?? '').toString();
    _notes.text = (det['notes'] ?? '').toString();
  }

  @override
  void dispose() {
    for (final c in [_vaccine, _dose, _batch, _temp, _symptoms, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _details() {
    String? opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    return switch (_type) {
      RecordType.vaccination => {
          'vaccineCode': _vaccine.text.trim(),
          'doseNumber': int.tryParse(_dose.text.trim()),
          'batchNumber': opt(_batch),
          'notes': opt(_notes),
        },
      RecordType.healthObservation => {
          'temperatureC': double.tryParse(_temp.text.trim().replaceAll(',', '.')),
          'symptoms': opt(_symptoms),
          'notes': opt(_notes),
        },
    };
  }

  Future<LocalIntent?> _save() async {
    setState(() => _saving = true);
    try {
      return await ref.read(outboxProvider).saveDraft(
            localId: widget.draft?.localId,
            cattle: widget.cattle,
            recordType: _type,
            details: _details(),
            scheduleId: _type == RecordType.vaccination ? _scheduleId : null,
            occurredAt: _occurredAt,
            readerObservationId: widget.readerObservationId ?? widget.draft?.readerObservationId,
          );
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
      return null;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_occurredAt));
    if (time == null) return;
    setState(() => _occurredAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<bool> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard form?'),
        content: const Text('Unsaved content will be lost. To record another animal, scan again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
        ],
      ),
    );
    return leave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cattle;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmLeave()) nav.pop();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.draft == null ? 'New record' : 'Edit draft')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: ListTile(
                leading: const Icon(Icons.pets),
                title: Text(c.label, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${c.location} · record version v${c.resourceVersion}'),
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<RecordType>(
              segments: [
                for (final t in RecordType.values) ButtonSegment(value: t, label: Text(t.label)),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: const Text('Time performed'),
              subtitle: Text(fmtTime(_occurredAt)),
              trailing: TextButton(onPressed: _pickTime, child: const Text('Change')),
            ),
            if (_type == RecordType.vaccination) ...[
              DropdownButtonFormField<String?>(
                initialValue: _scheduleId,
                decoration: const InputDecoration(labelText: 'Vaccination schedule (optional)'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Not scheduled')),
                  for (final s in c.schedules)
                    DropdownMenuItem<String?>(value: s.scheduleId, child: Text(s.label)),
                ],
                onChanged: (v) => setState(() {
                  _scheduleId = v;
                  for (final s in c.schedules) {
                    if (s.scheduleId == v) {
                      _vaccine.text = s.vaccineCode;
                      if (s.doseNumber != null) _dose.text = '${s.doseNumber}';
                    }
                  }
                }),
              ),
              TextField(controller: _vaccine, decoration: const InputDecoration(labelText: 'Vaccine code *')),
              TextField(
                controller: _dose,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Dose number *'),
              ),
              TextField(controller: _batch, decoration: const InputDecoration(labelText: 'Batch number')),
            ] else ...[
              TextField(
                controller: _temp,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Temperature (°C)'),
              ),
              TextField(controller: _symptoms, decoration: const InputDecoration(labelText: 'Symptoms')),
            ],
            TextField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving
                      ? null
                      : () async {
                          final nav = Navigator.of(context);
                          final saved = await _save();
                          if (saved != null && mounted) {
                            showSnack(context, 'Draft saved on this device.');
                            nav.pop();
                          }
                        },
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save draft'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving
                      ? null
                      : () async {
                          final nav = Navigator.of(context);
                          final saved = await _save();
                          if (saved != null && mounted) {
                            nav.pushReplacement(MaterialPageRoute(
                              builder: (_) => ConfirmScreen(draft: saved),
                            ));
                          }
                        },
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Review & confirm'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
