import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import '../accounting/accounting_engine.dart';

/// Relational tables and a non-destructive migration from the original
/// JSON records table. The legacy table remains available during rollout.
class AppDatabaseSchema {
  AppDatabaseSchema._();

  static Future<void> create(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        first_name TEXT NOT NULL DEFAULT '',
        last_name TEXT NOT NULL DEFAULT '',
        phone TEXT NOT NULL DEFAULT '',
        address TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        legacy_source_id INTEGER UNIQUE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS suppliers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        normalized_name TEXT NOT NULL UNIQUE,
        phone TEXT NOT NULL DEFAULT '',
        address TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS suppliers_name_idx ON suppliers(normalized_name)');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL DEFAULT '',
        name TEXT NOT NULL,
        category TEXT NOT NULL DEFAULT '',
        subcategory TEXT NOT NULL DEFAULT '',
        unit TEXT NOT NULL DEFAULT 'عدد',
        quantity REAL NOT NULL DEFAULT 0,
        purchase_price REAL NOT NULL DEFAULT 0,
        sale_price REAL NOT NULL DEFAULT 0,
        is_used INTEGER NOT NULL DEFAULT 0 CHECK (is_used IN (0, 1)),
        image_path TEXT NOT NULL DEFAULT '',
        image_base64 TEXT NOT NULL DEFAULT '',
        shipping_cost REAL NOT NULL DEFAULT 0,
        freight_cost REAL NOT NULL DEFAULT 0,
        other_cost REAL NOT NULL DEFAULT 0,
        vat_rate REAL NOT NULL DEFAULT 0,
        vat_included INTEGER NOT NULL DEFAULT 0 CHECK (vat_included IN (0, 1)),
        created_at TEXT NOT NULL,
        legacy_source_id INTEGER UNIQUE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS repairs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER,
        customer_name_snapshot TEXT NOT NULL DEFAULT '',
        device_type TEXT NOT NULL DEFAULT '',
        model TEXT NOT NULL DEFAULT '',
        serial_number TEXT NOT NULL DEFAULT '',
        problem_description TEXT NOT NULL DEFAULT '',
        accessories TEXT NOT NULL DEFAULT '',
        received_at TEXT NOT NULL,
        estimated_cost REAL NOT NULL DEFAULT 0,
        labor_cost REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'پذیرفته شد',
        legacy_source_id INTEGER UNIQUE,
        FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_number TEXT NOT NULL UNIQUE,
        customer_id INTEGER,
        customer_name_snapshot TEXT NOT NULL DEFAULT '',
        subtotal REAL NOT NULL DEFAULT 0,
        discount REAL NOT NULL DEFAULT 0,
        tax REAL NOT NULL DEFAULT 0,
        total REAL NOT NULL DEFAULT 0,
        received_amount REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        notes TEXT NOT NULL DEFAULT '',
        legacy_source_id INTEGER UNIQUE,
        FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoice_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_id INTEGER NOT NULL,
        product_id INTEGER,
        product_name_snapshot TEXT NOT NULL,
        unit TEXT NOT NULL DEFAULT 'عدد',
        is_used INTEGER NOT NULL DEFAULT 0 CHECK (is_used IN (0, 1)),
        quantity REAL NOT NULL DEFAULT 1,
        unit_price REAL NOT NULL DEFAULT 0,
        line_total REAL NOT NULL DEFAULT 0,
        FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('CREATE INDEX IF NOT EXISTS customers_phone_idx ON customers(phone)');
    await db.execute('CREATE INDEX IF NOT EXISTS customers_name_idx ON customers(last_name, first_name)');
    await db.execute('CREATE INDEX IF NOT EXISTS products_code_idx ON products(code)');
    await db.execute('CREATE INDEX IF NOT EXISTS products_name_idx ON products(name)');
    await db.execute('CREATE INDEX IF NOT EXISTS products_category_idx ON products(category)');
    await db.execute('CREATE INDEX IF NOT EXISTS repairs_customer_idx ON repairs(customer_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS repairs_status_idx ON repairs(status)');
    await db.execute('CREATE INDEX IF NOT EXISTS invoices_customer_idx ON invoices(customer_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS invoices_created_idx ON invoices(created_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS invoice_items_invoice_idx ON invoice_items(invoice_id)');
    await AccountingEngine.createTables(db);
  }

