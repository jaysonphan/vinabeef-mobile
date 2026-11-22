import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/auth/presentation/session_controller.dart';
import 'features/capture/data/fake_tag_read_source.dart';
import 'features/capture/data/simulator/simulated_health_backend.dart';
import 'features/capture/presentation/outbox_controller.dart';

// Instances are created in main() (composition root) and injected via overrides.
final sessionProvider = ChangeNotifierProvider<SessionController>(
    (ref) => throw UnimplementedError('override sessionProvider in main()'));

final outboxProvider = ChangeNotifierProvider<OutboxController>(
    (ref) => throw UnimplementedError('override outboxProvider in main()'));

final tagReaderProvider =
    Provider<FakeTagReadSource>((ref) => throw UnimplementedError('override tagReaderProvider'));

final simulatorProvider =
    Provider<SimulatedHealthBackend>((ref) => throw UnimplementedError('override simulatorProvider'));
