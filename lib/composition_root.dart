import 'core/config.dart';
import 'features/auth/data/demo_auth_session.dart';
import 'features/auth/data/keycloak_auth_session.dart';
import 'features/auth/domain/auth_session.dart';
import 'features/capture/application/ports.dart';
import 'features/capture/data/http_health_api.dart';
import 'features/capture/data/simulator/simulated_health_api.dart';
import 'features/capture/data/simulator/simulated_health_backend.dart';

/// Ports bound for one mode. The only place that knows concrete adapters (DIP).
class Dependencies {
  const Dependencies({
    required this.auth,
    required this.directory,
    required this.submitter,
    required this.receipts,
    required this.history,
  });

  final AuthSession auth;
  final CattleDirectory directory;
  final HealthSubmitter submitter;
  final ReceiptReader receipts;
  final HistoryReader history;
}

Dependencies buildDependencies(AppMode mode, SimulatedHealthBackend simulator) {
  switch (mode) {
    case AppMode.demo:
      final auth = DemoAuthSession(simulator);
      final api = SimulatedHealthApi(simulator, auth);
      return Dependencies(auth: auth, directory: api, submitter: api, receipts: api, history: api);
    case AppMode.live:
      final auth = KeycloakAuthSession();
      final api = HttpHealthApi(baseUrl: AppConfig.apiBaseUrl, auth: auth);
      return Dependencies(auth: auth, directory: api, submitter: api, receipts: api, history: api);
  }
}