  /// Creates or finds a supplier by normalized name. The caller should pass a
  /// selected supplier ID when duplicate names are intentionally distinct.
  static Future<int> ensureSupplier(
    DatabaseExecutor db,
    String supplierName, {
    String phone = '',
    String address = '',
  }) async {
    final name = supplierName.trim().replaceAll(RegExp(r'\\s+'), ' ');
    if (name.isEmpty) throw ArgumentError('نام فروشنده الزامی است.');
    final normalized = name.toLowerCase();
    final existing = await db.query(
      'suppliers',
      columns: ['id'],
      where: 'normalized_name = ?',
      whereArgs: [normalized],
      limit: 1,
    );
    if (existing.isNotEmpty) return existing.first['id'] as int;
    return db.insert('suppliers', {
      'name': name,
      'normalized_name': normalized,
      'phone': phone.trim(),
      'address': address.trim(),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Backfills supplier identities for historic purchase and supplier-operation
  /// journal rows without touching immutable invoice/purchase snapshots.
  static Future<void> migrateSupplierPartyIds(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS suppliers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        normalized_name TEXT NOT NULL UNIQUE,
        phone TEXT NOT NULL DEFAULT '',
        address TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS suppliers_name_idx ON suppliers(normalized_name)');
    final records = await db.query(
      'records',
      columns: ['id', 'category', 'data'],
      where: 'category = ?',
      whereArgs: ['operations'],
      orderBy: 'id ASC',
    );
    for (final record in records) {
      final data = _decode(record['data']);
      final operation = _text(data, 'نوع عملیات');
      final partyType = _text(data, 'نوع طرف حساب');
      final supplierName = _text(data, 'نام شخص');
      if (supplierName.isEmpty ||
          !(operation == 'خرید کالا' || partyType == 'فروشنده' ||
            operation == 'تخفیف گرفتن' || operation == 'تخفیف گرفتن از فروشنده')) {
        continue;
      }
      final supplierId = await ensureSupplier(db, supplierName);
      data['شناسه فروشنده'] = supplierId.toString();
      await db.update(
        'records',
        {'data': jsonEncode(data)},
        where: 'id = ?',
        whereArgs: [record['id']],
      );
      final sourceType = operation == 'خرید کالا' ? 'purchase' : 'operation';
      await db.update(
        'journal_lines',
        {'party_type': 'supplier', 'party_id': supplierId},
        where: '''entry_id IN (
          SELECT id FROM journal_entries WHERE source_type = ? AND source_id = ?
        ) AND account_id IN (SELECT id FROM accounts WHERE code IN ('2000','1110'))''',
        whereArgs: [sourceType, record['id'].toString()],
      );
      await db.update(
        'checks_register',
        {'party_type': 'supplier', 'party_id': supplierId},
        where: 'party_name_snapshot = ? AND party_type = ? AND party_id IS NULL',
        whereArgs: [supplierName, 'فروشنده'],
      );
    }
  }

  static String _text(Map<String, Object?> data, String key) =>
      (data[key] ?? '').toString().trim();

  static double _number(Map<String, Object?> data, String key) {
    var value = _text(data, key);
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    for (var i = 0; i < 10; i++) {
      value = value.replaceAll(persian[i], i.toString());
      value = value.replaceAll(arabic[i], i.toString());
    }
    value = value.replaceAll(',', '').replaceAll('٬', '').replaceAll('٫', '.');
    return double.tryParse(value) ?? 0;
  }

  static Map<String, Object?> _decode(Object? raw) {
    if (raw is! String || raw.isEmpty) return <String, Object?>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // Keep the original legacy row untouched if its JSON is malformed.
    }
    return <String, Object?>{};
  }

  static void _assertNumeric(
    Map<String, Object?> data,
    List<String> keys, {
    bool allowDecimal = false,
  }) {
    final pattern = allowDecimal
        ? RegExp(r'^\d+(?:\.\d{1,3})?$')
        : RegExp(r'^\d+$');
    for (final key in keys) {
      final value = _text(data, key);
      if (value.isNotEmpty && !pattern.hasMatch(value)) {
        throw StateError('فیلد «' + key + '» فقط باید عدد باشد.');
      }
    }
  }

  /// Copies legacy JSON rows to the normalized schema once, without deleting
  /// or rewriting any original row.
  static Future<void> migrateLegacyRecords(DatabaseExecutor db) async {
    final rows = await db.query('records', orderBy: 'id ASC');
    if (rows.isEmpty) return;

    final customerIdsByName = <String, int>{};
    for (final row in rows.where((r) => r['category'] == 'customers')) {
      final legacyId = row['id'] as int;
      final data = _decode(row['data']);
      final fullName = _text(data, 'نام مشتری');
      final parts = fullName.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
      final customerId = await db.insert('customers', {
        'first_name': parts.isEmpty ? '' : parts.first,
        'last_name': parts.length < 2 ? '' : parts.skip(1).join(' '),
        'phone': _text(data, 'شماره تماس'),
        'address': _text(data, 'آدرس'),
        'notes': _text(data, 'توضیحات'),
        'created_at': _text(row, 'created_at').isEmpty
            ? DateTime.now().toIso8601String()
            : _text(row, 'created_at'),
        'legacy_source_id': legacyId,
      });
      if (fullName.isNotEmpty) {
        customerIdsByName.putIfAbsent(fullName, () => customerId);
      }
    }

    for (final row in rows.where((r) => r['category'] == 'products')) {
      final data = _decode(row['data']);
      final unit = _text(data, 'واحد شمارش').isEmpty ? 'عدد' : _text(data, 'واحد شمارش');
      await db.insert('products', {
        'code': _text(data, 'کد کالا'),
        'name': _text(data, 'نام کالا').isEmpty ? 'کالای بدون نام' : _text(data, 'نام کالا'),
        'category': _text(data, 'گروه اصلی'),
        'subcategory': _text(data, 'زیرگروه'),
        'unit': unit,
        'quantity': _number(data, 'موجودی'),
        'purchase_price': _number(data, 'بهای تمام‌شده هر واحد') > 0
            ? _number(data, 'بهای تمام‌شده هر واحد')
            : _number(data, 'قیمت خرید هر واحد'),
        'sale_price': _number(data, 'قیمت فروش'),
        'is_used': _text(data, 'وضعیت کالا') == 'دست دوم' ||
                _text(data, 'این کالا دست دوم است') == 'بله'
            ? 1
            : 0,
        // Keep old image payloads in records to avoid doubling database size.
        'image_base64': '',
        'shipping_cost': _number(data, 'هزینه پست'),
        'freight_cost': _number(data, 'هزینه باربری / حمل'),
        'other_cost': _number(data, 'سایر هزینه‌ها'),
        'vat_rate': _number(data, 'درصد ارزش افزوده'),
        'vat_included': _text(data, 'مشمول ارزش افزوده') == 'بله' ? 1 : 0,
        'created_at': _text(row, 'created_at').isEmpty
            ? DateTime.now().toIso8601String()
            : _text(row, 'created_at'),
        'legacy_source_id': row['id'],
      });
    }

    for (final row in rows.where((r) => r['category'] == 'repairs')) {
      final data = _decode(row['data']);
      final customerName = _text(data, 'نام مشتری');
      await db.insert('repairs', {
        'customer_id': customerIdsByName[customerName],
        'customer_name_snapshot': customerName,
        'device_type': _text(data, 'نوع دستگاه'),
        'problem_description': _text(data, 'شرح عیب'),
        'labor_cost': _number(data, 'اجرت'),
        'status': _text(data, 'وضعیت تعمیر').isEmpty
            ? 'پذیرفته شد'
            : _text(data, 'وضعیت تعمیر'),
        'received_at': _text(row, 'created_at').isEmpty
            ? DateTime.now().toIso8601String()
            : _text(row, 'created_at'),
        'legacy_source_id': row['id'],
      });
    }

    for (final row in rows.where((r) => r['category'] == 'sales')) {
      final data = _decode(row['data']);
      final quantity = _number(data, 'تعداد') <= 0 ? 1 : _number(data, 'تعداد');
      final total = _number(data, 'مبلغ کل');
      final discount = _number(data, 'تخفیف');
      final invoiceId = await db.insert('invoices', {
        'invoice_number': 'LEGACY-' + row['id'].toString(),
        'customer_name_snapshot': _text(data, 'نام مشتری'),
        'subtotal': total,
        'discount': discount,
        'total': (total - discount).clamp(0, total),
        'received_amount': _number(data, 'مبلغ دریافتی'),
        'created_at': _text(row, 'created_at').isEmpty
            ? DateTime.now().toIso8601String()
            : _text(row, 'created_at'),
        'legacy_source_id': row['id'],
      });
      final description = _text(data, 'شرح کالا/خدمت').isEmpty
          ? 'مورد ثبت‌شده در نسخه قبلی'
          : _text(data, 'شرح کالا/خدمت');
      await db.insert('invoice_items', {
        'invoice_id': invoiceId,
        'product_name_snapshot': description,
        'quantity': quantity,
        'unit_price': total / quantity,
        'line_total': total,
      });
    }
  }

  static Future<int> insertCheck(
    DatabaseExecutor db, {
    required String checkNumber,
    required String direction,
    required String partyType,
    required String partyName,
    int? partyId,
    required double amount,
    required DateTime issueDate,
    required DateTime dueDate,
    String bankName = '',
    String notes = '',
    String sourceType = '',
    String? sourceId,
  }) async {
    if (checkNumber.trim().isEmpty || amount <= 0 ||
        !amount.isFinite || !['received', 'issued'].contains(direction) ||
        dueDate.isBefore(issueDate)) {
      throw StateError('شماره، مبلغ یا تاریخ‌های چک معتبر نیستند.');
    }
    final duplicate = await db.query('checks_register',
      columns: ['id'],
      where: 'check_number = ? AND direction = ? AND bank_name = ? AND status != ?',
      whereArgs: [checkNumber.trim(), direction, bankName.trim(), 'cancelled'],
      limit: 1);
    if (duplicate.isNotEmpty) throw StateError('این شماره چک با همین بانک و جهت قبلاً ثبت شده است.');
    final id = await db.insert('checks_register', {
      'check_number': checkNumber.trim(),
      'direction': direction,
      'party_type': partyType,
      'party_id': partyId,
      'party_name_snapshot': partyName.trim(),
      'amount': amount,
      'issue_date': issueDate.toIso8601String(),
      'due_date': dueDate.toIso8601String(),
      'status': 'pending',
      'bank_name': bankName.trim(),
      'notes': notes.trim(),
      'source_type': sourceType,
      'source_id': sourceId,
      'created_at': DateTime.now().toIso8601String(),
    });
    await db.insert('checks_history', {
      'check_id': id,
      'old_status': '',
      'new_status': 'pending',
      'occurred_at': DateTime.now().toIso8601String(),
      'notes': 'ثبت اولیه چک',
    });
    return id;
  }

  /// Adds source-reference columns to check registers created by older builds.
  static Future<void> ensureCheckSourceColumns(DatabaseExecutor db) async {
    final columns = await db.rawQuery('PRAGMA table_info(checks_register)');
    final names = columns.map((row) => row['name'].toString()).toSet();
    if (!names.contains('source_type')) {
      await db.execute("ALTER TABLE checks_register ADD COLUMN source_type TEXT NOT NULL DEFAULT ''");
    }
    if (!names.contains('source_id')) {
      await db.execute('ALTER TABLE checks_register ADD COLUMN source_id TEXT');
    }
  }

  /// Rebuilds missing journal entries for legacy documents that predate the
  /// double-entry ledger. Each source is posted at most once by the journal
  /// source unique index; original JSON documents remain unchanged.
  static Future<void> migrateHistoricalJournals(DatabaseExecutor db) async {
    await AccountingEngine.ensureDefaultAccounts(db);
    // Reconcile normalized on-hand quantities with the movements available
    // before this migration. The difference is a dated opening stock movement.
    final stockProducts = await db.query(
      'products',
      columns: ['id', 'quantity', 'purchase_price', 'created_at'],
      orderBy: 'id ASC',
    );
    for (final product in stockProducts) {
      final productId = product['id'] as int;
      final currentQuantity = (product['quantity'] as num).toDouble();
      final movementRows = await db.rawQuery(
        'SELECT COALESCE(SUM(quantity_delta), 0) AS moved FROM stock_movements WHERE product_id = ?',
        [productId],
      );
      final movedQuantity = (movementRows.first['moved'] as num).toDouble();
      final openingQuantity = currentQuantity - movedQuantity;
      if (openingQuantity.abs() <= 0.000001) continue;
      final firstMovement = await db.query(
        'stock_movements',
        columns: ['occurred_at'],
        where: 'product_id = ?',
        whereArgs: [productId],
        orderBy: 'occurred_at ASC, id ASC',
        limit: 1,
      );
      final firstDate = firstMovement.isEmpty
          ? null : DateTime.tryParse((firstMovement.first['occurred_at'] ?? '').toString());
      final createdAt = DateTime.tryParse((product['created_at'] ?? '').toString());
      final openingDate = firstDate != null
          ? firstDate.subtract(const Duration(microseconds: 1))
          : createdAt ?? DateTime.now();
      final unitCost = (product['purchase_price'] as num).toDouble();
      final openingValue = openingQuantity.abs() * unitCost;
      await db.insert('stock_movements', {
        'product_id': productId,
        'movement_type': 'opening_balance',
        'quantity_delta': openingQuantity,
        'unit_cost': unitCost,
        'total_cost': openingValue,
        'reference_type': 'legacy_opening_balance',
        'reference_id': productId.toString(),
        'occurred_at': openingDate.toIso8601String(),
        'notes': 'مانده افتتاحیه مهاجرت از نسخه قدیمی',
      });
      if (openingValue > 0.0001) {
        final lines = openingQuantity > 0
            ? <JournalLineInput>[
                JournalLineInput(
                  accountId: await AccountingEngine.accountId(db, '1200'),
                  debit: openingValue,
                  memo: 'موجودی افتتاحیه مهاجرت‌شده',
                ),
                JournalLineInput(
                  accountId: await AccountingEngine.accountId(db, '3000'),
                  credit: openingValue,
                  memo: 'طرف مقابل موجودی افتتاحیه',
                ),
              ]
            : <JournalLineInput>[
                JournalLineInput(
                  accountId: await AccountingEngine.accountId(db, '6000'),
                  debit: openingValue,
                  memo: 'کسری موجودی افتتاحیه مهاجرت‌شده',
                ),
                JournalLineInput(
                  accountId: await AccountingEngine.accountId(db, '1200'),
                  credit: openingValue,
                  memo: 'اصلاح مانده موجودی افتتاحیه',
                ),
              ];
        await AccountingEngine.postJournalInTransaction(
          db,
          entryNumber: 'MIG-OPEN-STOCK-' + productId.toString(),
          occurredAt: openingDate,
          description: 'مانده افتتاحیه کالا ' + productId.toString(),
          sourceType: 'legacy_stock_opening',
          sourceId: productId.toString(),
          lines: lines,
        );
      }
    }

    final records = await db.query(
      'records',
      columns: ['id', 'category', 'data', 'created_at'],
      where: 'category IN (?, ?)',
      whereArgs: ['sales', 'operations'],
      orderBy: 'id ASC',
    );

    Future<double> balanceFor(String code, {String partyType = '', int? partyId}) async {
      final accountId = await AccountingEngine.accountId(db, code);
      final clauses = <String>['account_id = ?'];
      final args = <Object?>[accountId];
      if (partyType.isNotEmpty) {
        clauses.add('party_type = ?');
        args.add(partyType);
      }
      if (partyId != null) {
        clauses.add('party_id = ?');
        args.add(partyId);
      }
      final rows = await db.rawQuery(
        'SELECT COALESCE(SUM(debit - credit), 0) AS balance FROM journal_lines WHERE ' +
          clauses.join(' AND '),
        args,
      );
      return (rows.first['balance'] as num).toDouble();
    }

    for (final record in records) {
      final sourceId = record['id'] as int;
      final category = (record['category'] ?? '').toString();
      final data = _decode(record['data']);
      final operation = _text(data, 'نوع عملیات');
      final isPurchase = category == 'operations' && operation == 'خرید کالا';
      final journalType = category == 'sales' ? 'sale' : isPurchase ? 'purchase' : 'operation';
      final exists = await db.query(
        'journal_entries',
        columns: ['id'],
        where: 'source_type = ? AND source_id = ?',
        whereArgs: [journalType, sourceId.toString()],
        limit: 1,
      );
      if (exists.isNotEmpty) continue;

      final date = DateTime.tryParse(_text(data, 'تاریخ میلادی')) ??
          DateTime.tryParse(_text(data, 'تاریخ')) ??
          DateTime.tryParse((record['created_at'] ?? '').toString()) ??
          DateTime.now();
      final lines = <JournalLineInput>[];

      if (category == 'sales') {
        final gross = _number(data, 'مبلغ کل');
        final discount = _number(data, 'تخفیف');
        final tax = _number(data, 'مبلغ مالیات');
        final received = _number(data, 'مبلغ دریافتی');
        final deposit = _number(data, 'بیعانه تخصیص‌یافته');
        final total = gross - discount + tax;
        if (gross < 0 || discount < 0 || tax < 0 || received < 0 ||
            deposit < 0 || discount > gross || deposit > total + 0.01) {
          continue;
        }
        final customerIdValue = int.tryParse(_text(data, 'شناسه مشتری'));
        final method = _text(data, 'روش پرداخت');
        if (received > 0) {
          final cashCode = method == 'چک' ? '1020'
              : (method.contains('کارت') || method.contains('حواله')) ? '1010' : '1000';
          lines.add(JournalLineInput(
            accountId: await AccountingEngine.accountId(db, cashCode),
            debit: received,
            memo: 'دریافت فاکتور قدیمی ' + _text(data, 'شماره فاکتور'),
          ));
        }
        if (deposit > 0) {
          lines.add(JournalLineInput(
            accountId: await AccountingEngine.accountId(db, '2010'),
            debit: deposit,
            partyType: 'customer',
            partyId: customerIdValue,
            memo: 'مصرف بیعانه در فاکتور قدیمی',
          ));
        }
        final settled = received + deposit;
        if (settled < total - 0.001) {
          lines.add(JournalLineInput(
            accountId: await AccountingEngine.accountId(db, '1100'),
            debit: total - settled,
            partyType: 'customer',
            partyId: customerIdValue,
            memo: 'مانده فاکتور قدیمی',
          ));
        } else if (settled > total + 0.001) {
          lines.add(JournalLineInput(
            accountId: await AccountingEngine.accountId(db, '2010'),
            credit: settled - total,
            partyType: 'customer',
            partyId: customerIdValue,
            memo: 'اعتبار مازاد فاکتور قدیمی',
          ));
        }
        if (gross > 0) {
          final productId = _text(data, 'شناسه کالای انبار');
          final revenueCode = productId.isEmpty && _text(data, 'کالای انبار').isEmpty
              ? '4010' : '4000';
          lines.add(JournalLineInput(
            accountId: await AccountingEngine.accountId(db, revenueCode),
            credit: gross,
            memo: 'درآمد فاکتور قدیمی ' + _text(data, 'شماره فاکتور'),
          ));
        }
        if (discount > 0) {
          lines.add(JournalLineInput(
            accountId: await AccountingEngine.accountId(db, '4110'),
            debit: discount,
            memo: 'تخفیف فاکتور قدیمی',
          ));
        }
        if (tax > 0) {
          lines.add(JournalLineInput(
            accountId: await AccountingEngine.accountId(db, '2200'),
            credit: tax,
            memo: 'مالیات فاکتور قدیمی',
          ));
        }
      } else if (isPurchase) {
        final total = _number(data, 'مبلغ');
        final paid = _number(data, 'مبلغ پرداخت‌شده');
        if (total <= 0 || paid < 0 || paid > total + 0.01) {
          continue;
        }
        final supplierName = _text(data, 'نام شخص');
        final supplierIdValue = int.tryParse(_text(data, 'شناسه فروشنده')) ??
            await ensureSupplier(db, supplierName);
        final method = _text(data, 'روش');
        lines.add(JournalLineInput(
          accountId: await AccountingEngine.accountId(db, '1200'),
          debit: total,
          memo: 'موجودی بابت خرید قدیمی ' + sourceId.toString(),
        ));
        if (paid > 0) {
          final creditCode = method == 'چک' ? '2110'
              : (method.contains('کارت') || method.contains('حواله')) ? '1010' : '1000';
          lines.add(JournalLineInput(
            accountId: await AccountingEngine.accountId(db, creditCode),
            credit: paid,
            memo: 'پرداخت خرید قدیمی به ' + supplierName,
          ));
        }
        if (total - paid > 0.01) {
          lines.add(JournalLineInput(
            accountId: await AccountingEngine.accountId(db, '2000'),
            credit: total - paid,
            partyType: 'supplier',
            partyId: supplierIdValue,
            memo: 'بدهی خرید قدیمی به ' + supplierName,
          ));
        }
        data['شناسه فروشنده'] = supplierIdValue.toString();
        await db.update('records', {'data': jsonEncode(data)},
          where: 'id = ?', whereArgs: [sourceId]);
      } else if (category == 'operations') {
        final partyName = _text(data, 'نام شخص');
        final partyTypeLabel = _text(data, 'نوع طرف حساب').isEmpty
            ? 'مشتری' : _text(data, 'نوع طرف حساب');
        final amount = _number(data, 'مبلغ');
        if (amount <= 0 || partyName.isEmpty) continue;
        final customerIdValue = partyTypeLabel == 'مشتری'
            ? (int.tryParse(_text(data, 'شناسه مشتری')) ??
              await _findCustomerId(db, partyName))
            : null;
        final supplierIdValue = partyTypeLabel == 'فروشنده'
            ? (int.tryParse(_text(data, 'شناسه فروشنده')) ??
              await ensureSupplier(db, partyName))
            : null;
        final partyType = partyTypeLabel == 'مشتری' ? 'customer'
            : partyTypeLabel == 'فروشنده' ? 'supplier' : '';
        if (customerIdValue != null) data['شناسه مشتری'] = customerIdValue.toString();
        if (supplierIdValue != null) data['شناسه فروشنده'] = supplierIdValue.toString();
        final method = _text(data, 'روش');
        final isReceipt = operation == 'دریافت وجه' || operation == 'ثبت بیعانه';
        final isPayment = operation == 'پرداخت وجه';
        final isDiscountGiven = operation == 'تخفیف دادن' || operation == 'تخفیف دادن به مشتری';
        final isDiscountReceived = operation == 'تخفیف گرفتن' || operation == 'تخفیف گرفتن از فروشنده';
        final isPartyOwes = operation == 'متفرقه شخص بدهکار';
        final isWeOwe = operation == 'متفرقه شخص بستانکار';
        final partyId = customerIdValue ?? supplierIdValue;

        if (isReceipt) {
          final cashCode = method == 'چک' ? '1020'
              : (method.contains('کارت') || method.contains('حواله')) ? '1010' : '1000';
          lines.add(JournalLineInput(
            accountId: await AccountingEngine.accountId(db, cashCode),
            debit: amount,
            memo: 'دریافت قدیمی از ' + partyName,
          ));
          if (partyType == 'customer') {
            final receivable = operation == 'ثبت بیعانه' ? 0.0
                : (await balanceFor('1100', partyType: partyType, partyId: partyId))
                    .clamp(0.0, amount).toDouble();
            if (receivable > 0) {
              lines.add(JournalLineInput(
                accountId: await AccountingEngine.accountId(db, '1100'),
                credit: receivable,
                partyType: partyType,
                partyId: partyId,
                memo: 'تسویه دریافتنی قدیمی',
              ));
            }
            if (amount - receivable > 0.001) {
              lines.add(JournalLineInput(
                accountId: await AccountingEngine.accountId(db, '2010'),
                credit: amount - receivable,
                partyType: partyType,
                partyId: partyId,
                memo: 'اعتبار / بیعانه قدیمی مشتری',
              ));
            }
          } else if (partyType == 'supplier') {
            lines.add(JournalLineInput(
              accountId: await AccountingEngine.accountId(db, '1110'),
              credit: amount,
              partyType: partyType,
              partyId: partyId,
              memo: 'دریافت از فروشنده',
            ));
          } else {
            lines.add(JournalLineInput(
              accountId: await AccountingEngine.accountId(db, '4000'),
              credit: amount,
              memo: 'دریافت متفرقه قدیمی',
            ));
          }
        } else if (isPayment) {
          final cashCode = method == 'چک' ? '2110'
              : (method.contains('کارت') || method.contains('حواله')) ? '1010' : '1000';
          lines.add(JournalLineInput(
            accountId: await AccountingEngine.accountId(db, cashCode),
            credit: amount,
            memo: 'پرداخت قدیمی به ' + partyName,
          ));
          if (partyType == 'supplier') {
            final payable = (-(await balanceFor('2000', partyType: partyType, partyId: partyId)))
                .clamp(0.0, amount).toDouble();
            if (payable > 0) {
              lines.add(JournalLineInput(
                accountId: await AccountingEngine.accountId(db, '2000'),
                debit: payable,
                partyType: partyType,
                partyId: partyId,
                memo: 'کاهش بدهی فروشنده',
              ));
            }
            if (amount - payable > 0.001) {
              lines.add(JournalLineInput(
                accountId: await AccountingEngine.accountId(db, '1110'),
                debit: amount - payable,
                partyType: partyType,
                partyId: partyId,
                memo: 'پیش‌پرداخت به فروشنده',
              ));
            }
          } else if (partyType == 'customer') {
            final credit = (-(await balanceFor('2010', partyType: partyType, partyId: partyId)))
                .clamp(0.0, amount).toDouble();
            if (credit > 0) {
              lines.add(JournalLineInput(
                accountId: await AccountingEngine.accountId(db, '2010'),
                debit: credit,
                partyType: partyType,
                partyId: partyId,
                memo: 'بازپرداخت اعتبار مشتری',
              ));
            }
            if (amount - credit > 0.001) {
              lines.add(JournalLineInput(
                accountId: await AccountingEngine.accountId(db, '6000'),
                debit: amount - credit,
                memo: 'پرداخت متفرقه به مشتری',
              ));
            }
          } else {
            lines.add(JournalLineInput(
              accountId: await AccountingEngine.accountId(db, '6000'),
              debit: amount,
              memo: 'هزینه پرداختی قدیمی',
            ));
          }
        } else if (isDiscountGiven) {
          final receivable = partyType == 'customer' && partyId != null
              ? (await balanceFor('1100', partyType: partyType, partyId: partyId))
                  .clamp(0.0, amount).toDouble() : 0.0;
          lines.add(JournalLineInput(
            accountId: await AccountingEngine.accountId(db, '4110'),
            debit: amount,
            memo: 'تخفیف قدیمی مشتری',
          ));
          if (receivable > 0) {
            lines.add(JournalLineInput(
              accountId: await AccountingEngine.accountId(db, '1100'),
              credit: receivable,
              partyType: partyType,
              partyId: partyId,
              memo: 'کاهش دریافتنی بابت تخفیف',
            ));
          }
          if (amount - receivable > 0.001) {
            lines.add(JournalLineInput(
              accountId: await AccountingEngine.accountId(db, '2010'),
              credit: amount - receivable,
              partyType: partyType,
              partyId: partyId,
              memo: 'اعتبار تخفیف مشتری',
            ));
          }
        } else if (isDiscountReceived && partyType == 'supplier') {
          final payable = (-(await balanceFor('2000', partyType: partyType, partyId: partyId)))
              .clamp(0.0, amount).toDouble();
          if (payable > 0) {
            lines.add(JournalLineInput(
              accountId: await AccountingEngine.accountId(db, '2000'),
              debit: payable,
              partyType: partyType,
              partyId: partyId,
              memo: 'کاهش بدهی بابت تخفیف فروشنده',
            ));
          }
          if (amount - payable > 0.001) {
            lines.add(JournalLineInput(
              accountId: await AccountingEngine.accountId(db, '1110'),
              debit: amount - payable,
              partyType: partyType,
              partyId: partyId,
              memo: 'طلب مازاد از فروشنده',
            ));
          }
          lines.add(JournalLineInput(
            accountId: await AccountingEngine.accountId(db, '6010'),
            credit: amount,
            memo: 'تخفیف خرید قدیمی',
          ));
        } else if (isPartyOwes) {
          lines.add(JournalLineInput(
            accountId: await AccountingEngine.accountId(db, partyType == 'supplier' ? '1110' : '1100'),
            debit: amount,
            partyType: partyType,
            partyId: partyId,
            memo: 'ثبت بدهکاری قدیمی ' + partyName,
          ));
          lines.add(JournalLineInput(
            accountId: await AccountingEngine.accountId(db, '4000'),
            credit: amount,
            memo: 'درآمد / طلب متفرقه قدیمی',
          ));
        } else if (isWeOwe) {
          lines.add(JournalLineInput(
            accountId: await AccountingEngine.accountId(db, '6000'),
            debit: amount,
            memo: 'هزینه / بستانکاری متفرقه قدیمی',
          ));
          lines.add(JournalLineInput(
            accountId: await AccountingEngine.accountId(db, partyType == 'customer' ? '2010' : '2000'),
            credit: amount,
            partyType: partyType,
            partyId: partyId,
            memo: 'بستانکاری متفرقه قدیمی',
          ));
        }

        if (partyId != null) {
          await db.update('records', {'data': jsonEncode(data)},
            where: 'id = ?', whereArgs: [sourceId]);
        }
      }

      if (lines.length >= 2) {
        await AccountingEngine.postJournalInTransaction(
          db,
          entryNumber: (journalType == 'sale' ? 'MIG-SALE-' :
              journalType == 'purchase' ? 'MIG-PUR-' : 'MIG-OP-') + sourceId.toString(),
          occurredAt: date,
          description: 'مهاجرت سند قدیمی ' + sourceId.toString(),
          sourceType: journalType,
          sourceId: sourceId.toString(),
          lines: lines,
        );
      }
    }
  }

  static Future<int?> _findCustomerId(DatabaseExecutor db, String customerName) async {
    if (customerName.trim().isEmpty) return null;
    final rows = await db.query(
      'customers',
      columns: ['id'],
      where: "TRIM(first_name || ' ' || last_name) = ?",
      whereArgs: [customerName.trim()],
      limit: 2,
    );
    return rows.length == 1 ? rows.first['id'] as int : null;
  }

  /// Synchronizes editable legacy records with normalized tables.
  static Future<void> updateLegacyRecord(
    DatabaseExecutor db,
    String category,
    Map<String, String> item,
    int sourceId,
  ) async {
    if (category == 'customers') {
      final rows = await db.query(
        'customers',
        columns: ['id'],
        where: 'legacy_source_id = ?',
        whereArgs: [sourceId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('پرونده مشتری در پایگاه داده پیدا نشد.');
      final customerId = rows.first['id'] as int;
      final phone = _text(item, 'شماره تماس');
      if (phone.isNotEmpty && (phone.length != 11 || int.tryParse(phone) == null)) {
        throw StateError('شماره موبایل در صورت ورود باید دقیقاً ۱۱ رقم باشد.');
      }
      if (phone.isNotEmpty) {
        final duplicate = await db.query(
          'customers',
          columns: ['id'],
          where: 'phone = ? AND id != ?',
          whereArgs: [phone, customerId],
          limit: 1,
        );
        if (duplicate.isNotEmpty) throw StateError('این شماره موبایل برای مشتری دیگری ثبت شده است.');
      }
      final parts = _text(item, 'نام مشتری')
          .split(RegExp(r'\s+'))
          .where((part) => part.isNotEmpty)
          .toList();
      await db.update(
        'customers',
        {
          'first_name': parts.isEmpty ? '' : parts.first,
          'last_name': parts.length < 2 ? '' : parts.skip(1).join(' '),
          'phone': phone,
          'address': _text(item, 'آدرس'),
          'notes': _text(item, 'توضیحات'),
        },
        where: 'id = ?',
        whereArgs: [customerId],
      );
    } else if (category == 'products') {
      final rows = await db.query(
        'products',
        columns: ['id', 'quantity', 'purchase_price'],
        where: 'legacy_source_id = ?',
        whereArgs: [sourceId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('کالای موردنظر در پایگاه داده پیدا نشد.');
      final productId = rows.first['id'] as int;
      final unit = _text(item, 'واحد شمارش').isEmpty ? 'عدد' : _text(item, 'واحد شمارش');
      _assertNumeric(item, [
        'کد کالا', 'قیمت خرید هر واحد', 'قیمت فروش',
        'هزینه پست', 'هزینه باربری / حمل', 'سایر هزینه‌ها',
      ]);
      _assertNumeric(item, ['موجودی'], allowDecimal: unit != 'عدد');
      final oldQuantity = (rows.first['quantity'] as num).toDouble();
      final newQuantity = _number(item, 'موجودی');
      final delta = newQuantity - oldQuantity;
      if (delta.abs() > 0.000001) {
        final oldCost = (rows.first['purchase_price'] as num).toDouble();
        final now = DateTime.now();
        final reference = sourceId.toString() + '-' + now.microsecondsSinceEpoch.toString();
        await AccountingEngine.recordStockMovementInTransaction(
          db,
          productId: productId,
          movementType: 'manual_adjustment',
          quantityDelta: delta,
          unitCost: oldCost,
          referenceType: 'product_edit',
          referenceId: reference,
          notes: 'اصلاح موجودی از فرم ویرایش کالا',
          occurredAt: now,
        );
        final amount = delta.abs() * oldCost;
        if (amount > 0) {
          final lines = delta > 0
              ? <JournalLineInput>[
                  JournalLineInput(
                    accountId: await AccountingEngine.accountId(db, '1200'),
                    debit: amount,
                    memo: 'افزایش موجودی با اصلاح دستی',
                  ),
                  JournalLineInput(
                    accountId: await AccountingEngine.accountId(db, '3000'),
                    credit: amount,
                    memo: 'طرف مقابل اصلاح موجودی',
                  ),
                ]
              : <JournalLineInput>[
                  JournalLineInput(
                    accountId: await AccountingEngine.accountId(db, '6000'),
                    debit: amount,
                    memo: 'کسری موجودی با اصلاح دستی',
                  ),
                  JournalLineInput(
                    accountId: await AccountingEngine.accountId(db, '1200'),
                    credit: amount,
                    memo: 'کاهش موجودی با اصلاح دستی',
                  ),
                ];
          await AccountingEngine.postJournalInTransaction(
            db,
            entryNumber: 'STOCK-EDIT-' + reference,
            occurredAt: now,
            description: 'سند اصلاح دستی موجودی ' + _text(item, 'نام کالا'),
            sourceType: 'stock_adjustment',
            sourceId: reference,
            lines: lines,
          );
        }
      }
      final landedCost = _number(item, 'بهای تمام‌شده هر واحد');
      await db.update(
        'products',
        {
          'code': _text(item, 'کد کالا'),
          'name': _text(item, 'نام کالا').isEmpty ? 'کالای بدون نام' : _text(item, 'نام کالا'),
          'category': _text(item, 'گروه اصلی'),
          'subcategory': _text(item, 'زیرگروه'),
          'unit': unit,
          'purchase_price': landedCost > 0 ? landedCost : _number(item, 'قیمت خرید هر واحد'),
          'sale_price': _number(item, 'قیمت فروش'),
          'is_used': _text(item, 'وضعیت کالا') == 'دست دوم' ? 1 : 0,
          'shipping_cost': _number(item, 'هزینه پست'),
          'freight_cost': _number(item, 'هزینه باربری / حمل'),
          'other_cost': _number(item, 'سایر هزینه‌ها'),
          'vat_rate': _number(item, 'درصد ارزش افزوده'),
          'vat_included': _text(item, 'مشمول ارزش افزوده') == 'بله' ? 1 : 0,
          'image_base64': _text(item, 'تصویر کالا'),
        },
        where: 'id = ?',
        whereArgs: [productId],
      );
    } else if (category == 'repairs') {
      _assertNumeric(item, ['اجرت']);
      final repairRows = await db.query(
        'repairs',
        columns: ['id'],
        where: 'legacy_source_id = ?',
        whereArgs: [sourceId],
        limit: 1,
      );
      if (repairRows.isEmpty) throw StateError('پذیرش تعمیر برای ویرایش پیدا نشد.');
      final customerName = _text(item, 'نام مشتری');
      final explicitCustomerId = int.tryParse(_text(item, 'شناسه مشتری'));
      int? repairCustomerId;
      if (explicitCustomerId != null) {
        final selected = await db.query(
          'customers',
          columns: ['id', 'first_name', 'last_name'],
          where: 'id = ?',
          whereArgs: [explicitCustomerId],
          limit: 1,
        );
        if (selected.isEmpty) throw StateError('پرونده مشتری انتخاب‌شده برای پذیرش تعمیر پیدا نشد.');
        final selectedName = ((selected.first['first_name'] ?? '').toString() + ' ' +
          (selected.first['last_name'] ?? '').toString()).trim();
        if (selectedName != customerName) {
          throw StateError('نام مشتری با پرونده انتخاب‌شده مطابقت ندارد.');
        }
        repairCustomerId = explicitCustomerId;
      } else {
        repairCustomerId = await _findCustomerId(db, customerName);
        final matches = await db.query(
          'customers',
          columns: ['id'],
          where: "TRIM(first_name || ' ' || last_name) = ?",
          whereArgs: [customerName],
          limit: 2,
        );
        if (matches.length > 1) {
          throw StateError('نام مشتری تکراری است؛ پرونده دقیق مشتری را انتخاب کنید.');
        }
      }
      await db.update(
        'repairs',
        {
          'customer_id': repairCustomerId,
          'customer_name_snapshot': customerName,
          'device_type': _text(item, 'نوع دستگاه'),
          'problem_description': _text(item, 'شرح عیب'),
          'labor_cost': _number(item, 'اجرت'),
          'status': _text(item, 'وضعیت تعمیر').isEmpty ? 'پذیرفته شد' : _text(item, 'وضعیت تعمیر'),
        },
        where: 'id = ?',
        whereArgs: [repairRows.first['id']],
      );
    } else if (category != 'operations') {
      throw ArgumentError('ویرایش این دسته اطلاعات پشتیبانی نمی‌شود: ' + category);
    }
  }

  /// Mirrors new writes into normalized tables in the legacy JSON transaction.
  static Future<void> insertLegacyRecord(
    DatabaseExecutor db,
    String category,
    Map<String, String> item,
    int sourceId,
    String createdAt,
  ) async {
    final data = Map<String, Object?>.from(item);
    if (category == 'customers') {
      final phone = _text(data, 'شماره تماس');
      if (phone.isNotEmpty && !RegExp(r'^\d{11}$').hasMatch(phone)) {
        throw StateError('شماره موبایل در صورت ورود باید دقیقاً ۱۱ رقم باشد.');
      }
      if (phone.isNotEmpty) {
        final duplicate = await db.query(
          'customers',
          columns: ['id'],
          where: 'phone = ?',
          whereArgs: [phone],
          limit: 1,
        );
        if (duplicate.isNotEmpty) {
          throw StateError('این شماره موبایل قبلاً ثبت شده است.');
        }
      }
      final fullName = _text(data, 'نام مشتری');
      final parts = fullName.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
      await db.insert('customers', {
        'first_name': parts.isEmpty ? '' : parts.first,
        'last_name': parts.length < 2 ? '' : parts.skip(1).join(' '),
        'phone': phone,
        'address': _text(data, 'آدرس'),
        'notes': _text(data, 'توضیحات'),
        'created_at': createdAt,
        'legacy_source_id': sourceId,
      });
    } else if (category == 'products') {
      final unit = _text(data, 'واحد شمارش').isEmpty ? 'عدد' : _text(data, 'واحد شمارش');
      _assertNumeric(data, ['کد کالا', 'قیمت خرید هر واحد', 'قیمت فروش', 'هزینه پست', 'هزینه باربری / حمل', 'سایر هزینه‌ها']);
      _assertNumeric(data, ['موجودی'], allowDecimal: unit != 'عدد');
      _assertNumeric(data, ['درصد ارزش افزوده'], allowDecimal: true);
      final openingQuantity = _number(data, 'موجودی');
      final initialUnitCost = _number(data, 'بهای تمام‌شده هر واحد') > 0
          ? _number(data, 'بهای تمام‌شده هر واحد')
          : _number(data, 'قیمت خرید هر واحد');
      if (openingQuantity > 0 && initialUnitCost <= 0) {
        throw StateError('برای موجودی اولیه، بهای خرید یا بهای تمام‌شده هر واحد را وارد کنید.');
      }
      final normalizedProductId = await db.insert('products', {
        'code': _text(data, 'کد کالا'),
        'name': _text(data, 'نام کالا').isEmpty ? 'کالای بدون نام' : _text(data, 'نام کالا'),
        'category': _text(data, 'گروه اصلی'),
        'subcategory': _text(data, 'زیرگروه'),
        'unit': unit,
        'quantity': openingQuantity,
        'purchase_price': initialUnitCost,
        'sale_price': _number(data, 'قیمت فروش'),
        'is_used': _text(data, 'وضعیت کالا') == 'دست دوم' ? 1 : 0,
        // Image bytes remain in the legacy row until file-based image storage.
        'image_base64': '',
        'shipping_cost': _number(data, 'هزینه پست'),
        'freight_cost': _number(data, 'هزینه باربری / حمل'),
        'other_cost': _number(data, 'سایر هزینه‌ها'),
        'vat_rate': _number(data, 'درصد ارزش افزوده'),
        'vat_included': _text(data, 'مشمول ارزش افزوده') == 'بله' ? 1 : 0,
        'created_at': createdAt,
        'legacy_source_id': sourceId,
      });
      if (openingQuantity > 0) {
        final openingValue = openingQuantity * initialUnitCost;
        await db.insert('stock_movements', {
          'product_id': normalizedProductId,
          'movement_type': 'opening_balance',
          'quantity_delta': openingQuantity,
          'unit_cost': initialUnitCost,
          'total_cost': openingValue,
          'reference_type': 'stock_opening',
          'reference_id': sourceId.toString(),
          'occurred_at': createdAt,
          'notes': 'موجودی اولیه هنگام ثبت کالا',
        });
        await AccountingEngine.postJournalInTransaction(
          db,
          entryNumber: 'OPEN-STOCK-' + sourceId.toString(),
          occurredAt: DateTime.tryParse(createdAt) ?? DateTime.now(),
          description: 'ثبت موجودی اولیه کالا ' + _text(data, 'نام کالا'),
          sourceType: 'stock_opening',
          sourceId: sourceId.toString(),
          lines: [
            JournalLineInput(
              accountId: await AccountingEngine.accountId(db, '1200'),
              debit: openingValue,
              memo: 'موجودی اولیه انبار',
            ),
            JournalLineInput(
              accountId: await AccountingEngine.accountId(db, '3000'),
              credit: openingValue,
              memo: 'سرمایه اولیه موجودی',
            ),
          ],
        );
      }
    } else if (category == 'repairs') {
      _assertNumeric(data, ['اجرت']);
      final customerName = _text(data, 'نام مشتری');
      final explicitCustomerId = int.tryParse(_text(data, 'شناسه مشتری'));
      int? repairCustomerId;
      if (explicitCustomerId != null) {
        final selected = await db.query(
          'customers',
          columns: ['id', 'first_name', 'last_name'],
          where: 'id = ?',
          whereArgs: [explicitCustomerId],
          limit: 1,
        );
        if (selected.isEmpty) throw StateError('پرونده مشتری انتخاب‌شده برای پذیرش تعمیر پیدا نشد.');
        final selectedName = ((selected.first['first_name'] ?? '').toString() + ' ' +
          (selected.first['last_name'] ?? '').toString()).trim();
        if (selectedName != customerName) {
          throw StateError('نام مشتری پذیرش با پرونده انتخاب‌شده مطابقت ندارد.');
        }
        repairCustomerId = explicitCustomerId;
      } else {
        repairCustomerId = await _findCustomerId(db, customerName);
        final matches = await db.query(
          'customers',
          columns: ['id'],
          where: "TRIM(first_name || ' ' || last_name) = ?",
          whereArgs: [customerName],
          limit: 2,
        );
        if (matches.length > 1) {
          throw StateError('نام مشتری پذیرش تکراری است؛ پرونده دقیق مشتری را انتخاب کنید.');
        }
      }
      await db.insert('repairs', {
        'customer_id': repairCustomerId,
        'customer_name_snapshot': customerName,
        'device_type': _text(data, 'نوع دستگاه'),
        'problem_description': _text(data, 'شرح عیب'),
        'labor_cost': _number(data, 'اجرت'),
        'status': _text(data, 'وضعیت تعمیر').isEmpty
            ? 'پذیرفته شد'
            : _text(data, 'وضعیت تعمیر'),
        'received_at': createdAt,
        'legacy_source_id': sourceId,
      });
    } else if (category == 'sales') {
      _assertNumeric(data, ['تعداد', 'مبلغ کل', 'تخفیف', 'مبلغ دریافتی', 'مبلغ مالیات']);
      final quantity = _number(data, 'تعداد');
      final gross = _number(data, 'مبلغ کل');
      final discount = _number(data, 'تخفیف');
      final tax = _number(data, 'مبلغ مالیات');
      final received = _number(data, 'مبلغ دریافتی');
      if (quantity <= 0 || gross < 0 || discount < 0 || tax < 0 || received < 0) {
        throw StateError('تعداد و مبالغ فاکتور باید معتبر و نامنفی باشند.');
      }
      if (discount > gross) {
        throw StateError('تخفیف نمی‌تواند از مبلغ کل فاکتور بیشتر باشد.');
      }
      final total = gross - discount + tax;
      final customerIdValue = int.tryParse(_text(data, 'شناسه مشتری'));
      final invoiceNumber = _text(data, 'شماره فاکتور').isEmpty
          ? 'LEGACY-' + sourceId.toString()
          : _text(data, 'شماره فاکتور');
      final invoiceId = await db.insert('invoices', {
        'invoice_number': invoiceNumber,
        'customer_id': customerIdValue,
        'customer_name_snapshot': _text(data, 'نام مشتری'),
        'subtotal': gross,
        'discount': discount,
        'tax': tax,
        'total': total,
        'received_amount': received,
        'created_at': createdAt,
        'notes': _text(data, 'توضیحات فاکتور'),
        'legacy_source_id': sourceId,
      });

      final structuredLinesJson = _text(data, 'ردیف‌های فاکتور');
      final rawInvoiceLines = <Map<String, Object?>>[];
      if (structuredLinesJson.isNotEmpty) {
        final decodedLines = jsonDecode(structuredLinesJson);
        if (decodedLines is! List || decodedLines.isEmpty) {
          throw StateError('ردیف‌های فاکتور معتبر نیستند.');
        }
        for (final rawLine in decodedLines) {
          if (rawLine is! Map) throw StateError('ساختار یکی از ردیف‌های فاکتور معتبر نیست.');
          rawInvoiceLines.add(rawLine.map(
            (key, value) => MapEntry(key.toString(), value),
          ));
        }
      } else {
        rawInvoiceLines.add({
          'product_id': _text(data, 'شناسه کالای انبار'),
          'description': _text(data, 'کالای انبار').isNotEmpty
              ? _text(data, 'کالای انبار')
              : (_text(data, 'شرح کالا/خدمت').isEmpty
                  ? 'مورد ثبت‌شده در نسخه قبلی' : _text(data, 'شرح کالا/خدمت')),
          'unit': _text(data, 'واحد شمارش').isEmpty ? 'عدد' : _text(data, 'واحد شمارش'),
          'quantity': quantity,
          'unit_price': gross / quantity,
          'line_total': gross,
        });
      }

      double costOfGoods = 0;
      double productRevenue = 0;
      double serviceRevenue = 0;
      double computedLineGross = 0;
      final stockByProduct = <int, Map<String, double>>{};
      for (final rawLine in rawInvoiceLines) {
        final lineQuantityRaw = rawLine['quantity'];
        final lineTotalRaw = rawLine['line_total'];
        final lineUnitPriceRaw = rawLine['unit_price'];
        final lineQuantity = lineQuantityRaw is num
            ? lineQuantityRaw.toDouble() : double.tryParse(lineQuantityRaw?.toString() ?? '') ?? 0;
        final lineTotal = lineTotalRaw is num
            ? lineTotalRaw.toDouble() : double.tryParse(lineTotalRaw?.toString() ?? '') ?? 0;
        final lineUnitPrice = lineUnitPriceRaw is num
            ? lineUnitPriceRaw.toDouble() : double.tryParse(lineUnitPriceRaw?.toString() ?? '') ?? 0;
        if (!lineQuantity.isFinite || lineQuantity <= 0 ||
            !lineTotal.isFinite || lineTotal < 0 ||
            !lineUnitPrice.isFinite || lineUnitPrice < 0 ||
            (lineQuantity * lineUnitPrice - lineTotal).abs() > 0.02) {
          throw StateError('تعداد یا مبلغ یکی از ردیف‌های فاکتور نامعتبر است.');
        }
        computedLineGross += lineTotal;
        var productId = int.tryParse((rawLine['product_id'] ?? '').toString());
        final lineDescription = (rawLine['description'] ?? '').toString().trim();
        final lineUnit = (rawLine['unit'] ?? 'عدد').toString();
        if (productId == null && structuredLinesJson.isEmpty &&
            _text(data, 'کالای انبار').trim().isNotEmpty) {
          final legacyProductRows = await db.query(
            'products',
            columns: ['id'],
            where: 'name = ?',
            whereArgs: [_text(data, 'کالای انبار').trim()],
            limit: 2,
          );
          if (legacyProductRows.length > 1) {
            throw StateError('نام کالای فاکتور قدیمی تکراری است؛ پیش از مهاجرت باید شناسه کالا تعیین شود.');
          }
          if (legacyProductRows.length == 1) {
            productId = legacyProductRows.first['id'] as int;
          }
        }
        if (productId != null) {
          final matches = await db.query(
            'products',
            columns: ['id', 'name', 'quantity', 'purchase_price', 'is_used', 'unit'],
            where: 'id = ?',
            whereArgs: [productId],
            limit: 1,
          );
          if (matches.isEmpty) throw StateError('یکی از کالاهای فاکتور در انبار پیدا نشد.');
          final product = matches.first;
          final unitCost = await AccountingEngine.averageUnitCost(
            db,
            productId,
            fallback: (product['purchase_price'] as num).toDouble(),
          );
          costOfGoods += unitCost * lineQuantity;
          productRevenue += lineTotal;
          final aggregate = stockByProduct.putIfAbsent(
            productId,
            () => {'quantity': 0.0, 'cost': 0.0},
          );
          aggregate['quantity'] = aggregate['quantity']! + lineQuantity;
          aggregate['cost'] = aggregate['cost']! + unitCost * lineQuantity;
          await db.insert('invoice_items', {
            'invoice_id': invoiceId,
            'product_id': productId,
            'product_name_snapshot': (product['name'] ?? lineDescription).toString(),
            'unit': lineUnit.isEmpty ? (product['unit'] ?? 'عدد') : lineUnit,
            'is_used': (product['is_used'] == 1 || rawLine['is_used'] == '1') ? 1 : 0,
            'quantity': lineQuantity,
            'unit_price': lineUnitPrice,
            'line_total': lineTotal,
          });
        } else {
          if (lineDescription.isEmpty) throw StateError('شرح یکی از ردیف‌های خدمت خالی است.');
          serviceRevenue += lineTotal;
          await db.insert('invoice_items', {
            'invoice_id': invoiceId,
            'product_id': null,
            'product_name_snapshot': lineDescription,
            'unit': lineUnit.isEmpty ? 'خدمت' : lineUnit,
            'is_used': 0,
            'quantity': lineQuantity,
            'unit_price': lineUnitPrice,
            'line_total': lineTotal,
          });
        }
      }
      if ((computedLineGross - gross).abs() > 0.02) {
        throw StateError('جمع ردیف‌های فاکتور با مبلغ کل فاکتور برابر نیست.');
      }
      for (final entry in stockByProduct.entries) {
        final productRows = await db.query(
          'products',
          columns: ['quantity'],
          where: 'id = ?',
          whereArgs: [entry.key],
          limit: 1,
        );
        final onHand = (productRows.first['quantity'] as num).toDouble();
        final outgoing = entry.value['quantity']!;
        if (outgoing > onHand + 0.000001) {
          throw StateError('موجودی یکی از کالاهای فاکتور کافی نیست. موجودی فعلی: ' + onHand.toString());
        }
        await AccountingEngine.recordStockMovementInTransaction(
          db,
          productId: entry.key,
          movementType: 'sale',
          quantityDelta: -outgoing,
          unitCost: entry.value['cost']! / outgoing,
          referenceType: 'sale',
          referenceId: sourceId.toString(),
          notes: 'خروج کالا بابت فاکتور ' + invoiceNumber,
        );
      }

      final paymentMethod = _text(data, 'روش پرداخت');
      if (paymentMethod == 'چک' && received > 0) {
        final dueDate = DateTime.tryParse(_text(data, 'تاریخ سررسید میلادی'));
        if (dueDate == null) throw StateError('تاریخ سررسید چک باید انتخاب شود.');
        final issueDate = DateTime.tryParse(_text(data, 'تاریخ میلادی')) ?? DateTime.parse(createdAt);
        await insertCheck(
          db,
          checkNumber: _text(data, 'شماره چک'),
          direction: 'received',
          partyType: 'مشتری',
          partyName: _text(data, 'نام مشتری'),
          partyId: customerIdValue,
          amount: received,
          issueDate: issueDate,
          dueDate: dueDate,
          bankName: _text(data, 'بانک چک'),
          notes: 'دریافت بابت فاکتور ' + invoiceNumber,
          sourceType: 'sale',
          sourceId: sourceId.toString(),
        );
      }

      final lines = <JournalLineInput>[];
      if (received > 0) {
        final method = _text(data, 'روش پرداخت');
        final cashCode = method == 'چک' ? '1020'
            : (method.contains('کارت') || method.contains('حواله')) ? '1010' : '1000';
        lines.add(JournalLineInput(
          accountId: await AccountingEngine.accountId(db, cashCode),
          debit: received,
          memo: 'دریافت فاکتور ' + invoiceNumber,
        ));
      }
      final depositApplied = _number(data, 'بیعانه تخصیص‌یافته');
      if (depositApplied < 0 || depositApplied > total + 0.01) {
        throw StateError('مبلغ بیعانه تخصیص‌یافته به فاکتور نامعتبر است.');
      }
      if (depositApplied > 0) {
        lines.add(JournalLineInput(
          accountId: await AccountingEngine.accountId(db, '2010'),
          debit: depositApplied,
          partyType: 'customer',
          partyId: customerIdValue,
          memo: 'مصرف اعتبار / بیعانه مشتری در فاکتور ' + invoiceNumber,
        ));
      }
      final settledTotal = received + depositApplied;
      if (settledTotal < total) {
        lines.add(JournalLineInput(
          accountId: await AccountingEngine.accountId(db, '1100'),
          debit: total - settledTotal,
          partyType: 'customer',
          partyId: customerIdValue,
          memo: 'مانده فاکتور پس از تخصیص بیعانه ' + invoiceNumber,
        ));
      } else if (settledTotal > total) {
        lines.add(JournalLineInput(
          accountId: await AccountingEngine.accountId(db, '2010'),
          credit: settledTotal - total,
          partyType: 'customer',
          partyId: customerIdValue,
          memo: 'اعتبار مازاد مشتری در فاکتور ' + invoiceNumber,
        ));
      }
      if (productRevenue > 0) {
        lines.add(JournalLineInput(
          accountId: await AccountingEngine.accountId(db, '4000'),
          credit: productRevenue,
          memo: 'فروش قطعات فاکتور ' + invoiceNumber,
        ));
      }
      if (serviceRevenue > 0) {
        lines.add(JournalLineInput(
          accountId: await AccountingEngine.accountId(db, '4010'),
          credit: serviceRevenue,
          memo: 'درآمد خدمات و اجرت فاکتور ' + invoiceNumber,
        ));
      }
      if (discount > 0) {
        lines.add(JournalLineInput(
          accountId: await AccountingEngine.accountId(db, '4110'),
          debit: discount,
          memo: 'تخفیف فاکتور ' + invoiceNumber,
        ));
      }
      if (tax > 0) {
        lines.add(JournalLineInput(
          accountId: await AccountingEngine.accountId(db, '2200'),
          credit: tax,
          memo: 'مالیات فاکتور ' + invoiceNumber,
        ));
      }
      if (costOfGoods > 0) {
        lines.add(JournalLineInput(
          accountId: await AccountingEngine.accountId(db, '5000'),
          debit: costOfGoods,
          memo: 'بهای تمام‌شده فاکتور ' + invoiceNumber,
        ));
        lines.add(JournalLineInput(
          accountId: await AccountingEngine.accountId(db, '1200'),
          credit: costOfGoods,
          memo: 'کاهش موجودی بابت فاکتور ' + invoiceNumber,
        ));
      }
      if (lines.length >= 2) {
        await AccountingEngine.postJournalInTransaction(
          db,
          entryNumber: 'SALE-' + sourceId.toString(),
          occurredAt: DateTime.tryParse(_text(data, 'تاریخ میلادی')) ?? DateTime.parse(createdAt),
          description: 'ثبت فروش ' + invoiceNumber,
          sourceType: 'sale',
          sourceId: sourceId.toString(),
          lines: lines,
        );
      }
    } else if (category == 'operations' || category == 'checks' || category == 'returns' ||
        category == 'stockMovements' || category == 'journalEntries') {
      // These ledgers remain in the canonical JSON records table until their
      // dedicated normalized schema is introduced. No legacy mirror is needed.
    } else {
      throw ArgumentError('دسته اطلاعات نامعتبر است: ' + category);
    }
  }
}

