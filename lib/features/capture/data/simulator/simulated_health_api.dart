import '../../../auth/domain/auth_session.dart';
import '../../application/ports.dart';
import '../../domain/cattle.dart';
import '../../domain/health_intent.dart';
import 'simulated_health_backend.dart';

/// Same ports as [HttpHealthApi] but backed by the in-app simulator (LSP: identical
/// outcome/exception semantics, so the application layer cannot tell them apart).
class SimulatedHealthApi implements CattleDirectory, HealthSubmitter, ReceiptReader, HistoryReader {
  SimulatedHealthApi(this._sim, this._auth);

  final SimulatedHealthBackend _sim;
  final AuthSession _auth;

  Future<String?> _token() async {
    final t = await _auth.accessToken();
    if (t == null) {
      _auth.markNeedsReauth();
      throw const AuthRequiredException();
    }
    return t;
  }

  Future<T> _guard<T>(Future<T> Function(String? token) call) async {
    final token = await _token();
    try {
      return await call(token);
    } on AuthRequiredException {
      _auth.markNeedsReauth();
      rethrow;
    }
  }

  @override
  Future<List<Cattle>> fetchScope() => _guard(_sim.fetchScope);

  @override
  Future<SubmitResult> submit(String intentId, String body) => _guard((t) => _sim.submit(t, body));

  @override
  Future<SubmitResult?> readReceipt(String intentId) => _guard((t) => _sim.readReceipt(t, intentId));

  @override
  Future<List<HealthRecord>> history(String cattleId) => _guard((t) => _sim.history(t, cattleId));
}
