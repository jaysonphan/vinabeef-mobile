import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers.dart';
import '../domain/cattle.dart';
import 'widgets.dart';

/// Demo-only fault switches for the in-app simulated server (T05/T06/T07/T09 walkthroughs).
class SimulatorPanel extends ConsumerStatefulWidget {
  const SimulatorPanel({super.key});

  @override
  ConsumerState<SimulatorPanel> createState() => _SimulatorPanelState();
}

class _SimulatorPanelState extends ConsumerState<SimulatorPanel> {
  int _records = 0;
  int _receipts = 0;
  List<Cattle> _cattle = const [];
  bool _revoked = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final sim = ref.read(simulatorProvider);
    final user = ref.read(sessionProvider).principal?.username;
    final records = await sim.recordCount();
    final receipts = await sim.receiptCount();
    final cattle = await sim.allCattle();
    final revoked = user == null ? false : await sim.isGrantRevoked(user);
    if (!mounted) return;
    setState(() {
      _records = records;
      _receipts = receipts;
      _cattle = cattle;
      _revoked = revoked;
    });
  }

  @override
  Widget build(BuildContext context) {
    final sim = ref.watch(simulatorProvider);
    final session = ref.watch(sessionProvider);
    // Rebuild counters when the outbox changes (after a sync).
    ref.listen(outboxProvider, (_, __) => _reload());
    final user = session.principal?.username;

    return Card(
      color: Colors.deepPurple.shade50,
      child: ExpansionTile(
        leading: const Icon(Icons.science),
        title: const Text('Simulated server (Demo)'),
        subtitle: Text('Server: $_records records · $_receipts receipts · network ${sim.online ? 'ON' : 'OFF'}'),
        childrenPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: [
          SwitchListTile(
            title: const Text('Phone ↔ server network'),
            subtitle: const Text('Turn off to record offline (stays PENDING_SYNC)'),
            value: sim.online,
            onChanged: (v) => setState(() => sim.online = v),
          ),
          SwitchListTile(
            title: const Text('Lose the next response'),
            subtitle: const Text('Server commits but the app never gets the result (T06)'),
            value: sim.loseNextResponse,
            onChanged: (v) => setState(() => sim.loseNextResponse = v),
          ),
          if (user != null)
            SwitchListTile(
              title: Text('Revoke access for $user'),
              subtitle: const Text('Server rejects on sync; the draft is kept (T07)'),
              value: _revoked,
              onChanged: (v) async {
                await sim.setGrantRevoked(user, v);
                await _reload();
              },
            ),
          ListTile(
            leading: const Icon(Icons.timer_off_outlined),
            title: const Text('Expire token'),
            subtitle: const Text('Pending items are kept; the app asks to sign in again'),
            onTap: () {
              sim.expireAllTokens();
              showSnack(context, 'Token expired (simulated).');
            },
          ),
          const Divider(),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Move custody on server (BARN-DL-01 ↔ BARN-DL-02):', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          for (final c in _cattle.where((c) => c.farmId == 'FARM-DL'))
            ListTile(
              dense: true,
              title: Text('${c.name} · ${c.rfid}'),
              subtitle: Text('${c.location} · custody v${c.custodyVersion} · record v${c.resourceVersion}'),
              trailing: TextButton(
                onPressed: () async {
                  final moved = await sim.toggleCustody(c.cattleId);
                  await _reload();
                  if (context.mounted) showSnack(context, '${moved.name} → ${moved.location}');
                },
                child: const Text('Move'),
              ),
            ),
        ],
      ),
    );
  }
}
