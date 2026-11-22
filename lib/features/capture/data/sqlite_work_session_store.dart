import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../application/ports.dart';
import '../domain/cattle.dart';
import '../domain/work_session.dart';

class SqliteWorkSessionStore implements WorkSessionStore {
  SqliteWorkSessionStore(this._db);

  final Database _db;

  @override
  Future<WorkSession?> load(String mode) async {
    final rows = await _db.query('work_session', where: 'mode = ?', whereArgs: [mode], limit: 1);
    if (rows.isEmpty) return null;
    final r = rows.first;
    final list = jsonDecode(r['cattle_json'] as String) as List;
    return WorkSession(
      username: r['username'] as String,
      preparedAt: DateTime.fromMillisecondsSinceEpoch(r['prepared_at'] as int),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(r['expires_at'] as int),
      cattle: list.map((e) => Cattle.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
    );
  }

  @override
  Future<void> save(String mode, WorkSession session) => _db.insert(
        'work_session',
        {
          'mode': mode,
          'username': session.username,
          'prepared_at': session.preparedAt.millisecondsSinceEpoch,
          'expires_at': session.expiresAt.millisecondsSinceEpoch,
          'cattle_json': jsonEncode(session.cattle.map((c) => c.toJson()).toList()),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  @override
  Future<void> clear(String mode) => _db.delete('work_session', where: 'mode = ?', whereArgs: [mode]);
}
