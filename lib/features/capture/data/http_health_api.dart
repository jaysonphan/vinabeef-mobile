import 'dart:convert';

import 'package:dio/dio.dart';

import '../../auth/domain/auth_session.dart';
import '../application/ports.dart';
import '../domain/cattle.dart';
import '../domain/health_intent.dart';

/// Adapter to herd-health (owner: Khánh) – contracts/openapi/herd-health.v1.yaml:
///   GET  /api/v1/cattle/in-scope                 cattle the caller may view + open doses (work session)
///   POST /api/v1/health-intents                  submit immutable intent (201 new, 200 replay, 409 + receipt)
///   GET  /api/v1/health-intents/{intentId}       receipt (404 = unknown or not visible)
///   GET  /api/v1/cattle/{cattleId}/health-history
/// Errors are application/problem+json `{status, code, detail, receipt?}`.
class HttpHealthApi implements CattleDirectory, HealthSubmitter, ReceiptReader, HistoryReader {
  HttpHealthApi({required String baseUrl, required AuthSession auth, Dio? dio})
      : _auth = auth,
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 5),
              sendTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              contentType: Headers.jsonContentType,
              responseType: ResponseType.plain,
              validateStatus: (_) => true,
            ));

  final AuthSession _auth;
  final Dio _dio;

  Future<Response<String>> _send(
    Future<Response<String>> Function(Options options) call, {
    required bool mutating,
  }) async {
    final token = await _auth.accessToken();
    if (token == null) {
      _auth.markNeedsReauth();
      throw const AuthRequiredException();
    }
    final options = Options(headers: {'Authorization': 'Bearer $token'});
    final Response<String> resp;
    try {
      resp = await call(options);
    } on DioException catch (e) {
      // Connection never established -> certainly not delivered.
      final delivered = mutating &&
          e.type != DioExceptionType.connectionError &&
          e.type != DioExceptionType.connectionTimeout &&
          e.type != DioExceptionType.cancel;
      throw TransientSyncFailure('Cannot reach the server (${e.type.name})',
          maybeDelivered: delivered);
    }
    if (resp.statusCode == 401) {
      _auth.markNeedsReauth();
      throw const AuthRequiredException();
    }
    return resp;
  }

  static Object? _json(Response<String> r) {
    final data = r.data;
    if (data == null || data.isEmpty) return null;
    try {
      return jsonDecode(data);
    } catch (_) {
      return null;
    }
  }

  /// Problem `code` (e.g. ACCESS_DENIED) is the stable, user-translatable reason.
  static String _reason(Object? body, int? status) {
    if (body is Map) {
      final r = body['code'] ?? body['reasonCode'] ?? body['detail'] ?? body['title'];
      if (r != null) return r.toString();
    }
    return 'HTTP $status';
  }

  /// Maps a herd-health HealthReceipt (`status`, `recordId`, `currentVersion`, `reasonCode`).
  static SubmitResult _fromReceipt(Map receipt, {String? fallbackCode}) {
    final status = (receipt['status'] ?? '').toString();
    final reason = (receipt['reasonCode'] ?? fallbackCode ?? status).toString();
    switch (status) {
      case 'ACCEPTED':
        return AcceptedResult(
          recordId: (receipt['recordId'] ?? '?').toString(),
          committedAt: DateTime.tryParse('${receipt['receivedAt']}') ?? DateTime.now(),
          currentVersion: (receipt['currentVersion'] as num?)?.toInt(),
        );
      case 'REJECTED':
        return RejectedResult(reason);
      case 'NEEDS_REVIEW':
        return NeedsReviewResult(reason);
      default:
        // Anything else is not a final clinical outcome; keep pending and ask again later.
        throw TransientSyncFailure('Server has no final outcome yet ($status)', maybeDelivered: true);
    }
  }

  SubmitResult _resultFrom(Response<String> resp, {required bool isSubmit}) {
    final code = resp.statusCode ?? 0;
    final body = _json(resp);
    if (code >= 200 && code < 300 && body is Map) return _fromReceipt(body);
    if (code == 409) {
      // Durable conflict carries its receipt (NEEDS_REVIEW or REJECTED, e.g. SCHEDULE_ALREADY_COMPLETED).
      // IDEMPOTENCY_KEY_REUSED has no receipt: same ID, different body -> needs review.
      final receipt = body is Map ? body['receipt'] : null;
      if (receipt is Map) return _fromReceipt(receipt, fallbackCode: _reason(body, code));
      return NeedsReviewResult(_reason(body, code));
    }
    // 403: current grant denies (out of scope, revoked, custody moved). 422: invalid body.
    if (code == 403 || code == 400 || code == 422) return RejectedResult(_reason(body, code));
    if (code == 404 && isSubmit) {
      throw const TransientSyncFailure('Health API endpoint not available (404)', maybeDelivered: false);
    }
    // 503 = grant/policy authority unavailable (nothing committed); 5xx = unknown -> ask receipt.
    throw TransientSyncFailure('Temporary server error (HTTP $code)', maybeDelivered: isSubmit && code != 503);
  }

  @override
  Future<SubmitResult> submit(String intentId, String body) async {
    final resp = await _send(
      (o) => _dio.post<String>('/api/v1/health-intents', data: body, options: o),
      mutating: true,
    );
    return _resultFrom(resp, isSubmit: true);
  }

  @override
  Future<SubmitResult?> readReceipt(String intentId) async {
    final resp = await _send(
      (o) => _dio.get<String>('/api/v1/health-intents/${Uri.encodeComponent(intentId)}', options: o),
      mutating: false,
    );
    if (resp.statusCode == 404) return null;
    return _resultFrom(resp, isSubmit: false);
  }

  @override
  Future<List<Cattle>> fetchScope() async {
    final resp =
        await _send((o) => _dio.get<String>('/api/v1/cattle/in-scope', options: o), mutating: false);
    final code = resp.statusCode ?? 0;
    final body = _json(resp);
    if (code == 403) throw AccessDeniedException(_reason(body, code));
    if (code != 200) {
      throw TransientSyncFailure('Could not load cattle list (HTTP $code)', maybeDelivered: false);
    }
    final list = body is Map ? (body['items'] ?? body['content'] ?? const []) : body;
    return (list as List).map((e) => Cattle.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  @override
  Future<List<HealthRecord>> history(String cattleId) async {
    final resp = await _send(
      (o) => _dio.get<String>('/api/v1/cattle/${Uri.encodeComponent(cattleId)}/health-history',
          options: o),
      mutating: false,
    );
    final code = resp.statusCode ?? 0;
    final body = _json(resp);
    if (code == 403) throw AccessDeniedException(_reason(body, code));
    if (code != 200) {
      throw TransientSyncFailure('Could not load history (HTTP $code)', maybeDelivered: false);
    }
    final list = body is Map ? (body['records'] ?? body['items'] ?? const []) : body;
    return (list as List)
        .map((e) => HealthRecord.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}
