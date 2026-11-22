import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config.dart';
import '../../../providers.dart';
import '../../auth/presentation/session_controller.dart';
import '../domain/health_intent.dart';
import 'intent_detail_screen.dart';
import 'scan_screen.dart';
import 'simulator_panel.dart';
import 'widgets.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final outbox = ref.watch(outboxProvider);
    final p = session.principal!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('VinaBeef at the barn'),
        actions: [
          IconButton(
            tooltip: 'Sync now',
            onPressed: outbox.syncing
                ? null
                : () async {
                    final r = await outbox.syncNow();
                    if (context.mounted) {
                      showSnack(context,
                          r?.summary() ?? (session.needsReauth ? 'Sign in again to sync.' : 'Syncing…'));
                    }
                  },
            icon: outbox.syncing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => _confirmLogout(context, session, outbox.count(IntentStatus.pendingSync)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: session.captureAllowed
            ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ScanScreen()))
            : null,
        backgroundColor: session.captureAllowed ? null : Colors.grey.shade400,
        icon: const Icon(Icons.nfc),
        label: const Text('Scan RFID'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await outbox.syncNow();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          children: [
            _UserCard(session: session),
            if (session.needsReauth) _ReauthBanner(session: session),
            _WorkSessionCard(session: session),
            if (session.error != null)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: Text(session.error!),
                  trailing: IconButton(icon: const Icon(Icons.close), onPressed: session.clearError),
                ),
              ),
            _SyncCard(
              summary: outbox.lastReport?.summary(),
              lastSyncAt: outbox.lastSyncAt,
              counts: {for (final s in IntentStatus.values) s: outbox.count(s)},
            ),
            if (session.mode == AppMode.demo) const SimulatorPanel(),
            const SizedBox(height: 8),
            Text('Records on this device (${outbox.intents.length})',
                style: Theme.of(context).textTheme.titleMedium),
            if (outbox.intents.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No records yet. Prepare a work session, then tap "Scan RFID".',
                    textAlign: TextAlign.center),
              ),
            for (final i in outbox.intents)
              Card(
                child: ListTile(
                  leading: Icon(statusIcon(i.status), color: statusColor(i.status)),
                  title: Text('${i.recordType.label} · ${i.cattleLabel}'),
                  subtitle: Text([
                    describeDetails(i.recordType, i.details),
                    'Performed: ${fmtTime(i.occurredAt)}',
                    if (i.status == IntentStatus.pendingSync && i.lastError != null)
                      'Attempt ${i.attempts}: ${i.lastError}${i.outcomeUnknown ? ' (outcome unknown)' : ''}',
                    if (i.reason != null) 'Reason: ${reasonText(i.reason)}',
                  ].join('\n')),
                  isThreeLine: true,
                  trailing: IntentStatusChip(i.status),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => IntentDetailScreen(localId: i.localId!),
                  )),
                ),
              ),
            Text('Owner: ${p.username} · Mode: ${session.mode.key}',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, SessionController session, int pending) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: Text(pending == 0
            ? 'The cached cattle list will be removed from this device.'
            : '$pending record(s) are still pending sync. They are KEPT on this device and will be sent when you sign in again. '
                'The cached cattle list will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (ok == true) await session.logout();
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({required this.session});
  final SessionController session;

  @override
  Widget build(BuildContext context) {
    final p = session.principal!;
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person)),
        title: Text('${p.displayName} (${p.username})'),
        subtitle: Text('Roles: ${p.roles.isEmpty ? '–' : p.roles.join(', ')}\n${session.mode.label}'),
        isThreeLine: true,
      ),
    );
  }
}

class _ReauthBanner extends StatelessWidget {
  const _ReauthBanner({required this.session});
  final SessionController session;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.amber.shade100,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Your session has expired',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const Text('Pending records are still kept on this device. Sign in again to send them.'),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: session.busy ? null : () => _relogin(context),
            child: const Text('Sign in again'),
          ),
        ]),
      ),
    );
  }

  Future<void> _relogin(BuildContext context) async {
    if (session.mode == AppMode.live) {
      await session.login();
      return;
    }
    final pass = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Sign in again: ${session.principal!.username}'),
        content: TextField(
          controller: pass,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Password'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, pass.text), child: const Text('Sign in')),
        ],
      ),
    );
    if (password != null) {
      await session.login(username: session.principal!.username, password: password);
    }
  }
}

class _WorkSessionCard extends StatelessWidget {
  const _WorkSessionCard({required this.session});
  final SessionController session;

  @override
  Widget build(BuildContext context) {
    final ws = session.workSession;
    final valid = session.captureAllowed;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(valid ? Icons.lock_open : Icons.lock_outline,
                color: valid ? Colors.green.shade700 : Colors.grey),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                valid
                    ? 'Work session: ${ws!.cattle.length} animal(s) in scope · expires ${fmtTime(ws.expiresAt)}'
                    : ws == null
                        ? 'No work session yet – recording is not possible.'
                        : 'Work session expired or belongs to another user – recording is locked.',
              ),
            ),
          ]),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: session.busy
                ? null
                : () async {
                    final ok = await session.prepareWorkSession();
                    if (context.mounted && ok) showSnack(context, 'Cattle in scope downloaded.');
                  },
            icon: const Icon(Icons.download),
            label: Text(ws == null ? 'Prepare session (needs network)' : 'Refresh session (needs network)'),
          ),
        ]),
      ),
    );
  }
}

class _SyncCard extends StatelessWidget {
  const _SyncCard({required this.summary, required this.lastSyncAt, required this.counts});
  final String? summary;
  final DateTime? lastSyncAt;
  final Map<IntentStatus, int> counts;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in counts.entries)
              if (e.value > 0) Chip(
                visualDensity: VisualDensity.compact,
                avatar: Icon(statusIcon(e.key), size: 16, color: statusColor(e.key)),
                label: Text('${e.key.label}: ${e.value}'),
              ),
          ]),
          const SizedBox(height: 4),
          Text('Last sync: ${fmtTime(lastSyncAt)}${summary == null ? '' : ' — $summary'}',
              style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }
}
