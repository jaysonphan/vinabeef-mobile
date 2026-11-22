import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../../../core/canonical_json.dart';
import '../../domain/cattle.dart';
import '../../domain/health_intent.dart';

/// DEMO ONLY – in-app stand-in for herd-health so the mobile flow can be shown without Docker.
/// It mirrors herd-health's observable contract (contracts/openapi/herd-health.v1.yaml and
/// HealthIntentService), with the same seed IDs/RFIDs as V2__health_demo_seed.sql plus two
/// extra demo-only cows in BARN-DL-01:
///  * actor from the token, never from the body; unknown body fields -> INVALID_INPUT
///  * 403 ACCESS_DENIED (not stored) when current grants do not cover the animal
///  * stale expectedVersion -> 409 NEEDS_REVIEW RESOURCE_VERSION_CHANGED (stored)
///  * completed scheduled dose -> 409 REJECTED SCHEDULE_ALREADY_COMPLETED (stored)
///  * same ID + same body -> stored receipt; same ID + other body -> IDEMPOTENCY_KEY_REUSED
///  * accepted record bumps the animal's resourceVersion
/// Nothing here is evidence for herd-health itself (coverage: demo only).
class SimUser {
  const SimUser({
    required this.username,
    required this.password,
    required this.displayName,
    required this.role,
    required this.farmId,
    this.barns,
  });

  final String username;
  final String password;
  final String displayName;
  final String role;
  final String farmId;

  /// Null = whole farm (FM).
  final Set<String>? barns;
}

