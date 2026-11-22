import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'features/auth/presentation/session_controller.dart';
import 'features/capture/data/fake_tag_read_source.dart';
import 'features/capture/data/local_database.dart';
import 'features/capture/data/simulator/simulated_health_backend.dart';
import 'features/capture/data/sqlite_draft_store.dart';
import 'features/capture/data/sqlite_work_session_store.dart';
import 'features/capture/presentation/outbox_controller.dart';
import 'providers.dart';

/// Composition root: open durable stores, wire adapters to ports, start the sync loop.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final localDb = await LocalDatabase.open();
  final simulator = await SimulatedHealthBackend.open();
  final readerId = await localDb.deviceReaderId();

  final session = SessionController(
    localDb: localDb,
    simulator: simulator,
    workSessions: SqliteWorkSessionStore(localDb.db),
  );
  await session.init();

  final outbox = OutboxController(
    session: session,
    store: SqliteDraftStore(localDb.db),
    deviceId: readerId,
  );
  await outbox.refresh();
  outbox.start();

  final reader = FakeTagReadSource(readerId: readerId, seqStore: localDb);

  runApp(ProviderScope(
    overrides: [
      sessionProvider.overrideWith((ref) => session),
      outboxProvider.overrideWith((ref) => outbox),
      tagReaderProvider.overrideWithValue(reader),
      simulatorProvider.overrideWithValue(simulator),
    ],
    child: const VinaBeefApp(),
  ));
}
