import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Versioned SQLite storage for the shop.
class AppDatabase {
  AppDatabase({String? databasePath}) : _databasePath = databasePath;

  static const String databaseName = 'khadamat_fanni_hosein.db';
  static const int schemaVersion = 3;

  static const Map<String, String> _tables = {
    'products': 'products',
    'customers': 'customers',
    'repairs': 'repairs',
    'sales': 'sales',
  };

  static const List<Map<String, String>> _defaultAccounts = [
    {'code': '1000', 'name': 'صندوق', 'type': 'asset', 'side': 'debit'},
    {'code': '1010', 'name': 'بانک', 'type': 'asset', 'side': 'debit'},
    {'code': '1100', 'name': 'دریافتنی از مشتریان', 'type': 'asset', 'side': 'debit'},
    {'code': '1200', 'name': 'موجودی کالا', 'type': 'asset', 'side': 'debit'},
    {'code': '2000', 'name': 'پرداختنی به فروشندگان', 'type': 'liability', 'side': 'credit'},
    {'code': '2100', 'name': 'مالیات ارزش افزوده پرداختنی', 'type': 'liability', 'side': 'credit'},
    {'code': '3000', 'name': 'سرمایه و مانده افتتاحیه', 'type': 'equity', 'side': 'credit'},
    {'code': '4000', 'name': 'درآمد فروش کالا', 'type': 'income', 'side': 'credit'},
    {'code': '4100', 'name': 'درآمد خدمات تعمیر', 'type': 'income', 'side': 'credit'},
    {'code': '5000', 'name': 'بهای تمام‌شده کالای فروش‌رفته', 'type': 'expense', 'side': 'debit'},
    {'code': '5100', 'name': 'هزینه قطعات مصرفی تعمیر', 'type': 'expense', 'side': 'debit'},
    {'code': '6000', 'name': 'هزینه‌های جاری', 'type': 'expense', 'side': 'debit'},
  ];

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
        await _createCoreSchema(db);
        await _createAccountingSchema(db);
        await _seedAccounts(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createCoreSchema(db);
          await _migrateLegacyRecords(db);
        }
        if (oldVersion < 3) {
          await _createAccountingSchema(db);
          await _seedAccounts(db);
          await _migrateOpeningStock(db);
        }
      },
    );
    return _db!;
  }

  static Future<void> _createCoreSchema(DatabaseExecutor db) async {
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
        'CREATE INDEX IF NOT EXISTS idx_' + table + '_created_at ON ' +
            table + '(created_at)',
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

  static Future<void> _createAccountingSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS accounts (
        code TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        account_type TEXT NOT NULL CHECK (
          account_type IN ('asset', 'liability', 'equity', 'income', 'expense')
        ),
        normal_side TEXT NOT NULL CHECK (normal_side IN ('debit', 'credit')),
        is_system INTEGER NOT NULL DEFAULT 1 CHECK (is_system IN (0, 1))
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS journal_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entry_date TEXT NOT NULL,
        description TEXT NOT NULL,
        reference_type TEXT,
        reference_id TEXT,
        idempotency_key TEXT NOT NULL UNIQUE,
        payload_json TEXT NOT NULL,
        reversal_of_id INTEGER UNIQUE,
        created_at TEXT NOT NULL,
        FOREIGN KEY (reversal_of_id) REFERENCES journal_entries(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS journal_lines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        journal_entry_id INTEGER NOT NULL,
        line_no INTEGER NOT NULL,
        account_code TEXT NOT NULL,
        debit INTEGER NOT NULL DEFAULT 0 CHECK (debit >= 0),
        credit INTEGER NOT NULL DEFAULT 0 CHECK (credit >= 0),
        party_id TEXT,
        memo TEXT,
        CHECK (
          (debit > 0 AND credit = 0) OR
          (credit > 0 AND debit = 0)
        ),
        UNIQUE (journal_entry_id, line_no),
        FOREIGN KEY (journal_entry_id) REFERENCES journal_entries(id) ON DELETE RESTRICT,
        FOREIGN KEY (account_code) REFERENCES accounts(code) ON DELETE RESTRICT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS inventory_movements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        movement_type TEXT NOT NULL,
        quantity_delta REAL NOT NULL CHECK (quantity_delta != 0),
        unit_cost INTEGER NOT NULL CHECK (unit_cost >= 0),
        total_cost INTEGER NOT NULL CHECK (total_cost >= 0),
        occurred_at TEXT NOT NULL,
        reference_type TEXT,
        reference_id TEXT,
        idempotency_key TEXT NOT NULL UNIQUE,
        payload_json TEXT NOT NULL,
        journal_entry_id INTEGER,
        created_at TEXT NOT NULL,
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE RESTRICT,
        FOREIGN KEY (journal_entry_id) REFERENCES journal_entries(id) ON DELETE RESTRICT
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_journal_entries_date ON journal_entries(entry_date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_journal_lines_account ON journal_lines(account_code, journal_entry_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_inventory_product_date ON inventory_movements(product_id, occurred_at)',
    );
  }

  static Future<void> _seedAccounts(DatabaseExecutor db) async {
    for (final account in _defaultAccounts) {
      await db.insert(
        'accounts',
        {
          'code': account['code'],
          'name': account['name'],
          'account_type': account['type'],
          'normal_side': account['side'],
          'is_system': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
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

  static String _normalizeDigits(String value) {
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    var result = value;
    for (var i = 0; i < 10; i++) {
      result = result.replaceAll(persian[i], '$i');
      result = result.replaceAll(arabic[i], '$i');
    }
    return result.replaceAll(',', '').replaceAll('٬', '').replaceAll('٫', '.').trim();
  }

  static double _number(Object? value) {
    return double.tryParse(_normalizeDigits(value?.toString() ?? '')) ?? 0;
  }

  static Future<void> _migrateOpeningStock(DatabaseExecutor db) async {
    final products = await db.query(
      'products',
      columns: ['id', 'data_json', 'created_at'],
      orderBy: 'id ASC',
    );
    for (final product in products) {
      final decoded = jsonDecode(product['data_json'] as String);
      if (decoded is! Map<String, dynamic>) continue;

      final quantity = _number(decoded['موجودی']);
      if (quantity <= 0) continue;
      final unitCost = _number(
        decoded['بهای تمام‌شده هر واحد'] ?? decoded['قیمت خرید هر واحد'],
      ).round();
      final productId = product['id'] as int;
      final occurredAt = product['created_at']?.toString() ??
          DateTime.fromMillisecondsSinceEpoch(0).toIso8601String();
      final payload = jsonEncode({
        'productId': productId,
        'type': 'opening_balance',
        'quantityDelta': quantity,
        'unitCost': unitCost,
        'occurredAt': occurredAt,
      });

      await db.insert(
        'inventory_movements',
        {
          'product_id': productId,
          'movement_type': 'opening_balance',
          'quantity_delta': quantity,
          'unit_cost': unitCost,
          'total_cost': (quantity * unitCost).round(),
          'occurred_at': occurredAt,
          'reference_type': 'database_migration',
          'reference_id': productId.toString(),
          'idempotency_key': 'migration-opening-product-' + productId.toString(),
          'payload_json': payload,
          'journal_entry_id': null,
          'created_at': DateTime.now().toIso8601String(),
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
      final item = decoded.map(
        (key, value) => MapEntry(key, value?.toString() ?? ''),
      );
      item['__database_id'] = row['id'].toString();
      return item;
    }).toList(growable: true);
  }

  Future<int> insert(String category, Map<String, String> item) async {
    final table = _tableFor(category);
    if (item.isEmpty || item.values.every((value) => value.trim().isEmpty)) {
      throw ArgumentError('اطلاعات خالی قابل ذخیره نیست');
    }

    final now = DateTime.now().toIso8601String();
    final db = await database;
    return db.transaction((txn) async {
      final id = await txn.insert(table, {
        'data_json': jsonEncode(item),
        'created_at': now,
        'updated_at': now,
      });

      // Initial quantity is recorded exactly once as opening stock.
      if (category == 'products') {
        final quantity = _number(item['موجودی']);
        if (quantity > 0) {
          final unitCost = _number(
            item['بهای تمام‌شده هر واحد'] ?? item['قیمت خرید هر واحد'],
          ).round();
          final payload = jsonEncode({
            'productId': id,
            'type': 'opening_balance',
            'quantityDelta': quantity,
            'unitCost': unitCost,
            'occurredAt': now,
          });
          await txn.insert('inventory_movements', {
            'product_id': id,
            'movement_type': 'opening_balance',
            'quantity_delta': quantity,
            'unit_cost': unitCost,
            'total_cost': (quantity * unitCost).round(),
            'occurred_at': now,
            'reference_type': 'product_creation',
            'reference_id': id.toString(),
            'idempotency_key': 'product-opening-' + id.toString(),
            'payload_json': payload,
            'journal_entry_id': null,
            'created_at': now,
          });
        }
      }
      return id;
    });
  }

  Future<double> getStockOnHand(int productId) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(quantity_delta), 0) AS quantity '
      'FROM inventory_movements WHERE product_id = ?',
      [productId],
    );
    return (rows.first['quantity'] as num?)?.toDouble() ?? 0;
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    if (db != null && db.isOpen) await db.close();
  }
}
