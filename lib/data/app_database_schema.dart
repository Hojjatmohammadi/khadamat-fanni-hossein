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
      final matches = await db.query(
        'customers',
        columns: ['id'],
        where: "TRIM(first_name || ' ' || last_name) = ?",
        whereArgs: [customerName],
        limit: 2,
      );
      await db.update(
        'repairs',
        {
          'customer_id': matches.length == 1 ? matches.first['id'] : null,
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
      final matches = await db.query(
        'customers',
        columns: ['id'],
        where: "TRIM(first_name || ' ' || last_name) = ?",
        whereArgs: [customerName],
        limit: 2,
      );
      await db.insert('repairs', {
        'customer_id': matches.length == 1 ? matches.first['id'] : null,
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

      final description = _text(data, 'شرح کالا/خدمت').isEmpty
          ? 'مورد ثبت‌شده در نسخه قبلی'
          : _text(data, 'شرح کالا/خدمت');
      final selectedProductName = _text(data, 'کالای انبار');
      final selectedProductId = int.tryParse(_text(data, 'شناسه کالای انبار'));
      int? productId;
      double costOfGoods = 0;
      var productIsUsed = false;
      if (selectedProductName.isNotEmpty || selectedProductId != null) {
        final matches = await db.query(
          'products',
          columns: ['id', 'name', 'quantity', 'purchase_price', 'is_used'],
          where: selectedProductId != null ? 'id = ?' : 'name = ?',
          whereArgs: [selectedProductId ?? selectedProductName],
          limit: 2,
        );
        if (matches.length != 1) {
          throw StateError(matches.isEmpty
              ? 'کالای انتخاب‌شده در انبار پیدا نشد.'
              : 'نام این کالا تکراری است؛ برای فروش، شناسه یکتا لازم است.');
        }
        final product = matches.first;
        productId = product['id'] as int;
        final onHand = (product['quantity'] as num).toDouble();
        if (quantity > onHand + 0.000001) {
          throw StateError('موجودی کالا کافی نیست. موجودی فعلی: ' + onHand.toString());
        }
        final unitCost = (product['purchase_price'] as num).toDouble();
        productIsUsed = product['is_used'] == 1;
        costOfGoods = unitCost * quantity;
        await AccountingEngine.recordStockMovementInTransaction(
          db,
          productId: productId,
          movementType: 'sale',
          quantityDelta: -quantity,
          unitCost: unitCost,
          referenceType: 'sale',
          referenceId: sourceId.toString(),
          notes: 'خروج کالا بابت فاکتور ' + invoiceNumber,
        );
      }

      await db.insert('invoice_items', {
        'invoice_id': invoiceId,
        'product_id': productId,
        'product_name_snapshot': selectedProductName.isEmpty ? description : selectedProductName,
        'unit': _text(data, 'واحد شمارش').isEmpty ? 'عدد' : _text(data, 'واحد شمارش'),
        'is_used': productIsUsed ? 1 : 0,
        'quantity': quantity,
        'unit_price': gross / quantity,
        'line_total': gross,
      });

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
      if (gross > 0) {
        final revenueCode = selectedProductName.isEmpty ? '4010' : '4000';
        lines.add(JournalLineInput(
          accountId: await AccountingEngine.accountId(db, revenueCode),
          credit: gross,
          memo: 'فروش فاکتور ' + invoiceNumber,
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

