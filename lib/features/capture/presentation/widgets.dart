import 'package:flutter/material.dart';

import '../domain/health_intent.dart';

Color statusColor(IntentStatus s) => switch (s) {
      IntentStatus.draft => Colors.blueGrey,
      IntentStatus.pendingSync => Colors.orange.shade800,
      IntentStatus.accepted => Colors.green.shade700,
      IntentStatus.rejected => Colors.red.shade700,
      IntentStatus.needsReview => Colors.purple.shade600,
    };

IconData statusIcon(IntentStatus s) => switch (s) {
      IntentStatus.draft => Icons.edit_note,
      IntentStatus.pendingSync => Icons.cloud_upload_outlined,
      IntentStatus.accepted => Icons.verified,
      IntentStatus.rejected => Icons.block,
      IntentStatus.needsReview => Icons.report_problem_outlined,
    };

class IntentStatusChip extends StatelessWidget {
  const IntentStatusChip(this.status, {super.key});

  final IntentStatus status;

  @override
  Widget build(BuildContext context) {
    final c = statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: c),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(statusIcon(status), size: 14, color: c),
        const SizedBox(width: 4),
        Text(status.label, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

String fmtTime(DateTime? t) {
  if (t == null) return '–';
  final l = t.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)} ${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
}

String describeDetails(RecordType type, Map<String, dynamic> d) => switch (type) {
      RecordType.vaccination => [
          '${d['vaccineCode'] ?? '?'}',
          if (d['doseNumber'] != null) 'dose ${d['doseNumber']}',
          if ((d['batchNumber'] ?? d['batchNo'] ?? '').toString().isNotEmpty)
            'batch ${d['batchNumber'] ?? d['batchNo']}',
        ].join(' · '),
      RecordType.healthObservation => [
          if (d['temperatureC'] != null) '${d['temperatureC']} °C',
          if ((d['symptoms'] ?? '').toString().isNotEmpty) d['symptoms'],
          if ((d['observation'] ?? '').toString().isNotEmpty) d['observation'],
        ].join(' · '),
    };

/// herd-health reason/problem codes -> Vietnamese explanation for the field user.
const _reasonLabels = <String, String>{
  'ACCESS_DENIED': 'No permission for this animal (out of scope or access changed)',
  'RESOURCE_VERSION_CHANGED': 'Animal record changed after capture – needs reconciliation',
  'CUSTODY_CHANGED': 'Animal moved barn/farm while sending – needs reconciliation',
  'SCHEDULE_ALREADY_COMPLETED': 'This scheduled dose was already recorded',
  'SCHEDULE_NOT_ACTIVE': 'Vaccination schedule is no longer active',
  'IDEMPOTENCY_KEY_REUSED': 'Intent ID was already used with different content',
  'CORRECTION_TARGET_CHANGED': 'The record being corrected has changed',
  'CATTLE_INACTIVE': 'Animal is no longer active',
  'INVALID_INPUT': 'Submitted data is invalid',
};

String reasonText(String? code) {
  if (code == null || code.isEmpty) return '–';
  final label = _reasonLabels[code];
  return label == null ? code : '$label ($code)';
}

void showSnack(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
