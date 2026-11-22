import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'fake_tag_read_source.dart';

/// On-device SQLite (sqflite). Survives process kill / restart.
/// Schema is versioned; add migrations in [_onUpgrade] when it changes.
class LocalDatabase implements ReaderSeqStore {
  LocalDatabase._(this.db);

  final Database db;

  static const fileName = 'vinabeef_local.db';
  static const schemaVersion = 1;

  static Future<LocalDatabase> open({DatabaseFactory? factory, String? path}) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), fileName);
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onCreate: (db, version) async {
          for (final stmt in _schemaV1) {
            await db.execute(stmt);
          }
        },
        onUpgrade: _onUpgrade,
      ),
    );
    return LocalDatabase._(db);
  }

  static Future<void> _onUpgrade(Database db, int from, int to) async {
    // v1 is the first released schema. Future: if (from < 2) { ALTER TABLE ... }
  }

  static const _schemaV1 = <String>[
    '''
    CREATE TABLE intents (
      local_id INTEGER PRIMARY KEY AUTOINCREMENT,
      mode TEXT NOT NULL,
      owner TEXT NOT NULL,
      intent_id TEXT UNIQUE,
      status TEXT NOT NULL,
      cattle_id TEXT NOT NULL,
      rfid TEXT NOT NULL,
      cattle_label TEXT NOT NULL,
      record_type TEXT NOT NULL,
      details_json TEXT NOT NULL,
      schedule_id TEXT,
      expected_custody_version INTEGER NOT NULL,
      reader_observation_id TEXT,
      occurred_at INTEGER NOT NULL,
      captured_at INTEGER NOT NULL,
      submitted_body TEXT,
      submitted_at INTEGER,
      last_attempt_at INTEGER,
      committed_at INTEGER,
      attempts INTEGER NOT NULL DEFAULT 0,
      outcome_unknown INTEGER NOT NULL DEFAULT 0,
      server_record_id TEXT,
      reason TEXT,
      last_error TEXT
    )
    ''',
    'CREATE INDEX idx_intents_queue ON intents(mode, owner, status, submitted_at)',
    '''
    CREATE TABLE work_session (
      mode TEXT PRIMARY KEY,
      username TEXT NOT NULL,
      prepared_at INTEGER NOT NULL,
      expires_at INTEGER NOT NULL,
      cattle_json TEXT NOT NULL
    )
    ''',
    'CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
  ];

  Future<String?> getMeta(String key) async {
    final rows = await db.query('meta', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setMeta(String key, String value) => db.insert(
        'meta',
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  /// Provisioned reader identity of this phone, e.g. MOB-1A2B3C4D (TagObservation.readerId).
  Future<String> deviceReaderId() async {
    final existing = await getMeta('reader_id');
    if (existing != null) return existing;
    final id = 'MOB-${const Uuid().v4().replaceAll('-', '').substring(0, 8).toUpperCase()}';
    await setMeta('reader_id', id);
    return id;
  }

  /// Monotonic per reader, persisted so it keeps increasing across restarts.
  @override
  Future<int> nextReaderSeq() async {
    return db.transaction((txn) async {
      final rows = await txn.query('meta', where: 'key = ?', whereArgs: ['reader_seq']);
      final next = rows.isEmpty ? 1 : int.parse(rows.first['value'] as String) + 1;
      await txn.insert('meta', {'key': 'reader_seq', 'value': '$next'},
          conflictAlgorithm: ConflictAlgorithm.replace);
      return next;
    });
  }
}
