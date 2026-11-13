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
        'purchase_price': _number(data, 'قیمت خرید هر واحد'),
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

  /// Mirrors new writes from the current screens into normalized tables
  /// inside the same SQLite transaction as the legacy JSON row.
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
      await db.insert('products', {
        'code': _text(data, 'کد کالا'),
        'name': _text(data, 'نام کالا').isEmpty ? 'کالای بدون نام' : _text(data, 'نام کالا'),
        'category': _text(data, 'گروه اصلی'),
        'subcategory': _text(data, 'زیرگروه'),
        'unit': unit,
        'quantity': _number(data, 'موجودی'),
        'purchase_price': _number(data, 'قیمت خرید هر واحد'),
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
      _assertNumeric(data, ['تعداد', 'مبلغ کل', 'تخفیف', 'مبلغ دریافتی']);
      final quantity = _number(data, 'تعداد') <= 0 ? 1 : _number(data, 'تعداد');
      final total = _number(data, 'مبلغ کل');
      final discount = _number(data, 'تخفیف');
      final invoiceId = await db.insert('invoices', {
        'invoice_number': 'LEGACY-' + sourceId.toString(),
        'customer_name_snapshot': _text(data, 'نام مشتری'),
        'subtotal': total,
        'discount': discount,
        'total': (total - discount).clamp(0, total),
        'received_amount': _number(data, 'مبلغ دریافتی'),
        'created_at': createdAt,
        'legacy_source_id': sourceId,
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
    } else if (category == 'operations' || category == 'checks' || category == 'returns' ||
        category == 'stockMovements' || category == 'journalEntries') {
      // These ledgers remain in the canonical JSON records table until their
      // dedicated normalized schema is introduced. No legacy mirror is needed.
    } else {
      throw ArgumentError('دسته اطلاعات نامعتبر است: ' + category);
    }
  }
}
