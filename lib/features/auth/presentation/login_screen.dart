import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config.dart';
import '../../../providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _user = TextEditingController(text: 'bs.demo');
  final _pass = TextEditingController(text: 'bs-local');

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final isDemo = session.mode == AppMode.demo;
    return Scaffold(
      appBar: AppBar(title: const Text('VinaBeef – Sign in')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Record vaccinations / health checks at the barn',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          SegmentedButton<AppMode>(
            segments: const [
              ButtonSegment(value: AppMode.demo, label: Text('Demo'), icon: Icon(Icons.science)),
              ButtonSegment(value: AppMode.live, label: Text('Live'), icon: Icon(Icons.cloud)),
            ],
            selected: {session.mode},
            onSelectionChanged: session.busy ? null : (s) => session.setMode(s.first),
          ),
          const SizedBox(height: 8),
          Text(session.mode.label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          if (isDemo) ...[
            TextField(
              controller: _user,
              decoration: const InputDecoration(labelText: 'Username', helperText: 'bs.demo / fm.demo'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _pass,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password', helperText: 'bs-local / fm-local'),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: session.busy
                  ? null
                  : () => session.login(username: _user.text, password: _pass.text),
              icon: const Icon(Icons.login),
              label: const Text('Sign in (simulated)'),
            ),
          ] else ...[
            Text('Issuer: ${AppConfig.oidcIssuer}\nAPI: ${AppConfig.apiBaseUrl}',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            const Text('Android emulator: run `adb reverse tcp:8080 tcp:8080 && adb reverse tcp:8081 tcp:8081` first.'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: session.busy ? null : () => session.login(),
              icon: const Icon(Icons.lock_open),
              label: const Text('Sign in with Keycloak'),
            ),
          ],
          if (session.busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          if (session.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(session.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
    );
  }
}
