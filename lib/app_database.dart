import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Local, versioned SQLite storage for the shop.
///
/// Version 2 separates the four app domains into their own tables. The v1
/// `records` table is intentionally retained after migration so the original
/// rows remain recoverable if a future migration needs to be audited.
class AppDatabase {
  AppDatabase({String? databasePath}) : _databasePath = databasePath;

  static const String databaseName = 'khadamat_fanni_hosein.db';
  static const int schemaVersion = 2;

  static const Map<String, String> _tables = {
    'products': 'products',
    'customers': 'customers',
    'repairs': 'repairs',
    'sales': 'sales',
  };

  final String? _databasePath;
  Database? _db;

  Future<Database> get database async {
    final existing = _db;
    if (existing != null && existing.isOpen) return existing;

    final path = _databasePath ?? p.join(await getDatabasesPath(), databaseName);
    _db = await openDatabase(
      path,
      version: schemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
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

  static Future<void> _createSchema(DatabaseExecutor db) async {
    for (final table in _tables.values) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $table (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          data_json TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_${table}_created_at ON $table(created_at)',
      );
    }

    await db.execute('''
      CREATE TABLE IF NOT EXISTS legacy_records (
        id INTEGER PRIMARY KEY,
        category TEXT NOT NULL,
        data TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _migrateLegacyRecords(DatabaseExecutor db) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      ['records'],
    );
    if (tables.isEmpty) return;

    final rows = await db.query('records', orderBy: 'id ASC');
    for (final row in rows) {
      final category = row['category']?.toString() ?? '';
      final table = _tables[category];
      final id = row['id'] as int;
      final rawData = row['data']?.toString() ?? '{}';
      final createdAt = row['created_at']?.toString() ??
          DateTime.fromMillisecondsSinceEpoch(0).toIso8601String();

      if (table == null) {
        await db.insert(
          'legacy_records',
          {
            'id': id,
            'category': category,
            'data': rawData,
            'created_at': createdAt,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        continue;
      }

      await db.insert(
        table,
        {
          'id': id,
          'data_json': rawData,
          'created_at': createdAt,
          'updated_at': createdAt,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  String _tableFor(String category) {
    final table = _tables[category];
    if (table == null) {
      throw ArgumentError.value(category, 'category', 'دسته اطلاعات نامعتبر است');
    }
    return table;
  }

  Future<List<Map<String, String>>> getAll(String category) async {
    final table = _tableFor(category);
    final db = await database;
    final rows = await db.query(table, orderBy: 'id ASC');
    return rows.map((row) {
      final raw = row['data_json'] as String;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('ساختار اطلاعات ذخیره‌شده معتبر نیست');
      }
      return decoded.map(
        (key, value) => MapEntry(key, value?.toString() ?? ''),
      );
    }).toList(growable: true);
  }

  Future<int> insert(String category, Map<String, String> item) async {
    final table = _tableFor(category);
    if (item.isEmpty || item.values.every((value) => value.trim().isEmpty)) {
      throw ArgumentError('اطلاعات خالی قابل ذخیره نیست');
    }

    final now = DateTime.now().toIso8601String();
    final db = await database;
    return db.insert(table, {
      'data_json': jsonEncode(item),
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    if (db != null && db.isOpen) await db.close();
  }
}
