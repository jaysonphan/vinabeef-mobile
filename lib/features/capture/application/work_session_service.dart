import '../../../core/canonical_json.dart';
import '../../../core/config.dart';
import '../domain/work_session.dart';
import 'ports.dart';

/// Prepares the offline capture window: online fetch of cattle in scope, cached with expiry.
class WorkSessionService {
  WorkSessionService({required this.directory, required this.store, required this.clock});

  final CattleDirectory directory;
  final WorkSessionStore store;
  final Clock clock;

  Future<WorkSession> prepare({required String mode, required String username}) async {
    final cattle = await directory.fetchScope();
    final now = clock();
    final session = WorkSession(
      username: username,
      preparedAt: now,
      expiresAt: now.add(AppConfig.workSessionTtl),
      cattle: cattle,
    );
    await store.save(mode, session);
    return session;
  }
}
