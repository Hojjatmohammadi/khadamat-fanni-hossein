import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Versioned SQLite storage for the shop.
class AppDatabase {
  AppDatabase({String? databasePath}) : _databasePath = databasePath;

  static const String databaseName = 'khadamat_fanni_hosein.db';
  static const int schemaVersion = 6;

  static const Map<String, String> _tables = {
    'products': 'products',
    'customers': 'customers',
    'repairs': 'repairs',
    'sales': 'sales',
  };

  static const List<Map<String, String>> _defaultAccounts = [
    {'code': '1000', 'name': 'صندوق', 'type': 'asset', 'side': 'debit'},
    {'code': '1010', 'name': 'بانک', 'type': 'asset', 'side': 'debit'},
    {'code': '1020', 'name': 'چک‌های دریافتی', 'type': 'asset', 'side': 'debit'},
    {'code': '1100', 'name': 'دریافتنی از مشتریان', 'type': 'asset', 'side': 'debit'},
    {'code': '2110', 'name': 'مالیات ارزش افزوده خرید', 'type': 'asset', 'side': 'debit'},
    {'code': '1200', 'name': 'موجودی کالا', 'type': 'asset', 'side': 'debit'},
    {'code': '2000', 'name': 'پرداختنی به فروشندگان', 'type': 'liability', 'side': 'credit'},
    {'code': '2020', 'name': 'چک‌های پرداختنی', 'type': 'liability', 'side': 'credit'},
    {'code': '2100', 'name': 'مالیات ارزش افزوده پرداختنی', 'type': 'liability', 'side': 'credit'},
    {'code': '3000', 'name': 'سرمایه و مانده افتتاحیه', 'type': 'equity', 'side': 'credit'},
    {'code': '4000', 'name': 'درآمد فروش کالا', 'type': 'income', 'side': 'credit'},
    {'code': '4050', 'name': 'برگشت از فروش', 'type': 'expense', 'side': 'debit'},
    {'code': '4100', 'name': 'درآمد خدمات تعمیر', 'type': 'income', 'side': 'credit'},
    {'code': '5000', 'name': 'بهای تمام‌شده کالای فروش‌رفته', 'type': 'expense', 'side': 'debit'},
    {'code': '5100', 'name': 'هزینه قطعات مصرفی تعمیر', 'type': 'expense', 'side': 'debit'},
    {'code': '6000', 'name': 'هزینه‌های جاری', 'type': 'expense', 'side': 'debit'},
    {'code': '6100', 'name': 'اجاره و شارژ', 'type': 'expense', 'side': 'debit'},
    {'code': '6200', 'name': 'آب، برق، گاز و تلفن', 'type': 'expense', 'side': 'debit'},
    {'code': '6300', 'name': 'حقوق و دستمزد', 'type': 'expense', 'side': 'debit'},
    {'code': '6400', 'name': 'حمل‌ونقل و ایاب‌وذهاب', 'type': 'expense', 'side': 'debit'},
    {'code': '6500', 'name': 'تعمیر و نگهداری ابزار', 'type': 'expense', 'side': 'debit'},
    {'code': '6600', 'name': 'سایر هزینه‌ها', 'type': 'expense', 'side': 'debit'},
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
        await _createCommerceSchema(db);
        await _createPartyAndCheckSchema(db);
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
        if (oldVersion < 4) {
          await _createCommerceSchema(db);
          await _seedAccounts(db);
        }
        if (oldVersion < 5) {
          await _createPartyAndCheckSchema(db);
          await _seedAccounts(db);
          await _migrateParties(db);
        }
        if (oldVersion < 6) {
          await _seedAccounts(db);
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

    await db.execute("""
      CREATE TRIGGER IF NOT EXISTS immutable_journal_entries_update
      BEFORE UPDATE ON journal_entries
      BEGIN
        SELECT RAISE(ABORT, 'posted journal entries are immutable');
      END
    """);
    await db.execute("""
      CREATE TRIGGER IF NOT EXISTS immutable_journal_entries_delete
      BEFORE DELETE ON journal_entries
      BEGIN
        SELECT RAISE(ABORT, 'posted journal entries are immutable');
      END
    """);
    await db.execute("""
      CREATE TRIGGER IF NOT EXISTS immutable_journal_lines_update
      BEFORE UPDATE ON journal_lines
      BEGIN
        SELECT RAISE(ABORT, 'posted journal lines are immutable');
      END
    """);
    await db.execute("""
      CREATE TRIGGER IF NOT EXISTS immutable_journal_lines_delete
      BEFORE DELETE ON journal_lines
      BEGIN
        SELECT RAISE(ABORT, 'posted journal lines are immutable');
      END
    """);
    await db.execute("""
      CREATE TRIGGER IF NOT EXISTS immutable_inventory_movements_update
      BEFORE UPDATE ON inventory_movements
      BEGIN
        SELECT RAISE(ABORT, 'inventory movements are immutable');
      END
    """);
    await db.execute("""
      CREATE TRIGGER IF NOT EXISTS immutable_inventory_movements_delete
      BEFORE DELETE ON inventory_movements
      BEGIN
        SELECT RAISE(ABORT, 'inventory movements are immutable');
      END
    """);
  }

  static Future<void> _createCommerceSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS business_documents (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        document_type TEXT NOT NULL CHECK (
          document_type IN (
            'purchase', 'sale', 'repair_consumption',
            'customer_return', 'supplier_return',
            'customer_receipt', 'supplier_payment'
          )
        ),
        document_date TEXT NOT NULL,
        document_number TEXT NOT NULL,
        counterparty_id TEXT,
        counterparty_name TEXT NOT NULL,
        subtotal INTEGER NOT NULL CHECK (subtotal >= 0),
        discount_amount INTEGER NOT NULL DEFAULT 0 CHECK (discount_amount >= 0),
        charges_amount INTEGER NOT NULL DEFAULT 0 CHECK (charges_amount >= 0),
        vat_amount INTEGER NOT NULL DEFAULT 0 CHECK (vat_amount >= 0),
        total_amount INTEGER NOT NULL CHECK (total_amount >= 0),
        paid_amount INTEGER NOT NULL DEFAULT 0 CHECK (paid_amount >= 0),
        source_document_id INTEGER,
        journal_entry_id INTEGER,
        idempotency_key TEXT NOT NULL UNIQUE,
        payload_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (source_document_id) REFERENCES business_documents(id) ON DELETE RESTRICT,
        FOREIGN KEY (journal_entry_id) REFERENCES journal_entries(id) ON DELETE RESTRICT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS business_document_lines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        document_id INTEGER NOT NULL,
        source_line_id INTEGER,
        product_id INTEGER NOT NULL,
        product_name TEXT NOT NULL,
        quantity REAL NOT NULL CHECK (quantity > 0),
        unit_price INTEGER NOT NULL CHECK (unit_price >= 0),
        unit_cost INTEGER NOT NULL CHECK (unit_cost >= 0),
        line_total INTEGER NOT NULL CHECK (line_total >= 0),
        tax_amount INTEGER NOT NULL DEFAULT 0 CHECK (tax_amount >= 0),
        created_at TEXT NOT NULL,
        FOREIGN KEY (document_id) REFERENCES business_documents(id) ON DELETE RESTRICT,
        FOREIGN KEY (source_line_id) REFERENCES business_document_lines(id) ON DELETE RESTRICT,
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE RESTRICT
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_business_documents_type_date ON business_documents(document_type, document_date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_business_documents_party ON business_documents(counterparty_id, document_date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_business_lines_document ON business_document_lines(document_id, id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_business_lines_source ON business_document_lines(source_line_id)',
    );

    await db.execute("""
      CREATE TRIGGER IF NOT EXISTS immutable_business_documents_update
      BEFORE UPDATE ON business_documents
      BEGIN
        SELECT RAISE(ABORT, 'posted business documents are immutable');
      END
    """);
    await db.execute("""
      CREATE TRIGGER IF NOT EXISTS immutable_business_documents_delete
      BEFORE DELETE ON business_documents
      BEGIN
        SELECT RAISE(ABORT, 'posted business documents are immutable');
      END
    """);
    await db.execute("""
      CREATE TRIGGER IF NOT EXISTS immutable_business_document_lines_update
      BEFORE UPDATE ON business_document_lines
      BEGIN
        SELECT RAISE(ABORT, 'posted business document lines are immutable');
      END
    """);
    await db.execute("""
      CREATE TRIGGER IF NOT EXISTS immutable_business_document_lines_delete
      BEFORE DELETE ON business_document_lines
      BEGIN
        SELECT RAISE(ABORT, 'posted business document lines are immutable');
      END
    """);
  }

  static Future<void> _createPartyAndCheckSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS parties (
        id TEXT PRIMARY KEY,
        party_type TEXT NOT NULL CHECK (party_type IN ('customer', 'supplier', 'other')),
        display_name TEXT NOT NULL,
        normalized_name TEXT NOT NULL,
        phone TEXT,
        address TEXT,
        notes TEXT,
        source_category TEXT,
        source_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS check_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        direction TEXT NOT NULL CHECK (direction IN ('incoming', 'outgoing')),
        check_number TEXT NOT NULL,
        bank_name TEXT NOT NULL,
        drawer_name TEXT NOT NULL,
        party_id TEXT,
        party_name TEXT NOT NULL,
        amount INTEGER NOT NULL CHECK (amount > 0),
        issue_date TEXT NOT NULL,
        due_date TEXT NOT NULL,
        status TEXT NOT NULL CHECK (
          status IN ('received', 'deposited', 'issued', 'cleared', 'bounced', 'cancelled')
        ),
        source_document_id INTEGER,
        acceptance_journal_id INTEGER,
        settlement_journal_id INTEGER,
        reversal_journal_id INTEGER,
        idempotency_key TEXT NOT NULL UNIQUE,
        payload_json TEXT NOT NULL,
        note TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (party_id) REFERENCES parties(id) ON DELETE RESTRICT,
        FOREIGN KEY (source_document_id) REFERENCES business_documents(id) ON DELETE RESTRICT,
        FOREIGN KEY (acceptance_journal_id) REFERENCES journal_entries(id) ON DELETE RESTRICT,
        FOREIGN KEY (settlement_journal_id) REFERENCES journal_entries(id) ON DELETE RESTRICT,
        FOREIGN KEY (reversal_journal_id) REFERENCES journal_entries(id) ON DELETE RESTRICT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS check_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        check_id INTEGER NOT NULL,
        old_status TEXT,
        new_status TEXT NOT NULL,
        event_date TEXT NOT NULL,
        description TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (check_id) REFERENCES check_records(id) ON DELETE RESTRICT
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_parties_name ON parties(party_type, normalized_name)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_check_records_due ON check_records(due_date, status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_check_records_party ON check_records(party_id, due_date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_check_events_check ON check_events(check_id, event_date, id)',
    );

    await db.execute("""
      CREATE TRIGGER IF NOT EXISTS check_records_immutable_fields
      BEFORE UPDATE ON check_records
      WHEN OLD.direction != NEW.direction
        OR OLD.check_number != NEW.check_number
        OR OLD.bank_name != NEW.bank_name
        OR OLD.drawer_name != NEW.drawer_name
        OR OLD.party_id IS NOT NEW.party_id
        OR OLD.party_name != NEW.party_name
        OR OLD.amount != NEW.amount
        OR OLD.issue_date != NEW.issue_date
        OR OLD.due_date != NEW.due_date
        OR OLD.source_document_id IS NOT NEW.source_document_id
        OR OLD.acceptance_journal_id != NEW.acceptance_journal_id
        OR OLD.idempotency_key != NEW.idempotency_key
        OR OLD.payload_json != NEW.payload_json
        OR OLD.note IS NOT NEW.note
      BEGIN
        SELECT RAISE(ABORT, 'check details are immutable after registration');
      END
    """);
    await db.execute("""
      CREATE TRIGGER IF NOT EXISTS check_records_no_delete
      BEFORE DELETE ON check_records
      BEGIN
        SELECT RAISE(ABORT, 'registered checks cannot be deleted');
      END
    """);
    await db.execute("""
      CREATE TRIGGER IF NOT EXISTS immutable_check_events_update
      BEFORE UPDATE ON check_events
      BEGIN
        SELECT RAISE(ABORT, 'check events are immutable');
      END
    """);
    await db.execute("""
      CREATE TRIGGER IF NOT EXISTS immutable_check_events_delete
      BEFORE DELETE ON check_events
      BEGIN
        SELECT RAISE(ABORT, 'check events are immutable');
      END
    """);
  }

  static Future<void> _migrateParties(DatabaseExecutor db) async {
    final now = DateTime.now().toIso8601String();
    final customers = await db.query('customers', orderBy: 'id ASC');
    for (final row in customers) {
      final decoded = jsonDecode(row['data_json'] as String);
      if (decoded is! Map<String, dynamic>) continue;
      final name = (decoded['نام مشتری'] ?? decoded['نام'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      final id = 'customer:${row['id']}';
      final normalized = name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      await db.insert(
        'parties',
        {
          'id': id,
          'party_type': 'customer',
          'display_name': name,
          'normalized_name': normalized,
          'phone': decoded['شماره تماس']?.toString(),
          'address': decoded['آدرس']?.toString(),
          'notes': decoded['توضیحات']?.toString(),
          'source_category': 'customers',
          'source_id': row['id'].toString(),
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    final documents = await db.query(
      'business_documents',
      where: 'counterparty_id IS NOT NULL AND counterparty_id != ?',
      whereArgs: [''],
      orderBy: 'id ASC',
    );
    for (final row in documents) {
      final id = row['counterparty_id']?.toString();
      final name = row['counterparty_name']?.toString().trim() ?? '';
      if (id == null || id.isEmpty || name.isEmpty) continue;
      final type = switch (row['document_type']) {
        'purchase' || 'supplier_return' || 'supplier_payment' => 'supplier',
        'sale' || 'customer_return' || 'customer_receipt' => 'customer',
        _ => 'other',
      };
      final normalized = name.toLowerCase().replaceAll(RegExp(r'\\s+'), ' ');
      await db.insert(
        'parties',
        {
          'id': id,
          'party_type': type,
          'display_name': name,
          'normalized_name': normalized,
          'phone': null,
          'address': null,
          'notes': null,
          'source_category': 'business_documents',
          'source_id': row['id'].toString(),
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
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

  static Future<int?> _insertOpeningStockJournal({
    required DatabaseExecutor db,
    required int productId,
    required int totalCost,
    required String occurredAt,
  }) async {
    if (totalCost <= 0) return null;

    final idempotencyKey = 'opening-stock-journal-' + productId.toString();
    final description = 'سند افتتاحیه موجودی کالای شماره ' + productId.toString();
    final payload = jsonEncode({
      'entryDate': occurredAt,
      'description': description,
      'idempotencyKey': idempotencyKey,
      'referenceType': 'opening_stock',
      'referenceId': productId.toString(),
      'lines': [
        {'accountCode': '1200', 'debit': totalCost, 'credit': 0},
        {'accountCode': '3000', 'debit': 0, 'credit': totalCost},
      ],
    });
    final now = DateTime.now().toIso8601String();
    final entryId = await db.insert('journal_entries', {
      'entry_date': occurredAt,
      'description': description,
      'reference_type': 'opening_stock',
      'reference_id': productId.toString(),
      'idempotency_key': idempotencyKey,
      'payload_json': payload,
      'reversal_of_id': null,
      'created_at': now,
    });
    await db.insert('journal_lines', {
      'journal_entry_id': entryId,
      'line_no': 1,
      'account_code': '1200',
      'debit': totalCost,
      'credit': 0,
      'party_id': null,
      'memo': 'ارزش موجودی افتتاحیه',
    });
    await db.insert('journal_lines', {
      'journal_entry_id': entryId,
      'line_no': 2,
      'account_code': '3000',
      'debit': 0,
      'credit': totalCost,
      'party_id': null,
      'memo': 'مانده افتتاحیه سرمایه',
    });
    return entryId;
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
      final totalCost = (quantity * unitCost).round();
      final journalEntryId = await _insertOpeningStockJournal(
        db: db,
        productId: productId,
        totalCost: totalCost,
        occurredAt: occurredAt,
      );
      final payload = jsonEncode({
        'productId': productId,
        'type': 'opening_balance',
        'quantityDelta': quantity,
        'unitCost': unitCost,
        'totalCost': totalCost,
        'occurredAt': occurredAt,
      });

      await db.insert(
        'inventory_movements',
        {
          'product_id': productId,
          'movement_type': 'opening_balance',
          'quantity_delta': quantity,
          'unit_cost': unitCost,
          'total_cost': totalCost,
          'occurred_at': occurredAt,
          'reference_type': 'database_migration',
          'reference_id': productId.toString(),
          'idempotency_key': 'migration-opening-product-' + productId.toString(),
          'payload_json': payload,
          'journal_entry_id': journalEntryId,
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
        final unitCost = _number(
          item['بهای تمام‌شده هر واحد'] ?? item['قیمت خرید هر واحد'],
        ).round();
        if (quantity < 0 || unitCost < 0) {
          throw ArgumentError('موجودی و بهای تمام‌شده کالا نمی‌تواند منفی باشد');
        }
        if (quantity > 0) {
          final totalCost = (quantity * unitCost).round();
          final journalEntryId = await _insertOpeningStockJournal(
            db: txn,
            productId: id,
            totalCost: totalCost,
            occurredAt: now,
          );
          final payload = jsonEncode({
            'productId': id,
            'type': 'opening_balance',
            'quantityDelta': quantity,
            'unitCost': unitCost,
            'totalCost': totalCost,
            'occurredAt': now,
          });
          await txn.insert('inventory_movements', {
            'product_id': id,
            'movement_type': 'opening_balance',
            'quantity_delta': quantity,
            'unit_cost': unitCost,
            'total_cost': totalCost,
            'occurred_at': now,
            'reference_type': 'product_creation',
            'reference_id': id.toString(),
            'idempotency_key': 'product-opening-' + id.toString(),
            'payload_json': payload,
            'journal_entry_id': journalEntryId,
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
