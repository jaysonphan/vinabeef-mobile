import 'dart:convert';

/// Clock injected everywhere a timestamp is taken, so tests can control time.
typedef Clock = DateTime Function();

/// JSON with recursively sorted keys. The submitted body of an intent is stored in this
/// form once and never rebuilt, so every retry sends byte-identical content under the same ID.
String canonicalJson(Object? value) => jsonEncode(_canon(value));

Object? _canon(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((k) => k.toString()).toList()..sort();
    return <String, Object?>{for (final k in keys) k: _canon(value[k])};
  }
  if (value is List) return value.map(_canon).toList();
  return value;
}

String isoUtc(DateTime t) => t.toUtc().toIso8601String();