class DemoLoginException implements Exception {
  const DemoLoginException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SimulatedHealthBackend {
  SimulatedHealthBackend._(this._db, this._clock);

  final Database _db;
  final Clock _clock;

  static const fileName = 'vinabeef_simulator.db';

  /// v2 = herd-health aligned seed. Demo data is simply recreated on upgrade.
  static const schemaVersion = 2;

  /// Same users/passwords as infra/oidc/realm and grants as authorization-grants.demo.json.
  static const users = <String, SimUser>{
    'bs.demo': SimUser(
        username: 'bs.demo',
        password: 'bs-local',
        displayName: 'Demo Veterinarian',
        role: 'BS',
        farmId: 'FARM-DL',
        barns: {'BARN-DL-01'}),
    'fm.demo': SimUser(
        username: 'fm.demo',
        password: 'fm-local',
        displayName: 'Farm Manager Demo',
        role: 'FM',
        farmId: 'FARM-DL'),
  };

  static const _allowedBodyFields = {
    'intentId', 'cattleId', 'rfid', 'type', 'payload', 'occurredAt', 'deviceRef', 'expectedVersion',
    'scheduleId', 'correctionOfRecordId', 'correctionReason',
  };

  /// Network between phone and server (demo switch).
  bool online = true;

  /// Commit the next submit, then drop its response (T06 "response lost").
  bool loseNextResponse = false;

  final Map<String, String> _tokens = {};
  int _tokenSeq = 0;

  static Future<SimulatedHealthBackend> open({DatabaseFactory? factory, String? path, Clock? clock}) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), fileName);
    final db = await f.openDatabase(dbPath,
        options: OpenDatabaseOptions(
          version: schemaVersion,
          onCreate: (db, _) => _createAndSeed(db),
          onUpgrade: (db, from, to) async {
            for (final t in ['sim_records', 'sim_receipts', 'sim_schedules', 'sim_cattle', 'sim_meta']) {
              await db.execute('DROP TABLE IF EXISTS $t');
            }
            await _createAndSeed(db);
          },
        ));
    return SimulatedHealthBackend._(db, clock ?? DateTime.now);
  }

  static Future<void> _createAndSeed(Database db) async {
    await db.execute('''
      CREATE TABLE sim_cattle (
        cattle_id TEXT PRIMARY KEY, rfid TEXT UNIQUE NOT NULL, name TEXT NOT NULL,
        farm_id TEXT NOT NULL, farm_name TEXT NOT NULL, barn_id TEXT NOT NULL,
        resource_version INTEGER NOT NULL, custody_version INTEGER NOT NULL)''');
    await db.execute('''
      CREATE TABLE sim_schedules (
        schedule_id TEXT PRIMARY KEY, cattle_id TEXT NOT NULL, vaccine_code TEXT NOT NULL,
        due_at TEXT NOT NULL, effective_record_id TEXT)''');
    await db.execute('''
      CREATE TABLE sim_receipts (
        intent_id TEXT PRIMARY KEY, body TEXT NOT NULL, actor TEXT NOT NULL, cattle_id TEXT NOT NULL,
        status TEXT NOT NULL, record_id TEXT, reason TEXT, current_version INTEGER NOT NULL,
        received_at INTEGER NOT NULL)''');
    await db.execute('''
      CREATE TABLE sim_records (
        record_id TEXT PRIMARY KEY, intent_id TEXT UNIQUE NOT NULL, cattle_id TEXT NOT NULL,
        record_version INTEGER NOT NULL, schedule_id TEXT, record_type TEXT NOT NULL,
        payload_json TEXT NOT NULL, occurred_at TEXT NOT NULL, recorded_at INTEGER NOT NULL,
        actor TEXT NOT NULL, origin_farm_id TEXT NOT NULL)''');
    await db.execute('CREATE TABLE sim_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)');

    Future<void> cow(String id, String rfid, String name, String farm, String farmName, String barn) =>
        db.insert('sim_cattle', {
          'cattle_id': id,
          'rfid': rfid,
          'name': name,
          'farm_id': farm,
          'farm_name': farmName,
          'barn_id': barn,
          'resource_version': 0,
          'custody_version': 0,
        });
    Future<void> dose(String id, String cattle, String vaccine, String due) => db.insert('sim_schedules',
        {'schedule_id': id, 'cattle_id': cattle, 'vaccine_code': vaccine, 'due_at': due});

    // Same as herd-health V2__health_demo_seed.sql
    await cow('10000000-0000-4000-8000-000000000001', 'RFID-DL-1001', 'Cow DL 1001', 'FARM-DL', 'Dak Lak', 'BARN-DL-01');
    await cow('10000000-0000-4000-8000-000000000002', 'RFID-DL-1002', 'Cow DL 1002', 'FARM-DL', 'Dak Lak', 'BARN-DL-02');
    await cow('10000000-0000-4000-8000-000000000003', 'RFID-GL-2001', 'Cow GL 2001', 'FARM-GL', 'Gia Lai', 'BARN-GL-01');
    await dose('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001',
        'FMD-BOOSTER', '2026-11-20T08:00:00Z');
    // Demo-only extras so multi-tag / offline batches have more than one cow in bs.demo's barn.
    await cow('10000000-0000-4000-8000-000000000011', 'RFID-DL-1011', 'Cow DL 1011', 'FARM-DL', 'Dak Lak', 'BARN-DL-01');
    await cow('10000000-0000-4000-8000-000000000012', 'RFID-DL-1012', 'Cow DL 1012', 'FARM-DL', 'Dak Lak', 'BARN-DL-01');
    await dose('20000000-0000-4000-8000-000000000011', '10000000-0000-4000-8000-000000000011',
        'LSD', '2026-12-05T08:00:00Z');
  }

  // ---------------- identity (token -> user) ----------------

  Future<String> issueToken(String username, String password) async {
    final u = users[username];
    if (u == null || u.password != password) {
      throw const DemoLoginException('Wrong username or password.');
    }
    if (!online) throw const DemoLoginException('No network – cannot sign in while offline.');
    final token = 'demo-${++_tokenSeq}-${_clock().microsecondsSinceEpoch}';
    _tokens[token] = username;
    return token;
  }

  void revokeToken(String? token) => _tokens.remove(token);

  /// Demo switch: every issued token expires now.
  void expireAllTokens() => _tokens.clear();

  Future<bool> isGrantRevoked(String username) async => (await _meta('revoked:$username')) == 'true';

  Future<void> setGrantRevoked(String username, bool revoked) =>
      _setMeta('revoked:$username', revoked ? 'true' : 'false');

  Future<String?> lastDemoUser() => _meta('last_user');

  Future<void> setLastDemoUser(String? username) async {
    if (username == null) {
      await _db.delete('sim_meta', where: 'key = ?', whereArgs: ['last_user']);
    } else {
      await _setMeta('last_user', username);
    }
  }

  SimUser _requireUser(String? token) {
    if (!online) {
      throw const TransientSyncFailure('Connection to server lost (simulated)', maybeDelivered: false);
    }
    final username = token == null ? null : _tokens[token];
    if (username == null) throw const AuthRequiredException();
    return users[username]!;
  }

  /// Same rule as access-policy VIEW_CATTLE / SUBMIT_HEALTH: BS = farm + listed barn, FM = farm.
  /// [revoked] is read before any transaction (sqflite must not touch the db inside a txn).
  static bool _mayAct(SimUser u, Cattle c, {required bool revoked}) {
    if (revoked) return false;
    if (u.role != 'BS' && u.role != 'FM') return false;
    return c.farmId == u.farmId && (u.barns == null || u.barns!.contains(c.barnId));
  }

  // ---------------- API surface ----------------

  /// GET /api/v1/cattle/in-scope
  Future<List<Cattle>> fetchScope(String? token) async {
    final u = _requireUser(token);
    final revoked = await isGrantRevoked(u.username);
    return (await allCattle()).where((c) => _mayAct(u, c, revoked: revoked)).toList();
  }

  /// POST /api/v1/health-intents
  Future<SubmitResult> submit(String? token, String body) async {
    final u = _requireUser(token);
    final Map<String, dynamic> m;
    try {
      m = Map<String, dynamic>.from(jsonDecode(body) as Map);
    } catch (_) {
      return const RejectedResult('INVALID_INPUT');
    }
    final intentId = m['intentId'];
    if (intentId is! String ||
        m.keys.any((k) => !_allowedBodyFields.contains(k)) ||
        m['cattleId'] is! String ||
        m['type'] is! String ||
        m['payload'] is! Map ||
        m['expectedVersion'] is! num ||
        DateTime.tryParse('${m['occurredAt']}') == null) {
      return const RejectedResult('INVALID_INPUT');
    }
    final canon = canonicalJson(m);
    final revoked = await isGrantRevoked(u.username);

    late SubmitResult result;
    await _db.transaction((txn) async {
      final existing =
          await txn.query('sim_receipts', where: 'intent_id = ?', whereArgs: [intentId], limit: 1);
      if (existing.isNotEmpty) {
        final r = existing.first;
        final cattle = await _cattle(txn, r['cattle_id'] as String);
        if (r['actor'] != u.username || cattle == null || !_mayAct(u, cattle, revoked: revoked)) {
          result = const RejectedResult('ACCESS_DENIED');
        } else if (r['body'] != canon) {
          result = const NeedsReviewResult('IDEMPOTENCY_KEY_REUSED');
        } else {
          result = _fromReceipt(r);
        }
        return;
      }
      result = await _decide(txn, u, m, canon, revoked: revoked);
    });

    if (loseNextResponse) {
      loseNextResponse = false;
      throw const TransientSyncFailure('Server processed the request but the response was lost (simulated)', maybeDelivered: true);
    }
    return result;
  }

  Future<SubmitResult> _decide(Transaction txn, SimUser u, Map<String, dynamic> m, String canon,
      {required bool revoked}) async {
    final cattle = await _cattle(txn, m['cattleId'] as String);
    // herd-health: unknown target or no current grant -> 403, nothing stored.
    if (cattle == null || !_mayAct(u, cattle, revoked: revoked)) return const RejectedResult('ACCESS_DENIED');

    final scheduleId = m['scheduleId'] as String?;
    if (scheduleId != null) {
      if (m['type'] != RecordType.vaccination.wire) return const RejectedResult('INVALID_INPUT');
      final s = await txn.query('sim_schedules', where: 'schedule_id = ?', whereArgs: [scheduleId], limit: 1);
      if (s.isEmpty || s.first['cattle_id'] != cattle.cattleId) return const RejectedResult('INVALID_INPUT');
    }

    final now = _clock();
    Future<SubmitResult> store(String status, String? reason, {String? recordId, int? version}) async {
      final v = version ?? cattle.resourceVersion;
      await txn.insert('sim_receipts', {
        'intent_id': m['intentId'],
        'body': canon,
        'actor': u.username,
        'cattle_id': cattle.cattleId,
        'status': status,
        'record_id': recordId,
        'reason': reason,
        'current_version': v,
        'received_at': now.millisecondsSinceEpoch,
      });
      return switch (status) {
        'ACCEPTED' => AcceptedResult(recordId: recordId!, committedAt: now, currentVersion: v),
        'NEEDS_REVIEW' => NeedsReviewResult(reason!),
        _ => RejectedResult(reason!),
      };
    }

    if ((m['expectedVersion'] as num).toInt() != cattle.resourceVersion) {
      return store('NEEDS_REVIEW', 'RESOURCE_VERSION_CHANGED');
    }
    if (scheduleId != null) {
      final s = await txn.query('sim_schedules', where: 'schedule_id = ?', whereArgs: [scheduleId], limit: 1);
      if (s.first['effective_record_id'] != null) return store('REJECTED', 'SCHEDULE_ALREADY_COMPLETED');
    }

    final nextVersion = cattle.resourceVersion + 1;
    final count = Sqflite.firstIntValue(await txn.rawQuery('SELECT COUNT(*) FROM sim_records')) ?? 0;
    final recordId = 'sim-record-${(count + 1).toString().padLeft(5, '0')}';
    await txn.insert('sim_records', {
      'record_id': recordId,
      'intent_id': m['intentId'],
      'cattle_id': cattle.cattleId,
      'record_version': nextVersion,
      'schedule_id': scheduleId,
      'record_type': m['type'],
      'payload_json': jsonEncode(m['payload']),
      'occurred_at': m['occurredAt'],
      'recorded_at': now.millisecondsSinceEpoch,
      'actor': u.username,
      'origin_farm_id': cattle.farmId,
    });
    await txn.update('sim_cattle', {'resource_version': nextVersion},
        where: 'cattle_id = ?', whereArgs: [cattle.cattleId]);
    if (scheduleId != null) {
      await txn.update('sim_schedules', {'effective_record_id': recordId},
          where: 'schedule_id = ?', whereArgs: [scheduleId]);
    }
    return store('ACCEPTED', null, recordId: recordId, version: nextVersion);
  }

  SubmitResult _fromReceipt(Map<String, Object?> r) => switch (r['status']) {
        'ACCEPTED' => AcceptedResult(
            recordId: r['record_id'] as String,
            committedAt: DateTime.fromMillisecondsSinceEpoch(r['received_at'] as int),
            currentVersion: r['current_version'] as int),
        'NEEDS_REVIEW' => NeedsReviewResult((r['reason'] ?? '') as String),
        _ => RejectedResult((r['reason'] ?? '') as String),
      };

  /// GET /api/v1/health-intents/{id} – 404 (null) when unknown or not visible.
  Future<SubmitResult?> readReceipt(String? token, String intentId) async {
    final u = _requireUser(token);
    final rows = await _db.query('sim_receipts', where: 'intent_id = ?', whereArgs: [intentId], limit: 1);
    if (rows.isEmpty) return null;
    final cattle = await _cattle(_db, rows.first['cattle_id'] as String);
    final revoked = await isGrantRevoked(u.username);
    if (rows.first['actor'] != u.username || cattle == null || !_mayAct(u, cattle, revoked: revoked)) {
      return null;
    }
    return _fromReceipt(rows.first);
  }

  /// GET /api/v1/cattle/{id}/health-history – records the caller may read (empty otherwise).
  Future<List<HealthRecord>> history(String? token, String cattleId) async {
    final u = _requireUser(token);
    final cattle = await _cattle(_db, cattleId);
    final revoked = await isGrantRevoked(u.username);
    if (cattle == null || !_mayAct(u, cattle, revoked: revoked)) return const [];
    final recs = await _db.query('sim_records',
        where: 'cattle_id = ?', whereArgs: [cattleId], orderBy: 'record_version DESC');
    return recs
        .map((r) => HealthRecord(
              recordId: r['record_id'] as String,
              intentId: r['intent_id'] as String,
              recordType: RecordType.fromWire(r['record_type'] as String),
              details: Map<String, dynamic>.from(jsonDecode(r['payload_json'] as String) as Map),
              occurredAt: DateTime.parse(r['occurred_at'] as String),
              committedAt: DateTime.fromMillisecondsSinceEpoch(r['recorded_at'] as int),
              actor: r['actor'] as String,
              scheduleId: r['schedule_id'] as String?,
            ))
        .toList();
  }

  // ---------------- demo controls / inspection ----------------

  Future<List<Cattle>> allCattle() async {
    final rows = await _db.query('sim_cattle', orderBy: 'farm_id, barn_id, rfid');
    return [for (final r in rows) await _toCattle(_db, r)];
  }

  /// Moves a cow between BARN-DL-01 and BARN-DL-02 (custody change before sync).
  Future<Cattle> toggleCustody(String cattleId) async {
    final c = (await _cattle(_db, cattleId))!;
    final newBarn = c.barnId == 'BARN-DL-01' ? 'BARN-DL-02' : 'BARN-DL-01';
    await _db.update('sim_cattle', {'barn_id': newBarn, 'custody_version': c.custodyVersion + 1},
        where: 'cattle_id = ?', whereArgs: [cattleId]);
    return (await _cattle(_db, cattleId))!;
  }

  Future<int> recordCount() async =>
      Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM sim_records')) ?? 0;

  Future<int> receiptCount() async =>
      Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM sim_receipts')) ?? 0;

  Future<Cattle?> _cattle(DatabaseExecutor db, String cattleId) async {
    final rows = await db.query('sim_cattle', where: 'cattle_id = ?', whereArgs: [cattleId], limit: 1);
    return rows.isEmpty ? null : _toCattle(db, rows.first);
  }

  static Future<Cattle> _toCattle(DatabaseExecutor db, Map<String, Object?> r) async {
    final open = await db.query('sim_schedules',
        where: 'cattle_id = ? AND effective_record_id IS NULL', whereArgs: [r['cattle_id']], orderBy: 'due_at');
    return Cattle(
      cattleId: r['cattle_id'] as String,
      rfid: r['rfid'] as String,
      name: r['name'] as String,
      farmId: r['farm_id'] as String,
      farmName: r['farm_name'] as String,
      barnId: r['barn_id'] as String,
      resourceVersion: r['resource_version'] as int,
      custodyVersion: r['custody_version'] as int,
      schedules: [
        for (final s in open)
          VaccinationSchedule(
            scheduleId: s['schedule_id'] as String,
            vaccineCode: s['vaccine_code'] as String,
            dueDate: s['due_at'] as String,
          ),
      ],
    );
  }

  Future<String?> _meta(String key) async {
    final rows = await _db.query('sim_meta', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> _setMeta(String key, String value) =>
      _db.insert('sim_meta', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> close() => _db.close();
}
