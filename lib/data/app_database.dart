import 'dart:convert';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// SQLite foundation for Khadamat Fanni Hosein.
/// Existing v1 "records" rows are copied transactionally; the source table is
/// retained until a later verified release explicitly removes it.
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final root = await getDatabasesPath();
    _db = await openDatabase(
      p.join(root, 'khadamat_fanni_hosein.db'),
      version: 2,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        await db.execute('PRAGMA journal_mode = WAL');
        await db.execute('PRAGMA busy_timeout = 5000');
      },
      onCreate: (db, version) async {
        await _createSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.transaction((txn) async {
            await _createSchema(txn);
            await _migrateLegacyRecords(txn);
          });
        }
      },
    );
    return _db!;
  }

  static String newId() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0,8)}-${h.substring(8,12)}-${h.substring(12,16)}-${h.substring(16,20)}-${h.substring(20)}';
  }

  Future<void> _createSchema(DatabaseExecutor db) async {
    const entities = ['products','customers','suppliers','repairs','sales','purchases','payments'];
    for (final table in entities) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $table (
          id TEXT PRIMARY KEY,
          data TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          deleted_at TEXT,
          created_by TEXT,
          updated_by TEXT
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS ${table}_deleted_idx ON $table(deleted_at)');
    }
    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id TEXT PRIMARY KEY,
        username TEXT NOT NULL COLLATE NOCASE UNIQUE,
        display_name TEXT NOT NULL,
        role TEXT NOT NULL CHECK(role IN ('manager','technician')),
        password_hash TEXT NOT NULL,
        password_salt TEXT NOT NULL,
        pin_hash TEXT,
        pin_salt TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS audit_logs (
        id TEXT PRIMARY KEY, user_id TEXT, action TEXT NOT NULL,
        entity TEXT NOT NULL, entity_id TEXT, before_json TEXT, after_json TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS audit_entity_idx ON audit_logs(entity, entity_id)');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS backup_history (
        id TEXT PRIMARY KEY, file_path TEXT NOT NULL, created_at TEXT NOT NULL,
        size_bytes INTEGER, status TEXT NOT NULL, details TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL
      )
    ''');
    await db.insert('schema_migrations', {
      'version': 2, 'applied_at': DateTime.now().toUtc().toIso8601String()
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> _migrateLegacyRecords(DatabaseExecutor db) async {
    final exists = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='records'");
    if (exists.isEmpty) return;
    final rows = await db.query('records', orderBy: 'id ASC');
    const mapping = {
      'products':'products', 'customers':'customers',
      'repairs':'repairs', 'sales':'sales'
    };
    for (final row in rows) {
      final target = mapping[row['category']];
      if (target == null) continue;
      final raw = row['data'];
      if (raw is! String) continue;
      // Preserve the old numeric key inside legacy_id for traceability.
      final decoded = jsonDecode(raw);
      if (decoded is! Map) continue;
      final data = Map<String, dynamic>.from(decoded);
      data.putIfAbsent('legacy_id', () => row['id'].toString());
      final stamp = (row['created_at'] as String?) ??
          DateTime.now().toUtc().toIso8601String();
      await db.insert(target, {
        'id': newId(), 'data': jsonEncode(data),
        'created_at': stamp, 'updated_at': stamp,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<String> insertRecord(String table, Map<String, dynamic> data,
      {String? userId}) async {
    _checkTable(table);
    final db = await database;
    final id = newId();
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      await txn.insert(table, {
        'id': id, 'data': jsonEncode(data), 'created_at': now,
        'updated_at': now, 'created_by': userId, 'updated_by': userId,
      });
      await _audit(txn, userId, 'create', table, id, null, data);
    });
    return id;
  }

  Future<void> updateRecord(String table, String id,
      Map<String, dynamic> data, {String? userId}) async {
    _checkTable(table);
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      final rows = await txn.query(table,
          where: 'id = ? AND deleted_at IS NULL', whereArgs: [id], limit: 1);
      if (rows.isEmpty) throw StateError('رکورد پیدا نشد یا حذف شده است');
      final before = jsonDecode(rows.first['data'] as String);
      await txn.update(table, {
        'data': jsonEncode(data), 'updated_at': now, 'updated_by': userId,
      }, where: 'id = ?', whereArgs: [id]);
      await _audit(txn, userId, 'update', table, id, before, data);
    });
  }

  Future<void> softDelete(String table, String id, {String? userId}) async {
    _checkTable(table);
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      final rows = await txn.query(table,
          where: 'id = ? AND deleted_at IS NULL', whereArgs: [id], limit: 1);
      if (rows.isEmpty) throw StateError('رکورد پیدا نشد یا قبلاً حذف شده است');
      final before = jsonDecode(rows.first['data'] as String);
      await txn.update(table, {
        'deleted_at': now, 'updated_at': now, 'updated_by': userId,
      }, where: 'id = ?', whereArgs: [id]);
      await _audit(txn, userId, 'soft_delete', table, id, before, null);
    });
  }

  Future<List<Map<String, Object?>>> listRecords(String table,
      {bool includeDeleted = false}) async {
    _checkTable(table);
    final db = await database;
    return db.query(table,
      where: includeDeleted ? null : 'deleted_at IS NULL',
      orderBy: 'created_at DESC');
  }

  Future<void> _audit(DatabaseExecutor db, String? userId, String action,
      String entity, String entityId, Object? before, Object? after) async {
    await db.insert('audit_logs', {
      'id': newId(), 'user_id': userId, 'action': action,
      'entity': entity, 'entity_id': entityId,
      'before_json': before == null ? null : jsonEncode(before),
      'after_json': after == null ? null : jsonEncode(after),
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  void _checkTable(String table) {
    const allowed = {'products','customers','suppliers','repairs','sales','purchases','payments'};
    if (!allowed.contains(table)) throw ArgumentError.value(table, 'table');
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
