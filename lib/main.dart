import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:persian_datetime_picker/persian_datetime_picker.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'data/app_database_schema.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DemoStore.init();
  await AppSettings.load();
  runApp(const HoseinApp());
}

const yellow = Color(0xFFFFD400);
const black = Color(0xFF171717);

class AppSettings {
  static late SharedPreferences _prefs;
  static final revision = ValueNotifier<int>(0);
  static String storeName = 'خدمات فنی حسین';
  static String managerName = '';
  static String phone = '';
  static String address = '';
  static String postalCode = '';
  static bool darkMode = false;
  static String themeMode = 'روشن';
  static String drawerImage = '';
  static double fontScale = 1.0;
  static String productImageMode = 'پیش فرض عکس کالا';
  static List<Map<String, String>> purchaseRecords = [];
  static Map<String, List<String>> productGroups = {
    'قطعات الکترونیکی': ['خازن‌ها', 'دیودها', 'آی‌سی‌ها', 'مقاومت‌ها', 'ترانزیستورها'],
    'قطعات مکانیکی': ['بلبرینگ', 'چرخ‌دنده', 'شفت', 'بوش'],
  };

  static Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    storeName = _prefs.getString('store_name') ?? storeName;
    managerName = _prefs.getString('manager_name') ?? '';
    phone = _prefs.getString('store_phone') ?? '';
    address = _prefs.getString('store_address') ?? '';
    postalCode = _prefs.getString('store_postal_code') ?? '';
    darkMode = _prefs.getBool('dark_mode') ?? false;
    themeMode = _prefs.getString('theme_mode') ?? (darkMode ? 'تیره' : 'روشن');
    drawerImage = _prefs.getString('drawer_image') ?? '';
    fontScale = _prefs.getDouble('font_scale') ?? 1.0;
    productImageMode = _prefs.getString('product_image_mode') ?? 'پیش فرض عکس کالا';
    final savedPurchases = _prefs.getString('purchase_records');
    if (savedPurchases != null) {
      try {
        purchaseRecords = (jsonDecode(savedPurchases) as List).map((x) => (x as Map).map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''))).toList();
      } catch (_) {}
    }
    final savedGroups = _prefs.getString('product_groups');
    if (savedGroups != null) {
      try {
        final decoded = jsonDecode(savedGroups) as Map<String, dynamic>;
        productGroups = decoded.map((k, v) => MapEntry(k, (v as List).map((x) => x.toString()).toList()));
      } catch (_) {}
    }
  }

  static Future<void> save({
    required String newStoreName,
    required String newManagerName,
    required String newPhone,
    required String newAddress,
    required String newPostalCode,
    required bool newDarkMode,
    required String newThemeMode,
    required String newDrawerImage,
    required double newFontScale,
  }) async {
    storeName = newStoreName.trim().isEmpty ? 'فروشگاه من' : newStoreName.trim();
    managerName = newManagerName.trim();
    phone = newPhone.trim();
    address = newAddress.trim();
    postalCode = newPostalCode.trim();
    darkMode = newThemeMode == 'تیره';
    themeMode = newThemeMode;
    drawerImage = newDrawerImage;
    fontScale = newFontScale;
    await _prefs.setString('store_name', storeName);
    await _prefs.setString('manager_name', managerName);
    await _prefs.setString('store_phone', phone);
    await _prefs.setString('store_address', address);
    await _prefs.setString('store_postal_code', postalCode);
    await _prefs.setBool('dark_mode', darkMode);
    await _prefs.setString('theme_mode', themeMode);
    await _prefs.setString('drawer_image', drawerImage);
    await _prefs.setDouble('font_scale', fontScale);
    revision.value++;
  }

  static Future<void> savePurchaseRecords() async {
    await _prefs.setString('purchase_records', jsonEncode(purchaseRecords));
  }

  static Future<void> saveProductGroups() async {
    await _prefs.setString('product_groups', jsonEncode(productGroups));
  }

  static Future<void> resetAppearance() async {
    themeMode = 'روشن';
    darkMode = false;
    fontScale = 1.0;
    drawerImage = '';
    await _prefs.setString('theme_mode', themeMode);
    await _prefs.setBool('dark_mode', false);
    await _prefs.setDouble('font_scale', 1.0);
    await _prefs.remove('drawer_image');
    revision.value++;
  }
}

class PersianDigitsOnlyFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    final normalized = newValue.text.replaceAllMapped(RegExp(r'[۰-۹٠-٩]'), (match) {
      final digit = match.group(0)!;
      final p = persian.indexOf(digit);
      if (p >= 0) return '$p';
      final a = arabic.indexOf(digit);
      return a >= 0 ? '$a' : '';
    });
    final digits = normalized.replaceAll(RegExp(r'[^0-9]'), '');
    return TextEditingValue(
      text: digits,
      selection: TextSelection.collapsed(offset: digits.length),
    );
  }
}

class PersianDateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text
        .replaceAll(RegExp(r'[^0-9۰-۹٠-٩]'), '')
        .split('')
        .map((digit) {
          const western = '0123456789';
          const persian = '۰۱۲۳۴۵۶۷۸۹';
          const arabic = '٠١٢٣٤٥٦٧٨٩';
          final p = persian.indexOf(digit);
          if (p >= 0) return persian[p];
          final a = arabic.indexOf(digit);
          if (a >= 0) return persian[a];
          final w = western.indexOf(digit);
          return w >= 0 ? persian[w] : '';
        })
        .join();
    final limited = digits.length > 8 ? digits.substring(0, 8) : digits;
    final formatted = limited.length <= 4
        ? limited
        : limited.length <= 6
            ? '${limited.substring(0, 4)}/${limited.substring(4)}'
            : '${limited.substring(0, 4)}/${limited.substring(4, 6)}/${limited.substring(6)}';
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class HoseinApp extends StatelessWidget {
  const HoseinApp({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: AppSettings.revision,
        builder: (context, _, __) {
          final brightness = AppSettings.themeMode == 'تیره' ? Brightness.dark : Brightness.light;
          final seed = AppSettings.themeMode == 'فیروزه‌ای و سرمه‌ای'
              ? const Color(0xFF087E8B)
              : yellow;
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'خدمات فنی حسین',
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: brightness),
              scaffoldBackgroundColor: AppSettings.themeMode == 'تیره' ? const Color(0xFF121212) : AppSettings.themeMode == 'فیروزه‌ای و سرمه‌ای' ? const Color(0xFFEAF4F4) : const Color(0xFFF7F7F7),
              appBarTheme: const AppBarTheme(backgroundColor: black, foregroundColor: yellow),
              inputDecorationTheme: InputDecorationTheme(
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: AppSettings.themeMode == 'تیره' ? const Color(0xFF252525) : Colors.white,
              ),
              textTheme: ThemeData(brightness: brightness).textTheme,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(AppSettings.fontScale)),
              child: child ?? const SizedBox.shrink(),
            ),
            home: const HomePage(),
          );
        },
      );
}

class DemoStore {
  static Database? _db;
  static final products = <Map<String, String>>[];
  static final customers = <Map<String, String>>[];
  static final repairs = <Map<String, String>>[];
  static final sales = <Map<String, String>>[];
  static final operations = <Map<String, String>>[];
  static final checks = <Map<String, String>>[];
  static final returns = <Map<String, String>>[];
  static final stockMovements = <Map<String, String>>[];
  static final journalEntries = <Map<String, String>>[];

  static Future<void> init() async {
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dbPath, 'khadamat_fanni_hosein.db'),
      version: 2,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE records (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            category TEXT NOT NULL,
            data TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('CREATE INDEX records_category_idx ON records(category)');
        await AppDatabaseSchema.create(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await AppDatabaseSchema.create(db);
          await AppDatabaseSchema.migrateLegacyRecords(db);
        }
      },
    );
    await _loadCategory('products', products);
    await _loadCategory('customers', customers);
    await _loadCategory('repairs', repairs);
    await _loadCategory('sales', sales);
    await _loadCategory('operations', operations);
    await _loadCategory('checks', checks);
    await _loadCategory('returns', returns);
    await _loadCategory('stockMovements', stockMovements);
    await _loadCategory('journalEntries', journalEntries);
  }

  static Future<void> _loadCategory(String category, List<Map<String, String>> target) async {
    final rows = await _db!.query('records', where: 'category = ?', whereArgs: [category], orderBy: 'id ASC');
    target
      ..clear()
      ..addAll(rows.map((row) {
        final decoded = jsonDecode(row['data'] as String) as Map<String, dynamic>;
        return decoded.map((key, value) => MapEntry(key, value?.toString() ?? ''));
      }));
  }

  static Future<void> update(String category, Map<String, String> oldItem, Map<String, String> newItem) async {
    final savedItem = Map<String, String>.from(newItem);
    savedItem['شناسه سند'] = oldItem['شناسه سند'] ?? savedItem['شناسه سند'] ??
        DateTime.now().microsecondsSinceEpoch.toString();
    if (category == 'sales') {
      AccountingEngine.validateSale(savedItem, oldItem: oldItem);
      savedItem.addAll(AccountingEngine.prepareSale(savedItem, oldItem: oldItem));
    } else if (category == 'repairs') {
      AccountingEngine.validateRepair(savedItem, oldItem: oldItem);
    } else if (category == 'returns') {
      AccountingEngine.validateReturn(savedItem, oldItem: oldItem);
    }
    await _db!.update('records', {'data': jsonEncode(savedItem)}, where: 'category = ? AND data = ?', whereArgs: [category, jsonEncode(oldItem)]);
    final target = switch (category) {
      'products' => products, 'customers' => customers, 'repairs' => repairs, 'sales' => sales, 'operations' => operations,
      'checks' => checks, 'returns' => returns, 'stockMovements' => stockMovements, 'journalEntries' => journalEntries,
      _ => throw ArgumentError('دسته اطلاعات نامعتبر است'),
    };
    final index = target.indexWhere((x) => jsonEncode(x) == jsonEncode(oldItem));
    if (index >= 0) target[index] = Map<String,String>.from(savedItem);
    await AccountingEngine.syncDocument(category, savedItem, previous: oldItem);
  }

  static Future<void> updateRaw(String category, Map<String, String> oldItem, Map<String, String> newItem) async {
    await _db!.update('records', {'data': jsonEncode(newItem)},
        where: 'category = ? AND data = ?', whereArgs: [category, jsonEncode(oldItem)]);
    final target = switch (category) {
      'products' => products,
      _ => throw ArgumentError('ویرایش خام فقط برای کالا پشتیبانی می‌شود'),
    };
    final index = target.indexWhere((x) => jsonEncode(x) == jsonEncode(oldItem));
    if (index >= 0) target[index] = Map<String, String>.from(newItem);
  }

  static Future<void> renamePartyReferences(String oldName, String newName) async {
    final oldValue = oldName.trim();
    final newValue = newName.trim();
    if (oldValue.isEmpty || newValue.isEmpty || oldValue == newValue) return;

    Future<void> renameIn(String category, List<Map<String, String>> target, String field) async {
      final matches = target.where((item) => (item[field] ?? '').trim() == oldValue).toList();
      for (final oldItem in matches) {
        final replacement = Map<String, String>.from(oldItem)..[field] = newValue;
        await update(category, oldItem, replacement);
      }
    }

    await renameIn('sales', sales, 'نام مشتری');
    await renameIn('repairs', repairs, 'نام مشتری');
    await renameIn('operations', operations, 'نام شخص');
    await renameIn('checks', checks, 'نام شخص');
    await renameIn('returns', returns, 'نام شخص');
    var purchaseChanged = false;
    final changedPurchases = <({Map<String,String> oldItem, Map<String,String> newItem})>[];
    for (final item in AppSettings.purchaseRecords) {
      if ((item['نام فروشنده'] ?? '').trim() == oldValue) {
        final oldItem = Map<String,String>.from(item);
        item['نام فروشنده'] = newValue;
        changedPurchases.add((oldItem: oldItem, newItem: Map<String,String>.from(item)));
        purchaseChanged = true;
      }
    }
    if (purchaseChanged) {
      await AppSettings.savePurchaseRecords();
      for (final change in changedPurchases) {
        await AccountingEngine.syncSupplierPurchase(change.newItem, previous: change.oldItem);
      }
    }
  }

  static Future<void> delete(String category, List<Map<String, String>> items) async {
    if (items.isEmpty) return;
    for (final item in items) {
      await AccountingEngine.removeDocument(category, item);
    }
    final table = switch (category) {
      'customers' => 'customers', 'products' => 'products', 'repairs' => 'repairs', 'sales' => 'invoices',
      _ => null,
    };
    await _db!.transaction((txn) async {
      for (final item in items) {
        final rows = await txn.query('records', columns: ['id'], where: 'category = ? AND data = ?', whereArgs: [category, jsonEncode(item)]);
        for (final row in rows) {
          final id = row['id'] as int;
          if (table != null) await txn.delete(table, where: 'legacy_source_id = ?', whereArgs: [id]);
          await txn.delete('records', where: 'id = ?', whereArgs: [id]);
        }
      }
    });
    final target = switch (category) {
      'products' => products, 'customers' => customers, 'repairs' => repairs, 'sales' => sales, 'operations' => operations,
      'checks' => checks, 'returns' => returns, 'stockMovements' => stockMovements, 'journalEntries' => journalEntries,
      _ => throw ArgumentError('دسته اطلاعات نامعتبر است'),
    };
    for (final item in items) {
      final index = target.indexWhere((x) => jsonEncode(x) == jsonEncode(item));
      if (index >= 0) target.removeAt(index);
    }
  }

  static Future<void> replaceJournalEntries(String reference, List<Map<String,String>> entries) async {
    final createdAt = DateTime.now().toIso8601String();
    await _db!.transaction((txn) async {
      final existing = await txn.query('records', columns: ['id','data'],
          where: 'category = ?', whereArgs: ['journalEntries']);
      for (final row in existing) {
        final decoded = jsonDecode(row['data'] as String) as Map<String,dynamic>;
        if ((decoded['مرجع سند'] ?? '').toString() == reference) {
          await txn.delete('records', where: 'id = ?', whereArgs: [row['id']]);
        }
      }
      for (final entry in entries) {
        await txn.insert('records', {
          'category': 'journalEntries',
          'data': jsonEncode(entry),
          'created_at': createdAt,
        });
      }
    });
    journalEntries.removeWhere((x) => x['مرجع سند'] == reference);
    journalEntries.addAll(entries.map((x) => Map<String,String>.from(x)));
  }

  static Future<void> add(String category, Map<String, String> item) async {
    final createdAt = DateTime.now().toIso8601String();
    final savedItem = Map<String, String>.from(item);
    savedItem.putIfAbsent('شناسه سند', () => DateTime.now().microsecondsSinceEpoch.toString());
    if (category == 'sales') {
      AccountingEngine.validateSale(savedItem);
      savedItem.addAll(AccountingEngine.prepareSale(savedItem));
    } else if (category == 'repairs') {
      AccountingEngine.validateRepair(savedItem);
    } else if (category == 'returns') {
      AccountingEngine.validateReturn(savedItem);
    }
    await _db!.transaction((txn) async {
      final recordId = await txn.insert('records', {
        'category': category,
        'data': jsonEncode(savedItem),
        'created_at': createdAt,
      });
      await AppDatabaseSchema.insertLegacyRecord(
        txn, category, savedItem, recordId, createdAt,
      );
    });
    final target = switch (category) {
      'products' => products,
      'customers' => customers,
      'repairs' => repairs,
      'sales' => sales,
      'operations' => operations,
      'checks' => checks, 'returns' => returns, 'stockMovements' => stockMovements, 'journalEntries' => journalEntries,
      _ => throw ArgumentError('دسته اطلاعات نامعتبر است'),
    };
    target.add(Map<String, String>.from(savedItem));
    await AccountingEngine.syncDocument(category, savedItem);
  }
}


class PartyAccounting {
  static String _digits(String value) {
    const fa = '۰۱۲۳۴۵۶۷۸۹';
    const ar = '٠١٢٣٤٥٦٧٨٩';
    return value.split('').map((c) {
      final f = fa.indexOf(c);
      final a = ar.indexOf(c);
      if (f >= 0) return '$f';
      if (a >= 0) return '$a';
      return c;
    }).join();
  }

  static int amount(Map<String, String> item, String key) {
    final raw = _digits(item[key] ?? '').replaceAll(RegExp(r'[^0-9-]'), '');
    return int.tryParse(raw) ?? 0;
  }

  static void _add(List<Map<String, String>> rows, String party, String side,
      int value, String type, String date, String description) {
    final name = party.trim();
    if (name.isEmpty || value <= 0) return;
    rows.add({
      'شخص': name,
      'ماهیت': side,
      'مبلغ': value.toString(),
      'نوع': type,
      'تاریخ': date,
      'شرح': description,
    });
  }

  static List<Map<String, String>> entriesFor(String party) {
    final name = party.trim();
    final rows = <Map<String, String>>[];

    final customer = DemoStore.customers.where((x) => (x['نام مشتری'] ?? '').trim() == name);
    for (final person in customer) {
      final opening = amount(person, 'مانده اولیه');
      final side = (person['ماهیت مانده اولیه'] ?? 'بدهکار').trim() == 'بستانکار'
          ? 'بستانکار'
          : 'بدهکار';
      _add(rows, name, side, opening, 'مانده اول دوره',
          person['تاریخ مانده اولیه'] ?? '', 'مانده اولیه ثبت‌شده برای مشتری');
    }

    for (final sale in DemoStore.sales.where((x) => (x['نام مشتری'] ?? '').trim() == name)) {
      final gross = amount(sale, 'مبلغ کل');
      final discount = amount(sale, 'تخفیف');
      final net = (gross - discount).clamp(0, 1 << 62).toInt();
      final date = sale['تاریخ فاکتور'] ?? sale['تاریخ'] ?? '';
      _add(rows, name, 'بدهکار', net, 'فاکتور فروش', date,
          sale['شرح کالا/خدمت'] ?? 'فروش کالا یا خدمات');
      _add(rows, name, 'بستانکار', amount(sale, 'مبلغ دریافتی'),
          'دریافت هنگام فروش', date, 'پرداخت ثبت‌شده در فاکتور فروش');
    }

    for (final repair in DemoStore.repairs.where((x) => (x['نام مشتری'] ?? '').trim() == name)) {
      final date = repair['تاریخ پذیرش'] ?? '';
      _add(rows, name, 'بدهکار', amount(repair, 'اجرت'),
          'اجرت تعمیر', date, repair['نوع دستگاه'] ?? 'پذیرش تعمیر');
      _add(rows, name, 'بستانکار', amount(repair, 'مبلغ دریافتی'),
          'دریافت تعمیر', date, 'مبلغ دریافت‌شده بابت تعمیر');
    }

    for (final purchase in AppSettings.purchaseRecords.where((x) => (x['نام فروشنده'] ?? '').trim() == name)) {
      final date = purchase['تاریخ خرید'] ?? '';
      _add(rows, name, 'بستانکار', amount(purchase, 'مبلغ خرید'),
          'خرید از فروشنده', date, purchase['کالا'] ?? 'خرید کالا');
      _add(rows, name, 'بدهکار', amount(purchase, 'مبلغ پرداختی'),
          'پرداخت خرید', date, 'مبلغ پرداخت‌شده به فروشنده');
    }

    for (final operation in DemoStore.operations.where((x) => (x['نام شخص'] ?? '').trim() == name)) {
      final type = operation['نوع عملیات'] ?? '';
      final date = operation['تاریخ'] ?? '';
      final value = amount(operation, 'مبلغ');
      String? side;
      switch (type) {
        case 'دریافت وجه':
        case 'متفرقه شخص بستانکار':
        case 'تخفیف دادن':
          side = 'بستانکار';
          break;
        case 'پرداخت وجه':
        case 'متفرقه شخص بدهکار':
        case 'تخفیف گرفتن':
          side = 'بدهکار';
          break;
      }
      if (side != null) {
        _add(rows, name, side, value, type, date,
            operation['توضیحات'] ?? operation['روش'] ?? type);
      }
    }

    for (final returned in DemoStore.returns.where((x) => (x['نام شخص'] ?? '').trim() == name)) {
      final type = returned['نوع برگشت'] ?? '';
      final side = type == 'برگشت فروش' ? 'بستانکار' : 'بدهکار';
      _add(rows, name, side, amount(returned, 'مبلغ'), type,
          returned['تاریخ'] ?? '', returned['شرح'] ?? returned['نام کالا'] ?? type);
    }

    for (final check in DemoStore.checks.where((x) => (x['نام شخص'] ?? '').trim() == name)) {
      final type = check['نوع چک'] ?? '';
      final status = check['وضعیت'] ?? 'پاس نشده';
      final effect = (check['اثر در مانده حساب'] ?? 'بله') == 'بله';
      final reversedCheck = status == 'برگشتی' || status == 'باطل شده';
      if (reversedCheck) {
        if (type == 'دریافتی') {
          _add(rows, name, 'بدهکار', amount(check, 'مبلغ'), 'برگشت چک دریافتی',
              check['تاریخ سررسید'] ?? check['تاریخ ثبت'] ?? '', 'برگشت چک؛ بدهی مشتری دوباره برقرار شد');
        } else if (type == 'پرداختی') {
          _add(rows, name, 'بستانکار', amount(check, 'مبلغ'), 'برگشت چک پرداختی',
              check['تاریخ سررسید'] ?? check['تاریخ ثبت'] ?? '', 'برگشت چک؛ بدهی به فروشنده دوباره برقرار شد');
        }
      } else if (effect && status != 'باطل شده') {
        if (type == 'دریافتی') {
          _add(rows, name, 'بستانکار', amount(check, 'مبلغ'), 'چک دریافتی',
              check['تاریخ ثبت'] ?? '', 'چک شماره ' + (check['شماره چک'] ?? ''));
        } else if (type == 'پرداختی') {
          _add(rows, name, 'بدهکار', amount(check, 'مبلغ'), 'چک پرداختی',
              check['تاریخ ثبت'] ?? '', 'چک شماره ' + (check['شماره چک'] ?? ''));
        }
      }
    }

    DateTime? parseDate(String raw) {
      final value = _digits(raw);
      final match = RegExp(r'(\d{4})[/-](\d{1,2})[/-](\d{1,2})').firstMatch(value);
      if (match != null) {
        final year = int.parse(match.group(1)!);
        final month = int.parse(match.group(2)!);
        final day = int.parse(match.group(3)!);
        try {
          return year >= 1300 ? Jalali(year, month, day).toDateTime() : DateTime(year, month, day);
        } catch (_) { return null; }
      }
      return DateTime.tryParse(value)?.toLocal();
    }

    rows.sort((a, b) {
      final ad = a['تاریخ'] ?? '';
      final bd = b['تاریخ'] ?? '';
      final aDate = parseDate(ad);
      final bDate = parseDate(bd);
      if (aDate != null && bDate != null) return aDate.compareTo(bDate);
      if (aDate != null) return 1;
      if (bDate != null) return -1;
      return ad.compareTo(bd);
    });

    var runningBalance = 0;
    for (final row in rows) {
      final value = amount(row, 'مبلغ');
      runningBalance += row['ماهیت'] == 'بدهکار' ? value : -value;
      row['مانده پس از سند'] = runningBalance.toString();
      row['وضعیت مانده'] = runningBalance > 0 ? 'بدهکار' : runningBalance < 0 ? 'بستانکار' : 'تسویه';
    }
    return rows;
  }

  static int balanceFor(String party) {
    return entriesFor(party).fold<int>(0, (balance, entry) {
      final value = amount(entry, 'مبلغ');
      return balance + (entry['ماهیت'] == 'بدهکار' ? value : -value);
    });
  }

  static bool hasHistoryFor(String party) {
    final name = party.trim();
    if (name.isEmpty) return false;
    return entriesFor(name).isNotEmpty ||
        DemoStore.sales.any((x) => (x['نام مشتری'] ?? '').trim() == name) ||
        DemoStore.repairs.any((x) => (x['نام مشتری'] ?? '').trim() == name) ||
        DemoStore.operations.any((x) => (x['نام شخص'] ?? '').trim() == name) ||
        DemoStore.checks.any((x) => (x['نام شخص'] ?? '').trim() == name) ||
        DemoStore.returns.any((x) => (x['نام شخص'] ?? '').trim() == name) ||
        AppSettings.purchaseRecords.any((x) => (x['نام فروشنده'] ?? '').trim() == name);
  }

  static String formatMoney(int value) => value.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

  static String statusFor(String party) {
    final balance = balanceFor(party);
    if (balance > 0) return 'بدهکار';
    if (balance < 0) return 'بستانکار';
    return 'تسویه';
  }

  static int totalDebtors() => DemoStore.customers.fold<int>(0, (sum, x) {
    final balance = balanceFor(x['نام مشتری'] ?? '');
    return sum + (balance > 0 ? balance : 0);
  });

  static int totalCreditors() => DemoStore.customers.fold<int>(0, (sum, x) {
    final balance = balanceFor(x['نام مشتری'] ?? '');
    return sum + (balance < 0 ? -balance : 0);
  });
}


class AccountingEngine {
  static String _reference(String category, Map<String,String> item) =>
      category + ':' + (item['شناسه سند'] ?? item['شناسه داخلی'] ?? '');

  static double _qty(Map<String,String> item, String key) {
    final raw = PartyAccounting._digits(item[key] ?? '').replaceAll(',', '').replaceAll('٬','');
    return double.tryParse(raw) ?? 0;
  }

  static Map<String,String>? _product(String name) {
    final clean = name.trim();
    if (clean.isEmpty) return null;
    for (final item in DemoStore.products) {
      if ((item['نام کالا'] ?? '').trim() == clean ||
          ((item['کد کالا'] ?? '').trim().isNotEmpty && (item['کد کالا'] ?? '').trim() == clean)) {
        return item;
      }
    }
    return null;
  }

  static Map<String,String> prepareSale(Map<String,String> item, {Map<String,String>? oldItem}) {
    final result = Map<String,String>.from(item);
    final productName = (result['نام کالا (از انبار)'] ?? '').trim();
    final product = _product(productName);
    final quantity = _qty(result, 'تعداد');
    final gross = PartyAccounting.amount(result, 'مبلغ کل');
    final discount = PartyAccounting.amount(result, 'تخفیف');
    final netSales = (gross - discount).clamp(0, 1 << 62).toInt();
    if (product != null) {
      final sameOriginalProduct = oldItem != null &&
          (oldItem['نام کالا (از انبار)'] ?? '').trim() == productName &&
          _qty(oldItem!, 'بهای تمام‌شده هر واحد') > 0;
      final unitCost = sameOriginalProduct
          ? _qty(oldItem!, 'بهای تمام‌شده هر واحد')
          : (_qty(product, 'بهای تمام‌شده هر واحد') > 0
              ? _qty(product, 'بهای تمام‌شده هر واحد')
              : _qty(product, 'قیمت خرید هر واحد'));
      final costTotal = unitCost * quantity;
      result['شناسه کالا'] = product['کد کالا'] ?? '';
      result['واحد کالا'] = product['واحد شمارش'] ?? 'عدد';
      result['بهای تمام‌شده هر واحد'] = unitCost.toStringAsFixed(0);
      result['بهای تمام‌شده کل'] = costTotal.toStringAsFixed(0);
      result['سود'] = (netSales - costTotal).toStringAsFixed(0);
    } else {
      result.remove('شناسه کالا');
      result.remove('بهای تمام‌شده هر واحد');
      result.remove('بهای تمام‌شده کل');
      result.remove('سود');
    }
    result['مبلغ فروش خالص'] = netSales.toString();
    return result;
  }

  static void validateReturn(Map<String,String> item, {Map<String,String>? oldItem}) {
    final amount = PartyAccounting.amount(item, 'مبلغ');
    if (amount <= 0) throw StateError('مبلغ برگشت باید بیشتر از صفر باشد.');
    final productName = (item['نام کالا'] ?? '').trim();
    final qty = _qty(item, 'تعداد');
    if (qty < 0) throw StateError('تعداد برگشت نمی‌تواند منفی باشد.');
    if (productName.isEmpty) return;

    final returnType = item['نوع برگشت'] ?? '';
    final reference = (item['شناسه مرجع'] ?? '').trim();
    if (reference.isEmpty) {
      throw StateError('برای برگشت کالای انبار، فاکتور اصلی را انتخاب کنید.');
    }
    final sourceRows = returnType == 'برگشت فروش'
        ? DemoStore.sales
        : AppSettings.purchaseRecords;
    String sourceId(Map<String,String> row, int index) =>
        row['شناسه سند'] ?? 'legacy-origin-$index';
    Map<String,String>? source;
    for (final entry in sourceRows.asMap().entries) {
      if (sourceId(entry.value, entry.key) == reference) {
        source = entry.value;
        break;
      }
    }
    if (source == null) throw StateError('سند مرجع برگشت پیدا نشد.');
    final sourceProduct = returnType == 'برگشت فروش'
        ? (source['نام کالا (از انبار)'] ?? '').trim()
        : (source['کالا'] ?? '').trim();
    if (sourceProduct != productName) {
      throw StateError('کالای انتخاب‌شده با کالای فاکتور مرجع یکسان نیست.');
    }
    final expectedParty = returnType == 'برگشت فروش'
        ? (source['نام مشتری'] ?? '').trim()
        : (source['نام فروشنده'] ?? '').trim();
    if (expectedParty.isNotEmpty && (item['نام شخص'] ?? '').trim() != expectedParty) {
      throw StateError('نام مشتری یا فروشنده باید با فاکتور مرجع یکسان باشد.');
    }

    final product = _product(productName);
    if (product == null) throw StateError('کالای برگشتی در انبار پیدا نشد.');
    final originalQty = returnType == 'برگشت فروش'
        ? _qty(source, 'تعداد')
        : _qty(source, 'تعداد خرید');
    final previousReturns = DemoStore.returns.where((row) =>
        row['شناسه مرجع'] == reference &&
        row['شناسه سند'] != (oldItem?['شناسه سند'] ?? '')).toList();
    final alreadyReturnedQty = previousReturns.fold<double>(
        0, (sum, row) => sum + _qty(row, 'تعداد'));
    final remainingQty = (originalQty - alreadyReturnedQty).clamp(0, 1e15).toDouble();
    if (qty <= 0 || qty > remainingQty) {
      throw StateError('تعداد برگشتی از مقدار باقی‌مانده فاکتور مرجع بیشتر است: $remainingQty');
    }

    final originalAmount = returnType == 'برگشت فروش'
        ? (PartyAccounting.amount(source, 'مبلغ کل') - PartyAccounting.amount(source, 'تخفیف')).clamp(0, 1 << 62).toInt()
        : PartyAccounting.amount(source, 'مبلغ خرید');
    final alreadyReturnedAmount = previousReturns.fold<int>(
        0, (sum, row) => sum + PartyAccounting.amount(row, 'مبلغ'));
    final remainingAmount = (originalAmount - alreadyReturnedAmount).clamp(0, 1 << 62).toInt();
    if (amount > remainingAmount) {
      throw StateError('مبلغ برگشت از مانده مبلغ فاکتور مرجع بیشتر است: $remainingAmount تومان');
    }
  }

  static void validateRepair(Map<String,String> item, {Map<String,String>? oldItem}) {
    final productName = (item['نام قطعه مصرفی از انبار'] ?? '').trim();
    if (productName.isEmpty) return;
    final product = _product(productName);
    if (product == null) throw StateError('قطعه انتخاب‌شده در انبار پیدا نشد.');
    final requested = _qty(item, 'تعداد قطعه مصرفی');
    final oldQty = oldItem != null && (oldItem['نام قطعه مصرفی از انبار'] ?? '') == productName
        ? _qty(oldItem, 'تعداد قطعه مصرفی') : 0;
    final available = _qty(product, 'موجودی') + oldQty;
    if (requested <= 0) throw StateError('تعداد قطعه مصرفی باید بیشتر از صفر باشد.');
    if (requested > available) throw StateError('موجودی قطعه کافی نیست. موجودی قابل مصرف: ' + available.toString());
  }

  static void validateSale(Map<String,String> item, {Map<String,String>? oldItem}) {
    final gross = PartyAccounting.amount(item, 'مبلغ کل');
    final discount = PartyAccounting.amount(item, 'تخفیف');
    final received = PartyAccounting.amount(item, 'مبلغ دریافتی');
    if (gross <= 0) throw StateError('مبلغ فاکتور باید بیشتر از صفر باشد.');
    if (discount > gross) throw StateError('تخفیف نمی‌تواند از مبلغ کل فاکتور بیشتر باشد.');
    if (received < 0) throw StateError('مبلغ دریافتی نمی‌تواند منفی باشد.');
    final productName = (item['نام کالا (از انبار)'] ?? '').trim();
    if (productName.isEmpty) return;
    final product = _product(productName);
    if (product == null) throw StateError('کالای انتخاب‌شده در انبار پیدا نشد.');
    final requested = _qty(item, 'تعداد');
    final oldQty = oldItem != null && (oldItem['نام کالا (از انبار)'] ?? '') == productName
        ? _qty(oldItem, 'تعداد') : 0;
    final available = _qty(product, 'موجودی') + oldQty;
    if (requested <= 0) throw StateError('تعداد کالای فروخته‌شده باید بیشتر از صفر باشد.');
    if (requested > available) {
      throw StateError('موجودی کافی نیست. موجودی قابل فروش: ' + available.toString());
    }
  }

  static Future<void> _setProductQuantity(Map<String,String> product, double quantity) async {
    final changed = Map<String,String>.from(product);
    changed['موجودی'] = quantity.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  int tab = 0;
  final List<int> _tabHistory = [];
  final TextEditingController drawerSearchController = TextEditingController();
  final titles = const ['داشبورد', 'انبار کالا', 'مشتریان', 'تعمیرات', 'فروش و فاکتور', 'گزارش‌ها', 'تنظیمات برنامه', 'عملیات‌های دیگر'];

  @override
  void dispose() { drawerSearchController.dispose(); super.dispose(); }

  String _scopeForTab() => switch (tab) {
    1 => 'products', 2 => 'customers', 3 => 'repairs', 4 => 'sales', 5 => 'reports', 7 => 'operations', _ => 'all',
  };

  Future<bool> _confirmSettingsExit() async {
    if (tab != 6 || SettingsPage.isDirty?.call() != true) return true;
    final choice = await showDialog<String>(context: context, builder: (d) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('تغییرات ذخیره نشده‌اند'),
        content: const Text('در تنظیمات تغییراتی انجام داده‌اید. قبل از خروج چه کاری انجام شود؟'),
        actions: [_horizontalDialogActions([
          TextButton(onPressed: () => Navigator.pop(d, 'stay'), child: const Text('ادامه ویرایش')),
          TextButton(onPressed: () => Navigator.pop(d, 'discard'), child: const Text('خروج بدون ذخیره')),
          FilledButton(onPressed: () => Navigator.pop(d, 'save'), child: const Text('ذخیره و خروج')),
        ])],
      ),
    ));
    if (choice == 'save') return await SettingsPage.savePending?.call() ?? false;
    return choice == 'discard';
  }

  void _selectTab(int nextTab) async {
    if (nextTab < 0 || nextTab >= titles.length || nextTab == tab) return;
    if (!await _confirmSettingsExit()) return;
    setState(() {
      _tabHistory.add(tab);
      tab = nextTab;
    });
  }

  Future<void> _handleBack() async {
    if (scaffoldKey.currentState?.isDrawerOpen == true) {
      scaffoldKey.currentState?.closeDrawer();
      return;
    }

    if (!await _confirmSettingsExit()) return;

    if (_tabHistory.isNotEmpty) {
      setState(() {
        tab = _tabHistory.removeLast();
      });
      return;
    }

    if (tab != 0) {
      setState(() => tab = 0);
      return;
    }

    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('خروج از برنامه'),
          content: const Text('آیا می‌خواهید از برنامه خارج شوید؟'),
          actions: [_horizontalDialogActions([
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('ادامه کار'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('خروج'),
            ),
          ])],
        ),
      ),
    );

    if (!mounted) return;
    if (shouldExit == true) {
      await SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      Dashboard(onSelect: _selectTab),
      ProductPage(onChanged: () => setState(() {})),
      CustomerPage(onChanged: () => setState(() {})),
      RepairPage(onChanged: () => setState(() {})),
      SalesPage(onChanged: () => setState(() {})),
      const ReportsPage(),
      const SettingsPage(),
      OperationsPage(onChanged: () => setState(() {})),
    ];
    return Directionality(
      textDirection: TextDirection.rtl,
      child: PopScope<Object?>(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) {
            _handleBack();
          }
        },
        child: Scaffold(
          key: scaffoldKey,
          appBar: AppBar(
            title: Text(titles[tab]),
            actions: [
              if (tab == 1)
                PopupMenuButton<String>(
                  tooltip: 'تنظیم نمایش عکس کالا',
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) async {
                    AppSettings.productImageMode = value;
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('product_image_mode', value);
                    if (mounted) setState(() {});
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'عدم نمایش عکس کالا', child: Text('عدم نمایش عکس کالا')),
                    PopupMenuItem(value: 'پیش فرض عکس کالا', child: Text('پیش فرض عکس کالا')),
                    PopupMenuItem(value: 'کوچک کردن عکس کالا', child: Text('کوچک کردن عکس کالا')),
                  ],
                ),
              IconButton(tooltip: 'جست‌وجو', onPressed: () => _showScopedSearch(context, _scopeForTab()), icon: const Icon(Icons.search)),
            ],
          ),
          body: pages[tab],
          drawer: Drawer(
            child: ListView(
              children: [
                DrawerHeader(
                  decoration: const BoxDecoration(color: black),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: AppSettings.drawerImage.isNotEmpty
                            ? Image.memory(base64Decode(AppSettings.drawerImage), width: 68, height: 68, fit: BoxFit.cover)
                            : Image.asset('assets/logo.jpg', width: 68, height: 68, fit: BoxFit.cover),
                      ),
                      const SizedBox(height: 8),
                      Text(AppSettings.storeName, style: const TextStyle(color: yellow, fontSize: 22, fontWeight: FontWeight.bold)),
                      Text('نسخه آزمایشی', style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
                Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 12), child: TextField(
                  controller: drawerSearchController,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    labelText: 'جست‌وجو در کل برنامه',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: () => _showScopedSearch(context, 'all', initialQuery: drawerSearchController.text)),
                  ),
                  onSubmitted: (value) => _showScopedSearch(context, 'all', initialQuery: value),
                )),
                for (int i = 0; i < titles.length; i++)
                  ListTile(
                    leading: Icon([Icons.dashboard, Icons.inventory_2, Icons.people, Icons.build, Icons.receipt_long, Icons.bar_chart, Icons.settings, Icons.account_balance_wallet][i]),
                    title: Text(titles[i]),
                    selected: tab == i,
                    onTap: () {
                      _selectTab(i);
                      Navigator.pop(context);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class Dashboard extends StatelessWidget {
  final ValueChanged<int> onSelect;
  const Dashboard({super.key, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final stats = [
      ('کالاهای ثبت‌شده', DemoStore.products.length.toString(), Icons.inventory_2, 1),
      ('مشتریان', DemoStore.customers.length.toString(), Icons.people, 2),
      ('پذیرش تعمیرات', DemoStore.repairs.length.toString(), Icons.build, 3),
      ('فاکتورهای فروش', DemoStore.sales.length.toString(), Icons.receipt, 4),
      ('گزارش‌ها', 'مشاهده گزارش‌ها', Icons.bar_chart, 5),
      ('عملیات‌های دیگر', '۶ عملیات مالی', Icons.account_balance_wallet, 7),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          childAspectRatio: 1.20,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          children: [
            for (final s in stats)
              Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onSelect(s.$4),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(s.$3, color: Colors.amber.shade800, size: 28),
                        const SizedBox(height: 6),
                        Text(s.$2, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, height: 1.25)),
                        Text(s.$1, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500, height: 1.25)),
                        const SizedBox(height: 4),
                        const Icon(Icons.touch_app_outlined, size: 16, color: Colors.grey),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text(
            'اطلاعات کالاها، مشتریان، تعمیرات و فروش در پایگاه داده محلی گوشی ذخیره می‌شوند.',
            style: TextStyle(color: Colors.red, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

Future<void> _showScopedSearch(BuildContext context, String scope, {String initialQuery = ''}) async {
  final controller = TextEditingController(text: initialQuery);
  final records = <({String section, Map<String, String> data})>[];
  void add(String section, List<Map<String, String>> items) {
    for (final item in items) records.add((section: section, data: item));
  }
  if (scope == 'all' || scope == 'products') add('کالاها و انبار', DemoStore.products);
  if (scope == 'all' || scope == 'customers') add('مشتریان', DemoStore.customers);
  if (scope == 'all' || scope == 'repairs') add('تعمیرات', DemoStore.repairs);
  if (scope == 'all' || scope == 'sales') add('فروش و فاکتورها', DemoStore.sales);
  if (scope == 'all' || scope == 'operations') add('عملیات مالی', DemoStore.operations);
  if (scope == 'reports') {
    add('گزارش‌ها', [
      {'عنوان گزارش': 'تعداد کالاهای ثبت‌شده', 'مقدار': DemoStore.products.length.toString()},
      {'عنوان گزارش': 'تعداد مشتریان', 'مقدار': DemoStore.customers.length.toString()},
      {'عنوان گزارش': 'تعداد پذیرش‌های تعمیر', 'مقدار': DemoStore.repairs.length.toString()},
      {'عنوان گزارش': 'تعداد فاکتورهای فروش', 'مقدار': DemoStore.sales.length.toString()},
      {'عنوان گزارش': 'تعداد عملیات مالی', 'مقدار': DemoStore.operations.length.toString()},
    ]);
  }
  String title = scope == 'all' ? 'جست‌وجو در کل برنامه' : 'جست‌وجو در این بخش';
  await showDialog<void>(context: context, builder: (dialogContext) => Directionality(
    textDirection: TextDirection.rtl,
    child: StatefulBuilder(builder: (dialogContext, refresh) {
      final query = controller.text.trim().toLowerCase();
      final filtered = query.isEmpty ? <({String section, Map<String, String> data})>[] : records.where((r) {
        final text = '${r.section} ${r.data.entries.map((e) => '${e.key} ${e.value}').join(' ')}'.toLowerCase();
        return text.contains(query);
      }).toList();
      return AlertDialog(
        title: Text(title),
        content: SizedBox(width: 420, height: 480, child: Column(children: [
          TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'عبارت مورد جست‌وجو',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(icon: const Icon(Icons.clear), tooltip: 'حذف فیلتر', onPressed: () { controller.clear(); refresh(() {}); }),
            ),
            onChanged: (_) => refresh(() {}),
            onSubmitted: (_) => refresh(() {}),
          ),
          const SizedBox(height: 8),
          Expanded(child: query.isEmpty
              ? const Center(child: Text('برای شروع، عبارت موردنظر را وارد کنید.'))
              : filtered.isEmpty
                  ? const Center(child: Text('موردی پیدا نشد.'))
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final result = filtered[index];
                        final entries = result.data.entries.where((e) => e.value.isNotEmpty).toList();
                        final primary = entries.isEmpty ? 'بدون عنوان' : entries.first.value;
                        final detail = entries.skip(1).take(2).map((e) => '${e.key}: ${e.value}').join(' • ');
                        return Card(child: ListTile(
                          leading: const Icon(Icons.search),
                          title: Text(primary, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${result.section}${detail.isEmpty ? '' : ' • $detail'}', maxLines: 2, overflow: TextOverflow.ellipsis),
                          onTap: () {
                            Navigator.pop(dialogContext);
                            showDialog<void>(context: context, builder: (detailContext) => Directionality(
                              textDirection: TextDirection.rtl,
                              child: AlertDialog(
                                title: Text(result.section),
                                content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [for (final entry in result.data.entries.where((e) => e.value.isNotEmpty))
                                    Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Text('${entry.key}: ${entry.value}'))],
                                ))),
                                actions: [_horizontalDialogActions([TextButton(onPressed: () => Navigator.pop(detailContext), child: const Text('بستن'))])],
                              ),
                            ));
                          },
                        ));
                      },
                    )),
        ])),
        actions: [_horizontalDialogActions([TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('بستن'))])],
      );
    }),
  ));
  controller.dispose();
}

Widget _horizontalDialogActions(List<Widget> children) {
  return SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: children,
    ),
  );
}

Future<bool> _confirmDelete(BuildContext context, int count) async {
  return await showDialog<bool>(context: context, builder: (d) => Directionality(textDirection: TextDirection.rtl, child: AlertDialog(
    title: const Text('تأیید حذف'),
    content: Text('آیا از حذف $count مورد انتخاب‌شده مطمئن هستید؟ این عمل قابل بازگشت نیست.'),
    actions: [_horizontalDialogActions([TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('انصراف')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('حذف'))])],
  ))) ?? false;
}

class SimpleListPage extends StatefulWidget {
  final String title;
  final List<Map<String, String>> data;
  final List<String> fields;
  final String primary;
  final VoidCallback onChanged;

  const SimpleListPage({
    super.key,
    required this.title,
    required this.data,
    required this.fields,
    required this.primary,
    required this.onChanged,
  });

  @override
  State<SimpleListPage> createState() => _SimpleListPageState();
}

class _SimpleListPageState extends State<SimpleListPage> {
  final Set<String> _selectedKeys = {};

  String _keyOf(Map<String, String> item) => jsonEncode(item);

  Future<void> _deleteSelected() async {
    final selected = widget.data.where((item) => _selectedKeys.contains(_keyOf(item))).toList();
    if (selected.isEmpty) return;
    if (widget.title == 'مشتری' && selected.any((x) => PartyAccounting.hasHistoryFor(x['نام مشتری'] ?? ''))) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('مشتری دارای سابقه مالی یا تعمیراتی است و حذف نمی‌شود. برای حفظ سابقه، اطلاعات او را ویرایش کنید.')));
      return;
    }
    if (!await _confirmDelete(context, selected.length)) return;
    final category = widget.title == 'مشتری' ? 'customers' : widget.title == 'پذیرش تعمیر' ? 'repairs' : 'sales';
    await DemoStore.delete(category, selected);
    if (!mounted) return;
    setState(() => _selectedKeys.clear());
    widget.onChanged();
  }

  Future<void> addItem({Map<String, String>? existing}) async {
    final controllers = widget.fields.map((field) => TextEditingController(text: existing != null ? (existing[field] ?? '') : field == 'روش پرداخت' ? 'نقدی' : (field.contains('تاریخ') ? Jalali.now().formatCompactDate() : ''))).toList();
    final focusNodes = widget.fields.map((_) => FocusNode()).toList();

    Future<void> saveForm(BuildContext dialogContext) async {
      final item = <String, String>{};
      for (int i = 0; i < widget.fields.length; i++) {
        item[widget.fields[i]] = controllers[i].text.trim();
      }
      if (item.values.every((value) => value.isEmpty)) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('چیزی برای ثبت یا ذخیره وارد نشده است.')));
        return;
      }
      if ((item[widget.primary] ?? '').trim().isEmpty) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text('فیلد «${widget.primary}» اجباری است.')));
        return;
      }
      if (widget.title == 'مشتری' && (item['شماره تماس'] ?? '').isNotEmpty &&
          !RegExp(r'^\d{11}$').hasMatch(item['شماره تماس'] ?? '')) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('شماره موبایل در صورت ورود باید دقیقاً ۱۱ رقم باشد.')));
        return;
      }
      final category = widget.title == 'مشتری' ? 'customers' : widget.title == 'پذیرش تعمیر' ? 'repairs' : 'sales';
      try {
        if (existing == null) {
          await DemoStore.add(category, item);
        } else {
          await DemoStore.update(category, existing, item);
          if (widget.title == 'مشتری') {
            await DemoStore.renamePartyReferences(existing['نام مشتری'] ?? '', item['نام مشتری'] ?? '');
          }
        }
        if (dialogContext.mounted) Navigator.pop(dialogContext, true);
      } catch (error) {
        if (dialogContext.mounted) {
          ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text('ذخیره اطلاعات ناموفق بود: $error')));
        }
      }
    }

    Future<void> requestClose(BuildContext dialogContext) async {
      final dirty = existing == null
          ? controllers.any((c) => c.text.trim().isNotEmpty)
          : widget.fields.asMap().entries.any((e) => controllers[e.key].text.trim() != (existing[e.value] ?? ''));
      if (!dirty) {
        Navigator.pop(dialogContext, false);
        return;
      }
      final discard = await showDialog<bool>(context: dialogContext, builder: (d) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تغییرات ذخیره نشده‌اند'),
          content: const Text('برای ذخیره، دکمه «ذخیره» را بزنید. آیا می‌خواهید بدون ذخیره خارج شوید؟'),
          actions: [_horizontalDialogActions([
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('ادامه ویرایش')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('خروج بدون ذخیره')),
          ])],
        ),
      ));
      if (discard == true && dialogContext.mounted) Navigator.pop(dialogContext, false);
    }

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope<Object?>(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) requestClose(dialogContext);
        },
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text(existing == null ? 'ثبت ${widget.title} جدید' : 'ویرایش ${widget.title}'),
            content: SizedBox(
              width: 360,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.title == 'فاکتور فروش' || widget.title == 'پذیرش تعمیر')
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          'مبلغ دریافتی در همین سند از مانده حساب کم می‌شود. اگر قبلاً آن را ثبت کرده‌ای، دوباره به‌عنوان دریافت وجه وارد نکن.',
                          style: TextStyle(fontSize: 12, color: Theme.of(dialogContext).colorScheme.error),
                        ),
                      ),
                    if (widget.title == 'مشتری' && existing == null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            try {
                              // Open Android's native contact picker instead of listing contacts inside the app.
                              final selected = await FlutterContacts.openExternalPick();
                              if (!dialogContext.mounted || selected == null) return;

                              final contactName = selected.displayName.trim();
                              if (contactName.isNotEmpty && controllers.isNotEmpty) {
                                controllers[0].text = contactName;
                              }

                              String normalizePhone(String value) {
                                final mapped = value.replaceAllMapped(
                                  RegExp(r'[۰-۹٠-٩]'),
                                  (match) {
                                    const persianDigits = '۰۱۲۳۴۵۶۷۸۹';
                                    const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
                                    final digit = match.group(0)!;
                                    final pIndex = persianDigits.indexOf(digit);
                                    if (pIndex >= 0) return '$pIndex';
                                    final aIndex = arabicDigits.indexOf(digit);
                                    return aIndex >= 0 ? '$aIndex' : '';
                                  },
                                );
                                var digits = mapped.replaceAll(RegExp(r'[^0-9]'), '');
                                if (digits.startsWith('0098') && digits.length == 14) {
                                  digits = '0${digits.substring(4)}';
                                } else if (digits.startsWith('98') && digits.length == 12) {
                                  digits = '0${digits.substring(2)}';
                                } else if (digits.startsWith('9') && digits.length == 10) {
                                  digits = '0$digits';
                                }
                                return digits;
                              }

                              final phoneNumbers = selected.phones
                                  .map((phone) => normalizePhone(phone.number))
                                  .where((phone) => phone.isNotEmpty)
                                  .toSet()
                                  .toList();

                              if (controllers.length > 1 && phoneNumbers.isNotEmpty) {
                                String? chosenPhone = phoneNumbers.first;
                                if (phoneNumbers.length > 1) {
                                  chosenPhone = await showDialog<String>(
                                    context: dialogContext,
                                    builder: (pickerContext) => Directionality(
                                      textDirection: TextDirection.rtl,
                                      child: AlertDialog(
                                        title: const Text('انتخاب شماره تماس'),
                                        content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: phoneNumbers.map((number) => ListTile(
                                            leading: const Icon(Icons.phone_outlined),
                                            title: Text(number),
                                            onTap: () => Navigator.pop(pickerContext, number),
                                          )).toList(),
                                        ),
                                      ),
                                    ),
                                  );
                                }
                                if (chosenPhone != null && dialogContext.mounted) {
                                  controllers[1].text = chosenPhone;
                                }
                              } else if (controllers.length > 1 && dialogContext.mounted) {
                                ScaffoldMessenger.of(dialogContext).showSnackBar(
                                  const SnackBar(content: Text('برای این مخاطب شماره تلفنی ثبت نشده است؛ نام او در فرم قرار گرفت.')),
                                );
                              }
                            } catch (error) {
                              if (dialogContext.mounted) {
                                ScaffoldMessenger.of(dialogContext).showSnackBar(
                                  SnackBar(content: Text('انتخاب مخاطب ناموفق بود: $error')),
                                );
                              }
                            }
                          },
                          icon: const Icon(Icons.contacts_outlined),
                          label: const Text('انتخاب از مخاطبین گوشی'),
                        ),
                      ),
                    for (int i = 0; i < widget.fields.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: widget.title == 'پذیرش تعمیر' &&
                                widget.fields[i] == 'نام مشتری'
                            ? DropdownButtonFormField<String>(
                                value: DemoStore.customers
                                        .map((customer) => (customer['نام مشتری'] ?? '').trim())
                                        .where((name) => name.isNotEmpty)
                                        .toSet()
                                        .contains(controllers[i].text.trim())
                                    ? controllers[i].text.trim()
                                    : null,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'انتخاب مشتری ثبت‌شده',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.person_search_outlined),
                                ),
                                hint: Text(DemoStore.customers.isEmpty
                                    ? 'ابتدا مشتری را در بخش مشتریان ثبت کنید'
                                    : 'نام مشتری را انتخاب کنید'),
                                items: {
                                  ...DemoStore.customers
                                      .map((customer) => (customer['نام مشتری'] ?? '').trim())
                                      .where((name) => name.isNotEmpty),
                                  if (controllers[i].text.trim().isNotEmpty)
                                    controllers[i].text.trim(),
                                }.map((name) => DropdownMenuItem<String>(
                                      value: name,
                                      child: Text(name, overflow: TextOverflow.ellipsis),
                                    )).toList(),
                                onChanged: (value) {
                                  if (value != null) controllers[i].text = value;
                                },
                              )
                            : widget.title == 'فاکتور فروش' && widget.fields[i] == 'نام کالا (از انبار)'
                                ? DropdownButtonFormField<String>(
                                    value: DemoStore.products.any((p) => (p['نام کالا'] ?? '') == controllers[i].text.trim()) ? controllers[i].text.trim() : null,
                                    isExpanded: true,
                                    decoration: const InputDecoration(labelText: 'انتخاب کالا از انبار'),
                                    hint: const Text('فروش خدمت یا کالای خارج از انبار را خالی بگذارید'),
                                    items: DemoStore.products.map((p) {
                                      final name = p['نام کالا'] ?? '';
                                      final code = p['کد کالا'] ?? '';
                                      return DropdownMenuItem<String>(value: name, child: Text(code.isEmpty ? name : name + ' • ' + code, overflow: TextOverflow.ellipsis));
                                    }).toList(),
                                    onChanged: (value) { if (value != null) controllers[i].text = value; },
                                  )
                            : widget.title == 'پذیرش تعمیر' && widget.fields[i] == 'نام قطعه مصرفی از انبار'
                                ? DropdownButtonFormField<String>(
                                    value: DemoStore.products.any((p) => (p['نام کالا'] ?? '') == controllers[i].text.trim()) ? controllers[i].text.trim() : null,
                                    isExpanded: true,
                                    decoration: const InputDecoration(labelText: 'قطعه مصرفی (اختیاری)'),
                                    hint: const Text('در صورت مصرف قطعه از انبار انتخاب کنید'),
                                    items: DemoStore.products.map((p) {
                                      final name = p['نام کالا'] ?? '';
                                      return DropdownMenuItem<String>(value: name, child: Text('$name • موجودی: ${p['موجودی'] ?? '0'}'));
                                    }).toList(),
                                    onChanged: (value) { if (value != null) controllers[i].text = value; },
                                  )
                            : widget.title == 'فاکتور فروش' && widget.fields[i] == 'روش پرداخت'
                                ? DropdownButtonFormField<String>(
                                    value: ['نقدی','کارتی / حواله','چک'].contains(controllers[i].text) ? controllers[i].text : 'نقدی',
                                    decoration: const InputDecoration(labelText: 'روش دریافت وجه'),
                                    items: const ['نقدی','کارتی / حواله','چک'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                                    onChanged: (value) { if (value != null) controllers[i].text = value; },
                                  )
                            : widget.title == 'مشتری' && widget.fields[i] == 'ماهیت مانده اولیه'
                                ? DropdownButtonFormField<String>(
                                    value: controllers[i].text.trim().isEmpty ? 'بدهکار' : controllers[i].text.trim(),
                                    decoration: const InputDecoration(labelText: 'ماهیت مانده اولیه'),
                                    items: const ['بدهکار', 'بستانکار'].map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
                                    onChanged: (value) { if (value != null) controllers[i].text = value; },
                                  )
                            : TextField(
                                controller: controllers[i],
                                focusNode: focusNodes[i],
                                keyboardType: const ['شماره تماس', 'اجرت', 'تعداد', 'تعداد قطعه مصرفی', 'مبلغ کل', 'تخفیف', 'مبلغ دریافتی', 'مانده اولیه'].contains(widget.fields[i])
                                    ? TextInputType.number : TextInputType.text,
                                inputFormatters: widget.fields[i].contains('تاریخ') ? [PersianDateInputFormatter()] : const ['شماره تماس', 'اجرت', 'تعداد', 'تعداد قطعه مصرفی', 'مبلغ کل', 'تخفیف', 'مبلغ دریافتی', 'مانده اولیه'].contains(widget.fields[i]) ? [PersianDigitsOnlyFormatter()] : const [],
                                textInputAction: i == widget.fields.length - 1 ? TextInputAction.done : TextInputAction.next,
                                onSubmitted: (_) {
                                  if (i < focusNodes.length - 1) FocusScope.of(dialogContext).requestFocus(focusNodes[i + 1]);
                                  else FocusScope.of(dialogContext).unfocus();
                                },
                                decoration: InputDecoration(labelText: widget.fields[i], suffixIcon: widget.fields[i].contains('تاریخ') ? IconButton(tooltip: 'انتخاب تاریخ شمسی', icon: const Icon(Icons.calendar_month), onPressed: () async { final picked = await showPersianDatePicker(context: dialogContext, initialDate: Jalali.now(), firstDate: Jalali(1300, 1, 1), lastDate: Jalali(1500, 12, 29)); if (picked != null) controllers[i].text = picked.formatCompactDate(); }) : null),
                              ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [_horizontalDialogActions([
              if (existing != null) TextButton.icon(
                onPressed: () async {
                  if (widget.title == 'مشتری' && PartyAccounting.hasHistoryFor(existing['نام مشتری'] ?? '')) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('این مشتری سابقه مالی یا تعمیراتی دارد و حذف نمی‌شود.')));
                    return;
                  }
                  if (!await _confirmDelete(dialogContext, 1)) return;
                  final category = widget.title == 'مشتری' ? 'customers' : widget.title == 'پذیرش تعمیر' ? 'repairs' : 'sales';
                  await DemoStore.delete(category, [existing]);
                  if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('حذف'),
              ),
              TextButton(onPressed: () => requestClose(dialogContext), child: const Text('انصراف')),
              FilledButton(onPressed: () => saveForm(dialogContext), child: const Text('ذخیره')),
            ])],
          ),
        ),
      ),
    );
    for (final controller in controllers) { controller.dispose(); }
    for (final node in focusNodes) { node.dispose(); }
    if (saved == true && mounted) {
      setState(() {});
      widget.onChanged();
    }
  }


  Future<void> _showCustomerAccount(Map<String, String> customer) async {
    final customerName = (customer['نام مشتری'] ?? '').trim();
    final linkedSales = DemoStore.sales.where((x) => (x['نام مشتری'] ?? '').trim() == customerName).toList();
    final linkedRepairs = DemoStore.repairs.where((x) => (x['نام مشتری'] ?? '').trim() == customerName).toList();
    final accountEntries = PartyAccounting.entriesFor(customerName);
    int amountOf(Map<String, String> item, String key) => PartyAccounting.amount(item, key);
    final salesTotal = linkedSales.fold<int>(0, (sum, x) => sum + (amountOf(x, 'مبلغ کل') - amountOf(x, 'تخفیف')).clamp(0, 1 << 62).toInt());
    final repairTotal = linkedRepairs.fold<int>(0, (sum, x) => sum + amountOf(x, 'اجرت'));
    final debitTotal = accountEntries.where((x) => x['ماهیت'] == 'بدهکار').fold<int>(0, (sum, x) => sum + amountOf(x, 'مبلغ'));
    final creditTotal = accountEntries.where((x) => x['ماهیت'] == 'بستانکار').fold<int>(0, (sum, x) => sum + amountOf(x, 'مبلغ'));
    final balance = debitTotal - creditTotal;
    String money(int value) => value.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

    Future<void> addMoneyOperation(String operation) async {
      final amount = TextEditingController();
      final note = TextEditingController();
      String method = 'نقدی';
      final saved = await showDialog<bool>(context: context, builder: (d) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(builder: (d, refresh) => AlertDialog(
          title: Text(operation == 'دریافت وجه' ? 'دریافت از مشتری' : operation == 'پرداخت وجه' ? 'پرداخت به مشتری' : operation == 'متفرقه شخص بدهکار' ? 'ثبت بدهکاری مشتری' : 'ثبت بستانکاری مشتری'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('مشتری: $customerName'),
            if (operation == 'دریافت وجه' || operation == 'پرداخت وجه') const Text('اگر همین مبلغ را در فاکتور یا پذیرش ثبت کرده‌اید، دوباره اینجا ثبت نکنید.', style: TextStyle(fontSize: 12, color: Colors.orange)),
            TextField(controller: amount, keyboardType: TextInputType.number, inputFormatters: [PersianDigitsOnlyFormatter()], decoration: const InputDecoration(labelText: 'مبلغ (تومان)')),
            if (operation == 'دریافت وجه' || operation == 'پرداخت وجه') DropdownButtonFormField<String>(value: method, decoration: const InputDecoration(labelText: 'روش پرداخت'), items: const ['نقدی', 'چک', 'کارتی / حواله'].map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(), onChanged: (v) => refresh(() => method = v ?? 'نقدی')),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'توضیحات')),
          ]),
          actions: [_horizontalDialogActions([
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('انصراف')),
            FilledButton(onPressed: () async {
              final value = PartyAccounting.amount({'مبلغ': amount.text}, 'مبلغ');
              if (value <= 0) {
                ScaffoldMessenger.of(d).showSnackBar(const SnackBar(content: Text('مبلغ معتبر وارد کنید.')));
                return;
              }
              try {
                await DemoStore.add('operations', {
                  'نوع عملیات': operation, 'نام شخص': customerName, 'مبلغ': value.toString(),
                  'روش': method, 'تاریخ': Jalali.now().formatCompactDate(), 'توضیحات': note.text.trim(),
                });
                if (d.mounted) Navigator.pop(d, true);
              } catch (error) {
                if (d.mounted) ScaffoldMessenger.of(d).showSnackBar(SnackBar(content: Text('ثبت عملیات ناموفق بود: $error')));
              }
            }, child: const Text('ثبت')),
          ])],
        )),
      ));
      amount.dispose(); note.dispose();
      if (saved == true && mounted) {
        Navigator.pop(context);
        await _showCustomerAccount(customer);
        setState(() {});
        widget.onChanged();
      }
    }

    await showDialog<void>(context: context, builder: (d) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text(customerName, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('شماره تماس: ${customer['شماره تماس'] ?? '—'}'),
            if ((customer['آدرس'] ?? '').isNotEmpty) Text('آدرس: ${customer['آدرس']}'),
            if ((customer['توضیحات'] ?? '').isNotEmpty) Text('توضیحات: ${customer['توضیحات']}'),
            const Divider(height: 24),
            Card(color: Theme.of(d).colorScheme.secondaryContainer, child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
              const Text('مانده حساب'),
              Text('${money(balance.abs())} تومان', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              Text(balance > 0 ? 'بدهکار' : balance < 0 ? 'بستانکار' : 'تسویه'),
            ]))),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(onPressed: () => addMoneyOperation('دریافت وجه'), icon: const Icon(Icons.call_received), label: const Text('دریافت وجه')),
              OutlinedButton.icon(onPressed: () => addMoneyOperation('پرداخت وجه'), icon: const Icon(Icons.call_made), label: const Text('پرداخت وجه')),
              OutlinedButton.icon(onPressed: () => addMoneyOperation('متفرقه شخص بدهکار'), icon: const Icon(Icons.add_circle_outline), label: const Text('ثبت بدهکار')),
              OutlinedButton.icon(onPressed: () => addMoneyOperation('متفرقه شخص بستانکار'), icon: const Icon(Icons.remove_circle_outline), label: const Text('ثبت بستانکار')),
            ]),
            const Divider(height: 24),
            Text('جمع بدهکار: ${money(debitTotal)} تومان'),
            Text('جمع بستانکار: ${money(creditTotal)} تومان'),
            Text('فاکتورهای فروش: ${linkedSales.length} مورد • ${money(salesTotal)} تومان'),
            Text('پذیرش‌های تعمیر: ${linkedRepairs.length} مورد • اجرت ${money(repairTotal)} تومان'),
            const SizedBox(height: 12),
            const Text('دفتر گردش حساب', style: TextStyle(fontWeight: FontWeight.bold)),
            if (accountEntries.isEmpty)
              const Text('برای این شخص هنوز گردش مالی ثبت نشده است.'),
            for (final entry in accountEntries.reversed)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(entry['ماهیت'] == 'بدهکار' ? Icons.arrow_circle_up : Icons.arrow_circle_down, color: entry['ماهیت'] == 'بدهکار' ? Colors.red : Colors.green),
                title: Text(entry['نوع'] ?? 'سند مالی'),
                subtitle: Text('${entry['تاریخ'] ?? ''} • ${entry['شرح'] ?? ''}'),
                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${money(amountOf(entry, 'مبلغ'))} تومان'),
                  Text(entry['ماهیت'] ?? '', style: TextStyle(fontSize: 11, color: entry['ماهیت'] == 'بدهکار' ? Colors.red : Colors.green)),
                  Text('مانده: ${money(amountOf(entry, 'مانده پس از سند').abs())} • ${entry['وضعیت مانده'] ?? ''}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                ]),
              ),
          ],
        ))),
        actions: [_horizontalDialogActions([
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('بستن')),
        ])],
      ),
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.transparent,
        bottomNavigationBar: widget.title == 'مشتری' ? SafeArea(child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('جمع بدهکاران مشتریان: ${PartyAccounting.formatMoney(PartyAccounting.totalDebtors())} تومان'),
            Text('جمع بستانکاران مشتریان: ${PartyAccounting.formatMoney(PartyAccounting.totalCreditors())} تومان'),
          ]),
        )) : null,
        floatingActionButton: FloatingActionButton(
          heroTag: 'add-${widget.title}',
          backgroundColor: yellow,
          foregroundColor: black,
          onPressed: addItem,
          child: const Icon(Icons.add),
        ),
        body: Column(children: [
          if (_selectedKeys.isNotEmpty)
            Material(color: Theme.of(context).colorScheme.secondaryContainer, child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(children: [
                Text('${_selectedKeys.length} مورد انتخاب شده'),
                const Spacer(),
                TextButton(onPressed: () => setState(() => _selectedKeys.clear()), child: const Text('لغو انتخاب')),
                TextButton.icon(onPressed: () => setState(() => _selectedKeys.addAll(widget.data.map(_keyOf))), icon: const Icon(Icons.select_all), label: const Text('انتخاب همه')),
                IconButton(onPressed: _deleteSelected, icon: const Icon(Icons.delete, color: Colors.red), tooltip: 'حذف موارد انتخاب‌شده'),
              ]),
            )),
          Expanded(child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (widget.data.isEmpty)
                const Padding(padding: EdgeInsets.all(28), child: Center(child: Text('هنوز اطلاعاتی ثبت نشده است'))),
              for (final item in widget.data.reversed)
                Card(child: ListTile(
                  leading: CircleAvatar(child: Icon(_selectedKeys.contains(_keyOf(item)) ? Icons.check : Icons.description)),
                  title: Text(item[widget.primary]?.isNotEmpty == true ? item[widget.primary]! : 'بدون عنوان'),
                  subtitle: widget.title == 'مشتری'
                      ? Builder(builder: (context) {
                          final balance = PartyAccounting.balanceFor(item['نام مشتری'] ?? '');
                          final status = balance > 0 ? 'بدهکار' : balance < 0 ? 'بستانکار' : 'تسویه';
                          final details = item.entries.where((e) => e.value.isNotEmpty && !['مانده اولیه', 'ماهیت مانده اولیه'].contains(e.key)).map((e) => '${e.key}: ${e.value}').join(' • ');
                          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            if (details.isNotEmpty) Text(details, maxLines: 2, overflow: TextOverflow.ellipsis),
                            Text('مانده: ${PartyAccounting.formatMoney(balance.abs())} تومان • ${status}', style: TextStyle(fontWeight: FontWeight.bold, color: balance > 0 ? Colors.red : balance < 0 ? Colors.green : Colors.grey)),
                          ]);
                        })
                      : Text(item.entries.where((e) => e.value.isNotEmpty).map((e) => '${e.key}: ${e.value}').join(' • ')),
                  trailing: _selectedKeys.isNotEmpty ? Checkbox(value: _selectedKeys.contains(_keyOf(item)), onChanged: (_) => setState(() { final k=_keyOf(item); _selectedKeys.contains(k) ? _selectedKeys.remove(k) : _selectedKeys.add(k); })) : widget.title == 'مشتری' ? PopupMenuButton<String>(onSelected: (v) { if (v == 'edit') addItem(existing: item); else _showCustomerAccount(item); }, itemBuilder: (_) => const [PopupMenuItem(value: 'view', child: Text('پرونده و مانده‌حساب')), PopupMenuItem(value: 'edit', child: Text('ویرایش اطلاعات مشتری'))]) : const Icon(Icons.edit_outlined),
                  onLongPress: () => setState(() => _selectedKeys.add(_keyOf(item))),
                  onTap: () {
                    if (_selectedKeys.isNotEmpty) setState(() { final k=_keyOf(item); _selectedKeys.contains(k) ? _selectedKeys.remove(k) : _selectedKeys.add(k); });
                    else if (widget.title == 'مشتری') _showCustomerAccount(item);
                    else addItem(existing: item);
                  },
                )),
            ],
          )),
        ]),
      );
}

class ProductPage extends StatefulWidget {
  final VoidCallback onChanged;
  const ProductPage({super.key, required this.onChanged});

  @override
  State<ProductPage> createState() => _ProductPageState();
}

class _ProductPageState extends State<ProductPage> {
  final Set<String> _selectedProducts = {};

  List<String> _supplierNames({String? include}) {
    final names = AppSettings.purchaseRecords
        .map((record) => (record['نام فروشنده'] ?? '').trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList();
    final previous = include?.trim() ?? '';
    if (previous.isNotEmpty && !names.contains(previous)) names.add(previous);
    names.sort();
    return names;
  }

  Future<void> _deleteProducts(List<Map<String, String>> items) async {
    if (items.isEmpty) return;
    final hasHistory = items.any((product) => DemoStore.stockMovements.any((movement) =>
        (movement['کد کالا'] ?? '') == (product['کد کالا'] ?? '') &&
        (movement['نام کالا'] ?? '') == (product['نام کالا'] ?? '')));
    if (hasHistory) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('کالای دارای سابقه گردش انبار حذف نمی‌شود؛ برای حفظ کاردکس، موجودی آن را صفر کنید.')));
      return;
    }
    if (!await _confirmDelete(context, items.length)) return;
    await DemoStore.delete('products', items);
    if (!mounted) return;
    setState(() => _selectedProducts.clear());
    widget.onChanged();
  }

  Future<void> addProduct() async {
    final names = ['نام کالا', 'کد کالا', 'موجودی', 'قیمت خرید هر واحد', 'قیمت فروش'];
    final saleDate = TextEditingController(text: Jalali.now().formatCompactDate());
    final c = List.generate(names.length, (_) => TextEditingController());
    final shipping = TextEditingController(text: '0');
    final freight = TextEditingController(text: '0');
    final other = TextEditingController(text: '0');
    final vatRate = TextEditingController(text: '0');
    bool vatIncluded = false;
    String? productGroup;
    String? productSubgroup;
    String? selectedSupplier;
    final supplierNames = _supplierNames();
    String unit = 'عدد';
    bool isUsed = false;
    String? productImageBase64;
    final imagePicker = ImagePicker();

    Future<void> pickProductImage(StateSetter refresh, ImageSource source) async {
      try {
        final picked = await imagePicker.pickImage(
          source: source,
          imageQuality: 70,
          maxWidth: 1600,
          maxHeight: 1600,
        );
        if (picked == null) return;
        final compressed = await FlutterImageCompress.compressWithFile(
          picked.path,
          minWidth: 900,
          minHeight: 900,
          quality: 55,
          format: CompressFormat.jpeg,
        );
        if (compressed == null || compressed.isEmpty) {
          throw Exception('فشرده‌سازی تصویر انجام نشد');
        }
        productImageBase64 = base64Encode(compressed);
        refresh(() {});
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('انتخاب یا فشرده‌سازی عکس ناموفق بود: $e')),
          );
        }
      }
    }

    double number(TextEditingController x) => double.tryParse(x.text.replaceAll(',', '').trim()) ?? 0;
    double totalCost() {
      final qty = number(c[2]);
      final purchase = number(c[3]) * qty;
      final extra = number(shipping) + number(freight) + number(other);
      final vat = vatIncluded ? purchase * number(vatRate) / 100 : 0;
      return purchase + extra + vat;
    }

    Future<void> requestProductClose(BuildContext dialogContext) async {
      final dirty = c.any((x) => x.text.trim().isNotEmpty) ||
          shipping.text.trim() != '0' || freight.text.trim() != '0' || other.text.trim() != '0' ||
          vatRate.text.trim() != '0' || vatIncluded || unit != 'عدد' || isUsed ||
          productGroup != null || productSubgroup != null || selectedSupplier != null || productImageBase64 != null;
      if (!dirty) { Navigator.pop(dialogContext, false); return; }
      final discard = await showDialog<bool>(context: dialogContext, builder: (d) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تغییرات ذخیره نشده‌اند'),
          content: const Text('اطلاعات کالا ذخیره نشده است. می‌خواهید بدون ذخیره خارج شوید؟'),
          actions: [_horizontalDialogActions([
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('ادامه ویرایش')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('خروج بدون ذخیره')),
          ])],
        ),
      ));
      if (discard == true && dialogContext.mounted) Navigator.pop(dialogContext, false);
    }

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope<Object?>(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) { if (!didPop) requestProductClose(dialogContext); },
        child: Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (context, refresh) => AlertDialog(
            title: const Text('ثبت کالا'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(controller: c[0], decoration: const InputDecoration(labelText: 'نام کالا')),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: unit,
                      decoration: const InputDecoration(labelText: 'واحد شمارش کالا'),
                      items: const ['عدد', 'گرم', 'کیلوگرم', 'میلی‌متر', 'سانتی‌متر', 'متر', 'میلی‌لیتر', 'لیتر']
                          .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                          .toList(),
                      onChanged: (value) => refresh(() => unit = value ?? 'عدد'),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: isUsed,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('این کالا دست دوم است'),
                      onChanged: (value) => refresh(() => isUsed = value ?? false),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: productGroup,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'گروه اصلی'),
                      items: AppSettings.productGroups.keys.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                      onChanged: (v) => refresh(() { productGroup = v; productSubgroup = null; }),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: productSubgroup,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'زیرگروه'),
                      items: (productGroup == null ? <String>[] : AppSettings.productGroups[productGroup] ?? <String>[]).map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                      onChanged: (v) => refresh(() => productSubgroup = v),
                    ),
                    const SizedBox(height: 10),
                    for (int i = 1; i < names.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: TextField(
                          controller: c[i],
                          keyboardType: TextInputType.numberWithOptions(decimal: i == 2 && unit != 'عدد'),
                          inputFormatters: i == 1 || i >= 3 || (i == 2 && unit == 'عدد')
                              ? [PersianDigitsOnlyFormatter()]
                              : [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}'))],
                          textInputAction: TextInputAction.next,
                          onChanged: (_) => refresh(() {}),
                          decoration: InputDecoration(labelText: names[i]),
                        ),
                      ),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<String>(
                      value: selectedSupplier,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'خرید از / نام فروشنده',
                        helperText: supplierNames.isEmpty
                            ? 'ابتدا فروشنده را در تنظیمات برنامه ثبت کنید.'
                            : 'فروشنده از فهرست مدیریت خرید انتخاب می‌شود.',
                        suffixIcon: selectedSupplier == null
                            ? null
                            : IconButton(
                                tooltip: 'پاک کردن انتخاب',
                                icon: const Icon(Icons.clear),
                                onPressed: () => refresh(() => selectedSupplier = null),
                              ),
                      ),
                      hint: const Text('انتخاب فروشنده'),
                      items: supplierNames
                          .map((name) => DropdownMenuItem<String>(value: name, child: Text(name)))
                          .toList(),
                      onChanged: supplierNames.isEmpty
                          ? null
                          : (value) => refresh(() => selectedSupplier = value),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: saleDate,
                      keyboardType: TextInputType.datetime,
                      textDirection: TextDirection.ltr,
                      inputFormatters: [PersianDateInputFormatter()],
                      decoration: InputDecoration(
                        labelText: 'تاریخ ثبت کالا (شمسی)',
                        hintText: '۱۴۰۵/۰۸/۲۲',
                        prefixIcon: IconButton(
                          tooltip: 'انتخاب از تقویم شمسی',
                          icon: const Icon(Icons.calendar_month),
                          onPressed: () async {
                            final initial = Jalali.now();
                            final picked = await showPersianDatePicker(
                              context: context,
                              initialDate: initial,
                              firstDate: Jalali(1300, 1, 1),
                              lastDate: Jalali(1500, 12, 29),
                            );
                            if (picked != null) {
                              saleDate.text = picked.formatCompactDate();
                              refresh(() {});
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text('تصویر کالا', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black26), borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        children: [
                          if (productImageBase64 != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(base64Decode(productImageBase64!), height: 150, fit: BoxFit.contain),
                            )
                          else
                            const Padding(
                              padding: EdgeInsets.all(18),
                              child: Column(children: [Icon(Icons.image_outlined, size: 42, color: Colors.black45), SizedBox(height: 6), Text('هنوز عکسی انتخاب نشده است')]),
                            ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => pickProductImage(refresh, ImageSource.gallery),
                                icon: const Icon(Icons.photo_library_outlined),
                                label: Text(productImageBase64 == null ? 'انتخاب از گالری' : 'تعویض عکس'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => pickProductImage(refresh, ImageSource.camera),
                                icon: const Icon(Icons.camera_alt_outlined),
                                label: const Text('گرفتن عکس'),
                              ),
                              if (productImageBase64 != null)
                                TextButton.icon(
                                  onPressed: () => refresh(() => productImageBase64 = null),
                                  icon: const Icon(Icons.delete_outline),
                                  label: const Text('حذف عکس'),
                                ),
                            ],
                          ),
                          const Text('عکس به‌صورت خودکار با کیفیت مناسب و حجم کمتر ذخیره می‌شود.', style: TextStyle(fontSize: 11, color: Colors.black54), textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                    const Divider(height: 24),
                    const Align(alignment: Alignment.centerRight, child: Text('هزینه‌های رساندن کالا به مغازه', style: TextStyle(fontWeight: FontWeight.bold))),
                    const SizedBox(height: 10),
                    TextField(controller: shipping, keyboardType: TextInputType.number, inputFormatters: [PersianDigitsOnlyFormatter()], onChanged: (_) => refresh(() {}), decoration: const InputDecoration(labelText: 'هزینه پست')),
                    const SizedBox(height: 10),
                    TextField(controller: freight, keyboardType: TextInputType.number, inputFormatters: [PersianDigitsOnlyFormatter()], onChanged: (_) => refresh(() {}), decoration: const InputDecoration(labelText: 'هزینه باربری / حمل')),
                    const SizedBox(height: 10),
                    TextField(controller: other, keyboardType: TextInputType.number, inputFormatters: [PersianDigitsOnlyFormatter()], onChanged: (_) => refresh(() {}), decoration: const InputDecoration(labelText: 'سایر هزینه‌های خرید')),
                    const Divider(height: 24),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: vatIncluded,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('این کالا مشمول ارزش افزوده است'),
                      onChanged: (v) => refresh(() => vatIncluded = v ?? false),
                    ),
                    if (vatIncluded)
                      TextField(
                        controller: vatRate,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}'))],
                        onChanged: (_) => refresh(() {}),
                        decoration: const InputDecoration(labelText: 'درصد ارزش افزوده', suffixText: '٪'),
                      ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: const Color(0xFFFFF4CC), borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('محاسبه خودکار بهای تمام‌شده', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          Text('مبلغ ارزش افزوده: ${(vatIncluded ? number(c[3]) * number(c[2]) * number(vatRate) / 100 : 0).toStringAsFixed(0)} تومان'),
                          Text('جمع کل خرید و هزینه‌ها: ${totalCost().toStringAsFixed(0)} تومان'),
                          Text('بهای تمام‌شده هر واحد: ${((number(c[2]) > 0) ? totalCost() / number(c[2]) : 0).toStringAsFixed(0)} تومان'),
                          const Text('هزینه‌ها به نسبت تعداد، بین کالاها سرشکن می‌شوند.', style: TextStyle(fontSize: 11, color: Colors.black54)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [_horizontalDialogActions([
              TextButton(onPressed: () => requestProductClose(dialogContext), child: const Text('انصراف')),
              FilledButton(
                onPressed: () {
                  final hasAnyEntry = c.any((x) => x.text.trim().isNotEmpty) ||
                      productImageBase64 != null || productGroup != null || productSubgroup != null ||
                      isUsed || vatIncluded || number(shipping) > 0 || number(freight) > 0 ||
                      number(other) > 0 || number(vatRate) > 0;
                  if (!hasAnyEntry) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('چیزی برای ثبت یا ذخیره وارد نشده است.')));
                    return;
                  }
                  if (c[0].text.trim().isEmpty) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('نام کالا اجباری است.')));
                    return;
                  }
                  final qty = number(c[2]);
                  final total = totalCost();
                  final item = <String, String>{};
                  for (int i = 0; i < names.length; i++) { item[names[i]] = c[i].text.trim(); }
                  item['نام فروشنده'] = selectedSupplier ?? '';
                  item['تاریخ ثبت کالا'] = saleDate.text.trim();
                  item['گروه اصلی'] = productGroup ?? '';
                  item['زیرگروه'] = productSubgroup ?? '';
                  item['تصویر کالا'] = productImageBase64 ?? '';
                  item['واحد شمارش'] = unit;
                  item['وضعیت کالا'] = isUsed ? 'دست دوم' : 'نو';
                  item['هزینه پست'] = shipping.text;
                  item['هزینه باربری / حمل'] = freight.text;
                  item['سایر هزینه‌ها'] = other.text;
                  item['مشمول ارزش افزوده'] = vatIncluded ? 'بله' : 'خیر';
                  item['درصد ارزش افزوده'] = vatIncluded ? vatRate.text : '0';
                  item['جمع بهای تمام‌شده'] = total.toStringAsFixed(0);
                  item['بهای تمام‌شده هر واحد'] = (qty > 0 ? total / qty : 0).toStringAsFixed(0);
                  DemoStore.add('products', item).then((_) {
                    if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                  }).catchError((error) {
                    if (dialogContext.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ذخیره کالا ناموفق بود: $error')));
                    }
                  });
                },
                child: const Text('ذخیره کالا'),
              ),
            ])],
          ),
        ),
        ),
      ),
    );
    for (final x in [...c, shipping, freight, other, vatRate, saleDate]) { x.dispose(); }
    if (saved == true && mounted) { setState(() {}); widget.onChanged(); }
  }

  Future<void> editProduct(Map<String, String> item) async {
    final groupKey = item['گروه اصلی'] ?? '';
    if (groupKey.isNotEmpty && !AppSettings.productGroups.containsKey(groupKey)) {
      AppSettings.productGroups[groupKey] = item['زیرگروه']?.isNotEmpty == true ? [item['زیرگروه']!] : [];
      await AppSettings.saveProductGroups();
    }
    final editable = item.keys.where((k) => k != 'تصویر کالا' && k != 'گروه اصلی' && k != 'زیرگروه' && k != 'نام فروشنده').toList();
    final controllers = {for (final key in editable) key: TextEditingController(text: item[key] ?? '')};
    final previousSupplier = (item['نام فروشنده'] ?? '').trim();
    String? supplier = previousSupplier.isEmpty ? null : previousSupplier;
    final supplierNames = _supplierNames(include: supplier);
    String? group = groupKey.isEmpty ? null : groupKey;
    String? subgroup = (item['زیرگروه'] ?? '').isEmpty ? null : item['زیرگروه'];

    bool dirty() {
      for (final key in editable) {
        if (controllers[key]!.text.trim() != (item[key] ?? '')) return true;
      }
      return supplier != (previousSupplier.isEmpty ? null : previousSupplier) ||
          group != (item['گروه اصلی']?.isEmpty == true ? null : item['گروه اصلی']) ||
          subgroup != (item['زیرگروه']?.isEmpty == true ? null : item['زیرگروه']);
    }

    bool allowDialogPop = false;

    Future<void> requestClose(BuildContext dialogContext) async {
      if (!dirty()) { allowDialogPop = true; Navigator.pop(dialogContext, false); return; }
      final discard = await showDialog<bool>(context: dialogContext, builder: (d) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تغییرات ذخیره نشده‌اند'),
          content: const Text('ویرایش کالا ذخیره نشده است. بدون ذخیره خارج می‌شوید؟'),
          actions: [_horizontalDialogActions([TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('ادامه ویرایش')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('خروج بدون ذخیره'))])],
        ),
      ));
      if (discard == true && dialogContext.mounted) { allowDialogPop = true; Navigator.pop(dialogContext, false); }
    }

    final result = await showDialog<bool>(context: context, barrierDismissible: false, builder: (d) => PopScope<Object?>(
      canPop: allowDialogPop,
      onPopInvokedWithResult: (didPop, result) { if (!didPop) requestClose(d); },
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(builder: (d, refresh) => AlertDialog(
          title: const Text('ویرایش کالا'),
          content: SizedBox(width: 380, child: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final key in editable)
                Padding(padding: const EdgeInsets.only(bottom: 9), child: TextField(
                  controller: controllers[key],
                  keyboardType: const ['موجودی','قیمت خرید هر واحد','قیمت فروش','کد کالا'].contains(key) ? TextInputType.number : TextInputType.text,
                  decoration: InputDecoration(labelText: key),
                )),
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(
                value: supplier,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'خرید از / نام فروشنده',
                  helperText: supplierNames.isEmpty
                      ? 'ابتدا فروشنده را در تنظیمات برنامه ثبت کنید.'
                      : 'فروشنده از فهرست مدیریت خرید انتخاب می‌شود.',
                  suffixIcon: supplier == null
                      ? null
                      : IconButton(
                          tooltip: 'پاک کردن انتخاب',
                          icon: const Icon(Icons.clear),
                          onPressed: () => refresh(() => supplier = null),
                        ),
                ),
                hint: const Text('انتخاب فروشنده'),
                items: supplierNames
                    .map((name) => DropdownMenuItem<String>(value: name, child: Text(name)))
                    .toList(),
                onChanged: supplierNames.isEmpty
                    ? null
                    : (value) => refresh(() => supplier = value),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: group,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'گروه اصلی'),
                items: AppSettings.productGroups.keys.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                onChanged: (v) => refresh(() { group = v; subgroup = null; }),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: subgroup,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'زیرگروه'),
                items: (group == null ? <String>[] : AppSettings.productGroups[group] ?? <String>[]).map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                onChanged: (v) => refresh(() => subgroup = v),
              ),
            ],
          ))),
          actions: [_horizontalDialogActions([
            TextButton.icon(onPressed: () async {
              final hasHistory = DemoStore.stockMovements.any((movement) =>
                  (movement['کد کالا'] ?? '') == (item['کد کالا'] ?? '') &&
                  (movement['نام کالا'] ?? '') == (item['نام کالا'] ?? ''));
              if (hasHistory) {
                ScaffoldMessenger.of(d).showSnackBar(const SnackBar(content: Text('این کالا سابقه گردش انبار دارد و حذف نمی‌شود.')));
                return;
              }
              if (!await _confirmDelete(d, 1)) return;
              await DemoStore.delete('products', [item]);
              if (d.mounted) { allowDialogPop = true; Navigator.pop(d, true); }
            }, icon: const Icon(Icons.delete_outline), label: const Text('حذف')),
            TextButton(onPressed: () => requestClose(d), child: const Text('انصراف')),
            FilledButton(onPressed: () async {
              if (!dirty()) {
                ScaffoldMessenger.of(d).showSnackBar(const SnackBar(content: Text('چیزی برای ثبت یا ذخیره وارد نشده است.')));
                return;
              }
              final changed = Map<String,String>.from(item);
              for (final key in editable) { changed[key] = controllers[key]!.text.trim(); }
              changed['نام فروشنده'] = supplier ?? '';
              changed['گروه اصلی'] = group ?? '';
              changed['زیرگروه'] = subgroup ?? '';
              final hasHistory = DemoStore.stockMovements.any((movement) =>
                  (movement['کد کالا'] ?? '') == (item['کد کالا'] ?? '') &&
                  (movement['نام کالا'] ?? '') == (item['نام کالا'] ?? ''));
              if (hasHistory &&
                  (changed['نام کالا'] != item['نام کالا'] || changed['کد کالا'] != item['کد کالا'])) {
                ScaffoldMessenger.of(d).showSnackBar(const SnackBar(content: Text('نام یا کد کالایی که کاردکس دارد تغییر نمی‌کند تا سابقه ورود و خروج آن محفوظ بماند.')));
                return;
              }
              try {
                await DemoStore.update('products', item, changed);
                if (d.mounted) { allowDialogPop = true; Navigator.pop(d, true); }
              } catch (error) {
                if (d.mounted) ScaffoldMessenger.of(d).showSnackBar(SnackBar(content: Text('ذخیره کالا ناموفق بود: $error')));
              }
            }, child: const Text('ذخیره تغییرات')),
          ])],
        )),
      ),
    ));
    for (final c in controllers.values) { c.dispose(); }
    if (result == true && mounted) { setState(() {}); widget.onChanged(); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton(
          heroTag: 'add-product', backgroundColor: yellow, foregroundColor: black,
          onPressed: addProduct, child: const Icon(Icons.add),
        ),
        body: Column(children: [
          if (_selectedProducts.isNotEmpty)
            Material(color: Theme.of(context).colorScheme.secondaryContainer, child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(children: [
                Text('${_selectedProducts.length} مورد انتخاب شده'),
                const Spacer(),
                TextButton(onPressed: () => setState(() => _selectedProducts.clear()), child: const Text('لغو انتخاب')),
                TextButton.icon(onPressed: () => setState(() => _selectedProducts.addAll(DemoStore.products.map((x) => jsonEncode(x)))), icon: const Icon(Icons.select_all), label: const Text('انتخاب همه')),
                IconButton(onPressed: () => _deleteProducts(DemoStore.products.where((x) => _selectedProducts.contains(jsonEncode(x))).toList()), icon: const Icon(Icons.delete, color: Colors.red)),
              ]),
            )),
          Expanded(child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (DemoStore.products.isEmpty)
                const Padding(padding: EdgeInsets.all(28), child: Center(child: Text('هنوز کالایی ثبت نشده است'))),
              for (final item in DemoStore.products.reversed)
                Card(child: ListTile(
                  leading: AppSettings.productImageMode == 'عدم نمایش عکس کالا'
                      ? null
                      : (item['تصویر کالا'] ?? '').isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(
                                base64Decode(item['تصویر کالا']!),
                                width: AppSettings.productImageMode == 'کوچک کردن عکس کالا' ? 28 : 48,
                                height: AppSettings.productImageMode == 'کوچک کردن عکس کالا' ? 28 : 48,
                                fit: BoxFit.cover,
                              ),
                            )
                          : (AppSettings.productImageMode == 'کوچک کردن عکس کالا'
                              ? const Icon(Icons.inventory_2, size: 22)
                              : CircleAvatar(child: Icon(_selectedProducts.contains(jsonEncode(item)) ? Icons.check : Icons.inventory_2))),
                  title: Text(item['نام کالا'] ?? 'بدون نام'),
                  onLongPress: () => setState(() => _selectedProducts.add(jsonEncode(item))),
                  onTap: () {
                    if (_selectedProducts.isNotEmpty) setState(() { final k=jsonEncode(item); _selectedProducts.contains(k) ? _selectedProducts.remove(k) : _selectedProducts.add(k); });
                    else editProduct(item);
                  },
                  trailing: _selectedProducts.isNotEmpty ? Checkbox(value: _selectedProducts.contains(jsonEncode(item)), onChanged: (_) => setState(() { final k=jsonEncode(item); _selectedProducts.contains(k) ? _selectedProducts.remove(k) : _selectedProducts.add(k); })) : const Icon(Icons.edit_outlined),
                  subtitle: Text('موجودی: ${item['موجودی'] ?? '0'} ${item['واحد شمارش'] ?? 'عدد'}  •  ${item['وضعیت کالا'] ?? 'نو'}  •  بهای تمام‌شده هر واحد: ${item['بهای تمام‌شده هر واحد'] ?? '0'} تومان'),
                )),
            ],
          )),
        ]),
      );
}

class CustomerPage extends StatelessWidget {
  final VoidCallback onChanged;
  const CustomerPage({super.key, required this.onChanged});

  @override
  Widget build(BuildContext context) => SimpleListPage(
        title: 'مشتری',
        data: DemoStore.customers,
        fields: const ['نام مشتری', 'شماره تماس', 'آدرس', 'توضیحات', 'مانده اولیه', 'ماهیت مانده اولیه', 'تاریخ مانده اولیه'],
        primary: 'نام مشتری',
        onChanged: onChanged,
      );
}

class RepairPage extends StatelessWidget {
  final VoidCallback onChanged;
  const RepairPage({super.key, required this.onChanged});

  @override
  Widget build(BuildContext context) => SimpleListPage(
        title: 'پذیرش تعمیر',
        data: DemoStore.repairs,
        fields: const ['نام مشتری', 'نوع دستگاه', 'شرح عیب', 'نام قطعه مصرفی از انبار', 'تعداد قطعه مصرفی', 'اجرت', 'مبلغ دریافتی', 'تاریخ پذیرش', 'وضعیت تعمیر'],
        primary: 'نوع دستگاه',
        onChanged: onChanged,
      );
}

class SalesPage extends StatelessWidget {
  final VoidCallback onChanged;
  const SalesPage({super.key, required this.onChanged});

  @override
  Widget build(BuildContext context) => SimpleListPage(
        title: 'فاکتور فروش',
        data: DemoStore.sales,
        fields: const ['نام مشتری', 'نام کالا (از انبار)', 'شرح کالا/خدمت', 'تعداد', 'مبلغ کل', 'تخفیف', 'مبلغ دریافتی', 'روش پرداخت', 'تاریخ فاکتور'],
        primary: 'نام مشتری',
        onChanged: onChanged,
      );
}

class SettingsPage extends StatefulWidget {
  static bool Function()? isDirty;
  static Future<bool> Function()? savePending;
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController storeName;
  late final TextEditingController managerName;
  late final TextEditingController phone;
  late final TextEditingController address;
  late final TextEditingController postalCode;
  late bool darkMode;
  late String themeMode;
  late String drawerImage;
  late double fontScale;

  @override
  void initState() {
    super.initState();
    storeName = TextEditingController(text: AppSettings.storeName);
    managerName = TextEditingController(text: AppSettings.managerName);
    phone = TextEditingController(text: AppSettings.phone);
    address = TextEditingController(text: AppSettings.address);
    postalCode = TextEditingController(text: AppSettings.postalCode);
    darkMode = AppSettings.darkMode;
    themeMode = AppSettings.themeMode;
    drawerImage = AppSettings.drawerImage;
    fontScale = AppSettings.fontScale;
    SettingsPage.isDirty = _hasUnsavedChanges;
    SettingsPage.savePending = _saveSettingsInternal;
  }

  bool _hasUnsavedChanges() =>
      storeName.text.trim() != AppSettings.storeName ||
      managerName.text.trim() != AppSettings.managerName ||
      phone.text.trim() != AppSettings.phone ||
      address.text.trim() != AppSettings.address ||
      postalCode.text.trim() != AppSettings.postalCode ||
      themeMode != AppSettings.themeMode || fontScale != AppSettings.fontScale || drawerImage != AppSettings.drawerImage;

  @override
  void dispose() {
    storeName.dispose();
    managerName.dispose();
    phone.dispose();
    address.dispose();
    postalCode.dispose();
    if (SettingsPage.isDirty == _hasUnsavedChanges) SettingsPage.isDirty = null;
    if (SettingsPage.savePending == _saveSettingsInternal) SettingsPage.savePending = null;
    super.dispose();
  }

  Future<String?> _askGroupRename(String title, String current) async {
    final controller = TextEditingController(text: current);
    final value = await showDialog<String>(context: context, builder: (d) => Directionality(textDirection: TextDirection.rtl, child: AlertDialog(
      title: Text(title),
      content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'نام جدید')),
      actions: [_horizontalDialogActions([TextButton(onPressed: () => Navigator.pop(d), child: const Text('انصراف')), FilledButton(onPressed: () => Navigator.pop(d, controller.text.trim()), child: const Text('ذخیره'))])],
    )));
    controller.dispose();
    return value;
  }

  Future<void> _manageProductGroups() async {
    final groupController = TextEditingController();
    final subController = TextEditingController();
    String? selectedGroup = AppSettings.productGroups.keys.isEmpty ? null : AppSettings.productGroups.keys.first;
    await showDialog<void>(context: context, builder: (dialogContext) => Directionality(
      textDirection: TextDirection.rtl,
      child: StatefulBuilder(builder: (dialogContext, refresh) => AlertDialog(
        title: const Text('مدیریت گروه‌ها و زیرگروه‌ها'),
        content: SizedBox(width: 380, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: groupController, decoration: const InputDecoration(labelText: 'نام گروه اصلی جدید')),
          Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () async {
            final name = groupController.text.trim();
            if (name.isEmpty || AppSettings.productGroups.containsKey(name)) return;
            AppSettings.productGroups[name] = [];
            await AppSettings.saveProductGroups();
            groupController.clear();
            refresh(() => selectedGroup = name);
          }, icon: const Icon(Icons.add), label: const Text('افزودن گروه'))),
          const Divider(),
          DropdownButtonFormField<String>(value: selectedGroup, isExpanded: true, decoration: const InputDecoration(labelText: 'انتخاب گروه'), items: AppSettings.productGroups.keys.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(), onChanged: (v) => refresh(() => selectedGroup = v)),
          const SizedBox(height: 8),
          TextField(controller: subController, decoration: const InputDecoration(labelText: 'نام زیرگروه جدید')),
          Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () async {
            final name = subController.text.trim();
            if (selectedGroup == null || name.isEmpty || (AppSettings.productGroups[selectedGroup] ?? []).contains(name)) return;
            AppSettings.productGroups[selectedGroup]!.add(name);
            await AppSettings.saveProductGroups();
            subController.clear();
            refresh(() {});
          }, icon: const Icon(Icons.add), label: const Text('افزودن زیرگروه'))),
          for (final sub in (selectedGroup == null ? <String>[] : AppSettings.productGroups[selectedGroup] ?? <String>[]))
            ListTile(dense: true, title: Text(sub), trailing: Wrap(children: [
              IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'ویرایش زیرگروه', onPressed: () async {
                final renamed = await _askGroupRename('ویرایش زیرگروه', sub);
                if (renamed == null || renamed.trim().isEmpty || renamed == sub || selectedGroup == null) return;
                final list = AppSettings.productGroups[selectedGroup]!;
                if (list.contains(renamed)) return;
                list[list.indexOf(sub)] = renamed;
                await AppSettings.saveProductGroups(); refresh(() {});
              }),
              IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'حذف زیرگروه', onPressed: () async { AppSettings.productGroups[selectedGroup]!.remove(sub); await AppSettings.saveProductGroups(); refresh(() {}); }),
            ])),
          for (final group in AppSettings.productGroups.keys.toList())
            ListTile(dense: true, title: Text(group), trailing: Wrap(children: [
              IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'ویرایش گروه', onPressed: () async {
                final renamed = await _askGroupRename('ویرایش گروه اصلی', group);
                if (renamed == null || renamed.trim().isEmpty || renamed == group || AppSettings.productGroups.containsKey(renamed)) return;
                final subs = AppSettings.productGroups.remove(group)!;
                AppSettings.productGroups[renamed] = subs;
                if (selectedGroup == group) selectedGroup = renamed;
                await AppSettings.saveProductGroups(); refresh(() {});
              }),
              IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'حذف گروه', onPressed: () async {
                final yes = await showDialog<bool>(context: dialogContext, builder: (d) => Directionality(textDirection: TextDirection.rtl, child: AlertDialog(
                  title: const Text('حذف گروه'),
                  content: Text('گروه «$group» و زیرگروه‌هایش حذف شوند؟ کالاهای قبلی همچنان با نام ثبت‌شده خود باقی می‌مانند.'),
                  actions: [_horizontalDialogActions([TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('انصراف')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('حذف'))])],
                )));
                if (yes != true) return;
                AppSettings.productGroups.remove(group);
                if (selectedGroup == group) selectedGroup = AppSettings.productGroups.keys.isEmpty ? null : AppSettings.productGroups.keys.first;
                await AppSettings.saveProductGroups(); refresh(() {});
              }),
            ])),
        ]))),
        actions: [_horizontalDialogActions([TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('بستن'))])],
      )),
    ));
    groupController.dispose(); subController.dispose();
    if (mounted) setState(() {});
  }

  Future<void> _recordSupplierPayment(String supplierName) async {
    final amount = TextEditingController();
    final note = TextEditingController();
    String paymentMethod = 'نقدی';
    final saved = await showDialog<bool>(context: context, builder: (d) => Directionality(
      textDirection: TextDirection.rtl,
      child: StatefulBuilder(builder: (d, refresh) => AlertDialog(
        title: const Text('ثبت پرداخت به فروشنده'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('فروشنده: ' + supplierName),
          TextField(controller: amount, keyboardType: TextInputType.number, inputFormatters: [PersianDigitsOnlyFormatter()], decoration: const InputDecoration(labelText: 'مبلغ پرداخت (تومان)')),
          DropdownButtonFormField<String>(
            value: paymentMethod,
            decoration: const InputDecoration(labelText: 'روش پرداخت'),
            items: const ['نقدی', 'چک', 'کارتی / حواله'].map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(),
            onChanged: (v) => refresh(() => paymentMethod = v ?? 'نقدی'),
          ),
          TextField(controller: note, decoration: const InputDecoration(labelText: 'توضیحات')),
        ]),
        actions: [_horizontalDialogActions([
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('انصراف')),
          FilledButton(onPressed: () {
            if (PartyAccounting.amount({'مبلغ': amount.text}, 'مبلغ') <= 0) {
              ScaffoldMessenger.of(d).showSnackBar(const SnackBar(content: Text('مبلغ معتبر وارد کنید.')));
              return;
            }
            Navigator.pop(d, true);
          }, child: const Text('ثبت پرداخت')),
        ])],
      )),
    ));
    if (saved == true) {
      await DemoStore.add('operations', {
        'نوع عملیات': 'پرداخت وجه',
        'نام شخص': supplierName,
        'مبلغ': PartyAccounting.amount({'مبلغ': amount.text}, 'مبلغ').toString(),
        'روش': paymentMethod,
        'تاریخ': Jalali.now().formatCompactDate(),
        'توضیحات': note.text.trim(),
      });
      if (mounted) setState(() {});
    }
    amount.dispose();
    note.dispose();
  }

  Future<void> _managePurchases() async {
    Future<void> editPurchase({Map<String, String>? existing, int? index}) async {
      final item = TextEditingController(text: existing?['کالا'] ?? '');
      final seller = TextEditingController(text: existing?['نام فروشنده'] ?? '');
      final mobile = TextEditingController(text: existing?['موبایل'] ?? '');
      final sellerAddress = TextEditingController(text: existing?['آدرس'] ?? '');
      final website = TextEditingController(text: existing?['آدرس سایت'] ?? '');
      final purchaseAmount = TextEditingController(text: existing?['مبلغ خرید'] ?? '');
      final purchaseQuantity = TextEditingController(text: existing?['تعداد خرید'] ?? '1');
      final paidAmount = TextEditingController(text: existing?['مبلغ پرداختی'] ?? '0');
      String paymentMethod = existing?['روش پرداخت'] ?? 'نقدی';
      final date = TextEditingController(text: existing?['تاریخ خرید'] ?? Jalali.now().formatCompactDate());
      final result = await showDialog<bool>(context: context, builder: (d) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(existing == null ? 'ثبت خرید کالا' : 'ویرایش خرید کالا'),
          content: SizedBox(width: 380, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: item, decoration: const InputDecoration(labelText: 'نام کالا')),
            const SizedBox(height: 8),
            TextField(controller: date, textDirection: TextDirection.ltr, keyboardType: TextInputType.datetime, inputFormatters: [PersianDateInputFormatter()], decoration: InputDecoration(labelText: 'تاریخ خرید (شمسی)', prefixIcon: IconButton(icon: const Icon(Icons.calendar_month), onPressed: () async {
              final picked = await showPersianDatePicker(context: d, initialDate: Jalali.now(), firstDate: Jalali(1300, 1, 1), lastDate: Jalali(1500, 12, 29));
              if (picked != null) date.text = picked.formatCompactDate();
            }))),
            const SizedBox(height: 8),
            TextField(controller: seller, decoration: const InputDecoration(labelText: 'نام فروشنده / شخصی که خرید از او انجام شد')),
            const SizedBox(height: 8),
            TextField(controller: purchaseQuantity, keyboardType: TextInputType.number, inputFormatters: [PersianDigitsOnlyFormatter()], decoration: const InputDecoration(labelText: 'تعداد خرید از این کالا')),
            const SizedBox(height: 8),
            TextField(controller: purchaseAmount, keyboardType: TextInputType.number, inputFormatters: [PersianDigitsOnlyFormatter()], decoration: const InputDecoration(labelText: 'مبلغ کل خرید (تومان)')),
            const SizedBox(height: 8),
            TextField(controller: paidAmount, keyboardType: TextInputType.number, inputFormatters: [PersianDigitsOnlyFormatter()], decoration: const InputDecoration(labelText: 'مبلغ پرداخت‌شده (تومان)')),
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('پرداخت ثبت‌شده در همین خرید از بدهی فروشنده کم می‌شود؛ همان پرداخت را دوباره از منوی پرداخت فروشنده ثبت نکن.', style: TextStyle(fontSize: 11, color: Colors.orange)),
            ),
            DropdownButtonFormField<String>(
              value: paymentMethod,
              decoration: const InputDecoration(labelText: 'روش پرداخت مبلغ پرداخت‌شده'),
              items: const ['نقدی','کارتی / حواله','چک'].map((v) => DropdownMenuItem(value:v,child:Text(v))).toList(),
              onChanged: (v) { paymentMethod = v ?? 'نقدی'; },
            ),
            const SizedBox(height: 8),
            TextField(controller: mobile, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'شماره موبایل')),
            const SizedBox(height: 8),
            TextField(controller: sellerAddress, maxLines: 2, decoration: const InputDecoration(labelText: 'آدرس فروشنده')),
            const SizedBox(height: 8),
            TextField(controller: website, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'آدرس سایت / وب‌سایت')),
          ]))),
          actions: [_horizontalDialogActions([
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('انصراف')),
            FilledButton(onPressed: () {
              final total = PartyAccounting.amount({'مبلغ': purchaseAmount.text}, 'مبلغ');
              final quantity = PartyAccounting.amount({'مبلغ': purchaseQuantity.text}, 'مبلغ');
              final paid = PartyAccounting.amount({'مبلغ': paidAmount.text}, 'مبلغ');
              if (item.text.trim().isEmpty || seller.text.trim().isEmpty || date.text.trim().isEmpty ||
                  total <= 0 || quantity <= 0 || paid > total) {
                ScaffoldMessenger.of(d).showSnackBar(const SnackBar(content: Text('نام کالا، تاریخ، فروشنده، تعداد و مبلغ معتبر را وارد کنید. مبلغ پرداختی نباید از کل خرید بیشتر باشد.')));
                return;
              }
              Navigator.pop(d, true);
            }, child: const Text('ذخیره')),
          ])],
        ),
      ));
      if (result == true) {
        final record = <String,String>{
          'شناسه سند': existing?['شناسه سند'] ?? DateTime.now().microsecondsSinceEpoch.toString(),
          'کالا': item.text.trim(), 'تاریخ خرید': date.text.trim(),
          'نام فروشنده': seller.text.trim(),
          'مبلغ خرید': PartyAccounting.amount({'مبلغ':purchaseAmount.text},'مبلغ').toString(),
          'تعداد خرید': PartyAccounting.amount({'مبلغ':purchaseQuantity.text},'مبلغ').toString(),
          'مبلغ پرداختی': PartyAccounting.amount({'مبلغ':paidAmount.text},'مبلغ').toString(),
          'روش پرداخت': paymentMethod,
          'موبایل': mobile.text.trim(), 'آدرس': sellerAddress.text.trim(), 'آدرس سایت': website.text.trim()
        };
        try {
          if (index == null) {
            AppSettings.purchaseRecords.add(record);
          } else {
            AppSettings.purchaseRecords[index] = record;
          }
          await AppSettings.savePurchaseRecords();
          await AccountingEngine.syncSupplierPurchase(record, previous: existing);
          if (existing != null && (existing['نام فروشنده'] ?? '').trim() != record['نام فروشنده']) {
            await DemoStore.renamePartyReferences(existing['نام فروشنده'] ?? '', record['نام فروشنده'] ?? '');
          }
          if (mounted) setState(() {});
        } catch(error) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ثبت خرید یا گردش حساب ناموفق بود: $error')));
        }
      }
      item.dispose(); seller.dispose(); mobile.dispose(); sellerAddress.dispose(); website.dispose(); purchaseAmount.dispose(); purchaseQuantity.dispose(); paidAmount.dispose(); date.dispose();
    }

    await showDialog<void>(context: context, builder: (d) => Directionality(
      textDirection: TextDirection.rtl,
      child: StatefulBuilder(builder: (d, refresh) => AlertDialog(
        title: const Text('مدیریت خرید کالاها و فروشندگان'),
        content: SizedBox(width: 400, child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 440),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Align(alignment: Alignment.centerRight, child: FilledButton.icon(onPressed: () async { await editPurchase(); refresh(() {}); }, icon: const Icon(Icons.add), label: const Text('ثبت خرید جدید'))),
            const Divider(),
            Expanded(child: AppSettings.purchaseRecords.isEmpty
              ? const Center(child: Text('هنوز خریدی ثبت نشده است.'))
              : ListView.builder(itemCount: AppSettings.purchaseRecords.length, itemBuilder: (context, i) {
                  final p = AppSettings.purchaseRecords[i];
                  return Card(child: ListTile(
                    title: Text(p['کالا'] ?? ''),
                    subtitle: Builder(builder: (context) {
                      final vendor = p['نام فروشنده'] ?? '';
                      final balance = PartyAccounting.balanceFor(vendor);
                      final status = balance < 0 ? 'بدهی به فروشنده' : balance > 0 ? 'طلب از فروشنده' : 'تسویه';
                      return Text('تاریخ: ${p['تاریخ خرید'] ?? ''} • فروشنده: $vendor\nمبلغ خرید: ${p['مبلغ خرید'] ?? '0'} تومان • ${status}: ${balance.abs()} تومان • موبایل: ${p['موبایل'] ?? ''}');
                    }),
                    isThreeLine: true,
                    trailing: PopupMenuButton<String>(onSelected: (v) async {
                      if (v == 'edit') { await editPurchase(existing: Map<String,String>.from(p), index: i); refresh(() {}); }
                      if (v == 'payment') { await _recordSupplierPayment(p['نام فروشنده'] ?? ''); refresh(() {}); }
                      if (v == 'delete') {
                        final yes = await showDialog<bool>(context: d, builder: (confirm) => Directionality(textDirection: TextDirection.rtl, child: AlertDialog(
                          title: const Text('حذف خرید'), content: const Text('این سابقه خرید حذف شود؟'),
                          actions: [_horizontalDialogActions([TextButton(onPressed: () => Navigator.pop(confirm, false), child: const Text('انصراف')), FilledButton(onPressed: () => Navigator.pop(confirm, true), child: const Text('حذف'))])],
                        )));
                        if (yes == true) {
                          await AccountingEngine.removeSupplierPurchase(p);
                          AppSettings.purchaseRecords.removeAt(i);
                          await AppSettings.savePurchaseRecords();
                          refresh(() {});
                        }
                      }
                    }, itemBuilder: (_) => const [PopupMenuItem(value: 'payment', child: Text('ثبت پرداخت به فروشنده')), PopupMenuItem(value: 'edit', child: Text('ویرایش')), PopupMenuItem(value: 'delete', child: Text('حذف'))]),
                  ));
                })),
          ]),
        )),
        actions: [_horizontalDialogActions([TextButton(onPressed: () => Navigator.pop(d), child: const Text('بستن'))])],
      )),
    ));
  }

  Future<void> _resetAppearance() async {
    final yes = await showDialog<bool>(context: context, builder: (d) => Directionality(textDirection: TextDirection.rtl, child: AlertDialog(
      title: const Text('بازگردانی تنظیمات ظاهری'),
      content: const Text('فقط قالب رنگی، اندازه نوشته‌ها و عکس منوی کناری به حالت پیش‌فرض برمی‌گردند. اطلاعات فروشگاه و داده‌ها حذف نمی‌شوند. ادامه می‌دهید؟'),
      actions: [_horizontalDialogActions([TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('انصراف')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('بازگردانی'))])],
    )));
    if (yes == true) { await AppSettings.resetAppearance(); if (mounted) setState(() { themeMode = 'روشن'; darkMode = false; fontScale = 1.0; drawerImage = ''; }); }
  }

  Future<bool> _saveSettingsInternal() async {
    if (!_hasUnsavedChanges()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('چیزی برای ثبت یا ذخیره وارد نشده است.')));
      return false;
    }
    if (phone.text.length > 11) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('شماره تماس حداکثر ۱۱ رقم باشد.')));
      return false;
    }
    if (postalCode.text.isNotEmpty && postalCode.text.length != 10) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('کد پستی باید دقیقاً ۱۰ رقم باشد.')));
      return false;
    }
    try {
      await AppSettings.save(
        newStoreName: storeName.text,
        newManagerName: managerName.text,
        newPhone: phone.text,
        newAddress: address.text,
        newPostalCode: postalCode.text,
        newDarkMode: darkMode,
        newThemeMode: themeMode,
        newDrawerImage: drawerImage,
        newFontScale: fontScale,
      );
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تنظیمات با موفقیت ذخیره شد')));
      return true;
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ذخیره تنظیمات ناموفق بود: $error')));
      return false;
    }
  }

  Future<void> saveSettings() async {
    await _saveSettingsInternal();
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('مشخصات فروشگاه', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(controller: storeName, decoration: const InputDecoration(labelText: 'نام فروشگاه')),
          const SizedBox(height: 10),
          TextField(controller: managerName, decoration: const InputDecoration(labelText: 'نام مدیر / صاحب فروشگاه')),
          const SizedBox(height: 10),
          TextField(controller: phone, keyboardType: TextInputType.phone, inputFormatters: [PersianDigitsOnlyFormatter(), LengthLimitingTextInputFormatter(11)], decoration: const InputDecoration(labelText: 'شماره تماس فروشگاه (حداکثر ۱۱ رقم)')),
          const SizedBox(height: 10),
          TextField(controller: address, maxLines: 2, decoration: const InputDecoration(labelText: 'آدرس فروشگاه')),
          const SizedBox(height: 10),
          TextField(controller: postalCode, keyboardType: TextInputType.number, inputFormatters: [PersianDigitsOnlyFormatter(), LengthLimitingTextInputFormatter(10)], decoration: const InputDecoration(labelText: 'کد پستی (دقیقاً ۱۰ رقم)')),
          const Divider(height: 32),
          const Text('تنظیمات ظاهری', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          DropdownButtonFormField<String>(
            value: themeMode,
            decoration: const InputDecoration(labelText: 'قالب رنگی برنامه'),
            items: const ['روشن', 'تیره', 'فیروزه‌ای و سرمه‌ای'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: (v) => setState(() { themeMode = v ?? 'روشن'; darkMode = themeMode == 'تیره'; }),
          ),
          const SizedBox(height: 14),
          const Text('اندازه نوشته‌ها'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              (0.82, 'ریز'),
              (0.92, 'کوچک'),
              (1.0, 'استاندارد'),
              (1.12, 'بزرگ'),
            ].map((option) => ChoiceChip(
              label: Text(option.$2, maxLines: 1, softWrap: false),
              selected: fontScale == option.$1,
              onSelected: (_) => setState(() => fontScale = option.$1),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            )).toList(),
          ),
          const Divider(height: 28),
          OutlinedButton.icon(onPressed: _manageProductGroups, icon: const Icon(Icons.category_outlined), label: const Text('مدیریت گروه‌ها و زیرگروه‌های کالا')),
          OutlinedButton.icon(onPressed: _managePurchases, icon: const Icon(Icons.shopping_cart_outlined), label: const Text('مدیریت خرید کالاها و فروشندگان')),
          OutlinedButton.icon(onPressed: _resetAppearance, icon: const Icon(Icons.restart_alt), label: const Text('بازگردانی تنظیمات ظاهری به پیش‌فرض')),
          const Divider(height: 28),
          const Text('عکس پروفایل فروشگاه', style: TextStyle(fontWeight: FontWeight.bold)),
          if (drawerImage.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Image.memory(base64Decode(drawerImage), height: 110, fit: BoxFit.contain)),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(onPressed: () async {
              final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70, maxWidth: 900, maxHeight: 900);
              if (x != null) { final bytes = await x.readAsBytes(); setState(() => drawerImage = base64Encode(bytes)); }
            }, icon: const Icon(Icons.photo_library), label: const Text('انتخاب عکس')),
            if (drawerImage.isNotEmpty) TextButton.icon(onPressed: () => setState(() => drawerImage = ''), icon: const Icon(Icons.delete), label: const Text('حذف عکس')),
          ]),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: saveSettings,
            icon: const Icon(Icons.save),
            label: const Text('ذخیره تنظیمات'),
          ),
          const SizedBox(height: 12),
          const Text(
            'مشخصات و تنظیمات این بخش روی همین گوشی ذخیره می‌شوند. در مرحله بعد می‌توان آن‌ها را به سربرگ فاکتور و نسخه پشتیبان متصل کرد.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      );
}


class OperationsPage extends StatefulWidget {
  final VoidCallback onChanged;
  const OperationsPage({super.key, required this.onChanged});
  @override
  State<OperationsPage> createState() => _OperationsPageState();
}

class _OperationsPageState extends State<OperationsPage> {
  static const options = ['ثبت هزینه', 'ثبت درآمد', 'تخفیف دادن', 'تخفیف گرفتن', 'متفرقه شخص بدهکار', 'متفرقه شخص بستانکار', 'پرداخت وجه', 'دریافت وجه'];
  final Set<String> _selected = {};

  Future<void> _deleteSelected() async {
    final items = DemoStore.operations.where((x) => _selected.contains(jsonEncode(x))).toList();
    if (items.isEmpty || !await _confirmDelete(context, items.length)) return;
    await DemoStore.delete('operations', items);
    if (mounted) setState(() => _selected.clear());
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: Column(children: [
      if (_selected.isNotEmpty) Material(color: Theme.of(context).colorScheme.secondaryContainer, child: Row(children: [
        Padding(padding: const EdgeInsets.all(12), child: Text('${_selected.length} مورد انتخاب شده')),
        const Spacer(),
        TextButton(onPressed: () => setState(() => _selected.clear()), child: const Text('لغو انتخاب')),
        TextButton.icon(onPressed: () => setState(() => _selected.addAll(DemoStore.operations.map((x) => jsonEncode(x)))), icon: const Icon(Icons.select_all), label: const Text('انتخاب همه')),
        IconButton(onPressed: _deleteSelected, icon: const Icon(Icons.delete, color: Colors.red)),
      ])),
      Expanded(child: ListView(padding: const EdgeInsets.all(12), children: [
      Card(child: ListTile(leading:const Icon(Icons.receipt_long),title:const Text('مدیریت چک‌ها'),subtitle:Text('${DemoStore.checks.length} چک ثبت شده'),trailing:const Icon(Icons.chevron_left),onTap:_manageChecks)),
      Card(child: ListTile(leading:const Icon(Icons.assignment_return),title:const Text('برگشت فروش'),subtitle:const Text('ثبت برگشت به مشتری و ورود کالا به انبار'),trailing:const Icon(Icons.chevron_left),onTap:()=>_manageReturns('برگشت فروش'))),
      Card(child: ListTile(leading:const Icon(Icons.keyboard_return),title:const Text('برگشت خرید'),subtitle:const Text('ثبت برگشت به فروشنده و خروج کالا از انبار'),trailing:const Icon(Icons.chevron_left),onTap:()=>_manageReturns('برگشت خرید'))),
      Card(child: ListTile(leading:const Icon(Icons.menu_book_outlined),title:const Text('دفتر کل و تراز آزمایشی'),subtitle:const Text('مشاهده اسناد دوطرفه و جمع بدهکار و بستانکار'),trailing:const Icon(Icons.chevron_left),onTap:()=>_showGeneralLedger('دفتر کل',DemoStore.journalEntries))),
      Card(child: ListTile(leading:const Icon(Icons.inventory_outlined),title:const Text('کاردکس و گردش انبار'),subtitle:Text('${DemoStore.stockMovements.length} گردش ثبت شده'),trailing:const Icon(Icons.chevron_left),onTap:()=>_showGeneralLedger('کاردکس کالا',DemoStore.stockMovements))),
      for (final op in options)
        Card(child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.account_balance_wallet_outlined)),
          title: Text(op),
          trailing: const Icon(Icons.chevron_left),
          onTap: () => _openOperation(context, op),
        )),
      const Divider(),
      for (final item in DemoStore.operations.reversed)
        Card(child: ListTile(
          title: Text(item['نوع عملیات'] ?? 'عملیات مالی'),
          subtitle: Text('${item['نام شخص'] ?? ''} • ${item['مبلغ'] ?? '0'} تومان • ${item['روش'] ?? ''}'),
          leading: _selected.contains(jsonEncode(item)) ? const Icon(Icons.check_circle, color: Colors.teal) : const Icon(Icons.account_balance_wallet_outlined),
          onLongPress: () => setState(() => _selected.add(jsonEncode(item))),
          onTap: () { if (_selected.isNotEmpty) setState(() { final k=jsonEncode(item); _selected.contains(k) ? _selected.remove(k) : _selected.add(k); }); else _openOperation(context, item['نوع عملیات'] ?? options.first, existing: item); },
          trailing: _selected.isNotEmpty ? Checkbox(value: _selected.contains(jsonEncode(item)), onChanged: (_) => setState(() { final k=jsonEncode(item); _selected.contains(k) ? _selected.remove(k) : _selected.add(k); })) : const Icon(Icons.edit_outlined),
        )),
    ])),
  ]));

  Future<void> _manageChecks() async {
    Future<void> editCheck({Map<String,String>? existing}) async {
      final person = TextEditingController(text: existing?['نام شخص'] ?? '');
      final amount = TextEditingController(text: existing?['مبلغ'] ?? '');
      final number = TextEditingController(text: existing?['شماره چک'] ?? '');
      final bank = TextEditingController(text: existing?['بانک'] ?? '');
      final issued = TextEditingController(text: existing?['تاریخ ثبت'] ?? Jalali.now().formatCompactDate());
      final due = TextEditingController(text: existing?['تاریخ سررسید'] ?? Jalali.now().formatCompactDate());
      final note = TextEditingController(text: existing?['توضیحات'] ?? '');
      String kind = existing?['نوع چک'] ?? 'دریافتی';
      String status = existing?['وضعیت'] ?? 'پاس نشده';
      String affectBalance = existing?['اثر در مانده حساب'] ?? 'خیر - در فاکتور یا عملیات ثبت شده';
      final result = await showDialog<bool>(context: context, builder: (d) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(builder: (d, refresh) => AlertDialog(
          title: Text(existing == null ? 'ثبت چک جدید' : 'ویرایش چک'),
          content: SizedBox(width: 400, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: kind,
              decoration: const InputDecoration(labelText: 'نوع چک'),
              items: const ['دریافتی','پرداختی'].map((v) => DropdownMenuItem(value:v,child:Text(v))).toList(),
              onChanged: (v) => refresh(() => kind = v ?? 'دریافتی'),
            ),
            TextField(controller: person, decoration: const InputDecoration(labelText: 'نام مشتری یا فروشنده')),
            TextField(controller: amount, keyboardType: TextInputType.number, inputFormatters: [PersianDigitsOnlyFormatter()], decoration: const InputDecoration(labelText: 'مبلغ چک (تومان)')),
            TextField(controller: number, decoration: const InputDecoration(labelText: 'شماره چک')),
            TextField(controller: bank, decoration: const InputDecoration(labelText: 'بانک')),
            TextField(controller: issued, readOnly: true, onTap: () async {
              final picked = await showPersianDatePicker(context: d, initialDate: Jalali.now(), firstDate: Jalali(1300,1,1), lastDate: Jalali(1500,12,29));
              if (picked != null) issued.text = picked.formatCompactDate();
            }, decoration: const InputDecoration(labelText: 'تاریخ ثبت', suffixIcon: Icon(Icons.calendar_month))),
            TextField(controller: due, readOnly: true, onTap: () async {
              final picked = await showPersianDatePicker(context: d, initialDate: Jalali.now(), firstDate: Jalali(1300,1,1), lastDate: Jalali(1500,12,29));
              if (picked != null) due.text = picked.formatCompactDate();
            }, decoration: const InputDecoration(labelText: 'تاریخ سررسید', suffixIcon: Icon(Icons.event))),
            DropdownButtonFormField<String>(
              value: affectBalance,
              decoration: const InputDecoration(labelText: 'اثر چک در مانده حساب شخص'),
              items: const ['خیر - در فاکتور یا عملیات ثبت شده','بله'].map((v) => DropdownMenuItem(value:v,child:Text(v))).toList(),
              onChanged: (v) => refresh(() => affectBalance = v ?? 'بله'),
            ),
            DropdownButtonFormField<String>(
              value: status,
              decoration: const InputDecoration(labelText: 'وضعیت چک'),
              items: const ['پاس نشده','پاس شده در بانک','پاس شده در صندوق','خرج شده','برگشتی','باطل شده'].map((v) => DropdownMenuItem(value:v,child:Text(v))).toList(),
              onChanged: (v) => refresh(() => status = v ?? 'پاس نشده'),
            ),
            TextField(controller: note, maxLines: 2, decoration: const InputDecoration(labelText: 'توضیحات')),
          ]))),
          actions: [_horizontalDialogActions([
            if (existing != null) TextButton(onPressed: () async {
              if (!await _confirmDelete(d,1)) return;
              await DemoStore.delete('checks',[existing]);
              if (d.mounted) Navigator.pop(d,true);
            }, child: const Text('حذف')),
            TextButton(onPressed: () => Navigator.pop(d,false), child: const Text('انصراف')),
            FilledButton(onPressed: () async {
              if (person.text.trim().isEmpty || PartyAccounting.amount({'مبلغ':amount.text},'مبلغ') <= 0 || due.text.trim().isEmpty) {
                ScaffoldMessenger.of(d).showSnackBar(const SnackBar(content: Text('نام شخص، مبلغ و تاریخ سررسید را وارد کنید.')));
                return;
              }
              final data = <String,String>{
                'نوع چک':kind, 'نام شخص':person.text.trim(),
                'مبلغ':PartyAccounting.amount({'مبلغ':amount.text},'مبلغ').toString(),
                'شماره چک':number.text.trim(), 'بانک':bank.text.trim(),
                'تاریخ ثبت':issued.text.trim(), 'تاریخ سررسید':due.text.trim(),
                'وضعیت':status, 'اثر در مانده حساب':affectBalance, 'توضیحات':note.text.trim(),
              };
              try {
                if (existing == null) await DemoStore.add('checks',data);
                else await DemoStore.update('checks',existing,data);
                if (d.mounted) Navigator.pop(d,true);
              } catch (error) {
                if (d.mounted) ScaffoldMessenger.of(d).showSnackBar(SnackBar(content: Text('ثبت چک ناموفق بود: $error')));
              }
            }, child: const Text('ذخیره چک')),
          ])],
        )),
      ));
      person.dispose(); amount.dispose(); number.dispose(); bank.dispose(); issued.dispose(); due.dispose(); note.dispose();
      if (result == true && mounted) { setState(() {}); widget.onChanged(); }
    }

    await showDialog<void>(context:context,builder:(d)=>Directionality(
      textDirection:TextDirection.rtl,
      child:StatefulBuilder(builder:(d,refresh){
        final sorted=[...DemoStore.checks]..sort((a,b)=>(a['تاریخ سررسید']??'').compareTo(b['تاریخ سررسید']??''));
        DateTime? parseDueDate(String raw) {
          final value = PartyAccounting._digits(raw);
          final match = RegExp(r'(\d{4})[/-](\d{1,2})[/-](\d{1,2})').firstMatch(value);
          if (match == null) return null;
          try {
            return Jalali(int.parse(match.group(1)!),int.parse(match.group(2)!),int.parse(match.group(3)!)).toDateTime();
          } catch (_) { return null; }
        }
        final today = DateTime.now();
        final dueSoon = sorted.where((check) {
          if (['پاس شده در بانک','پاس شده در صندوق','خرج شده','برگشتی','باطل شده'].contains(check['وضعیت'])) return false;
          final dueDate = parseDueDate(check['تاریخ سررسید'] ?? '');
          if (dueDate == null) return false;
          return dueDate.isBefore(today.add(const Duration(days: 2)));
        }).toList();
        return AlertDialog(
          title:const Text('مدیریت چک‌ها'),
          content:SizedBox(width:420,height:440,child:Column(children:[
            if (dueSoon.isNotEmpty)
              Card(color: Theme.of(d).colorScheme.errorContainer, child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('یادآوری چک‌های سررسید نزدیک یا گذشته', style: TextStyle(fontWeight: FontWeight.bold)),
                  for (final check in dueSoon.take(4))
                    Text('${check['نوع چک'] ?? ''} • ${check['نام شخص'] ?? ''} • ${check['مبلغ'] ?? '0'} تومان • ${check['تاریخ سررسید'] ?? ''}'),
                ]),
              )),
            Align(alignment:Alignment.centerRight,child:FilledButton.icon(onPressed:()async{await editCheck();refresh((){});},icon:const Icon(Icons.add),label:const Text('ثبت چک جدید'))),
            const Divider(),
            Expanded(child:sorted.isEmpty?const Center(child:Text('هنوز چکی ثبت نشده است.')):ListView.builder(
              itemCount:sorted.length,
              itemBuilder:(context,index){
                final item=sorted[index];
                final dueText=item['تاریخ سررسید']??'';
                final unpaid=(item['وضعیت']??'')=='پاس نشده';
                return Card(child:ListTile(
                  title:Text('${item['نوع چک']??''} • ${item['نام شخص']??''}'),
                  subtitle:Text('${item['مبلغ']??'0'} تومان • سررسید: $dueText • ${item['وضعیت']??''}'),
                  leading:Icon(unpaid?Icons.warning_amber_outlined:Icons.check_circle_outline,color:unpaid?Colors.orange:Colors.green),
                  onTap:()async{await editCheck(existing:Map<String,String>.from(item));refresh((){});},
                ));
              },
            )),
          ])),
          actions:[_horizontalDialogActions([TextButton(onPressed:()=>Navigator.pop(d),child:const Text('بستن'))])],
        );
      }),
    ));
  }

  Future<void> _manageReturns(String returnType) async {
    Future<void> editReturn({Map<String,String>? existing}) async {
      final person = TextEditingController(text: existing?['نام شخص'] ?? '');
      final product = TextEditingController(text: existing?['نام کالا'] ?? '');
      final quantity = TextEditingController(text: existing?['تعداد'] ?? '0');
      final amount = TextEditingController(text: existing?['مبلغ'] ?? '');
      final date = TextEditingController(text: existing?['تاریخ'] ?? Jalali.now().formatCompactDate());
      final description = TextEditingController(text: existing?['شرح'] ?? '');
      String? originReference = existing?['شناسه مرجع'];
      final originRecords = returnType == 'برگشت فروش'
          ? DemoStore.sales
          : AppSettings.purchaseRecords;
      String originId(Map<String,String> row, int index) =>
          row['شناسه سند'] ?? 'legacy-origin-$index';
      final result = await showDialog<bool>(context:context,builder:(d)=>Directionality(
        textDirection:TextDirection.rtl,
        child:AlertDialog(
          title:Text(existing==null?returnType:'ویرایش $returnType'),
          content:SizedBox(width:380,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
            TextField(controller:person,decoration:InputDecoration(labelText:returnType=='برگشت فروش'?'نام مشتری':'نام فروشنده')),
            DropdownButtonFormField<String>(
              value: DemoStore.products.any((x)=>(x['نام کالا']??'')==product.text.trim())?product.text.trim():null,
              isExpanded:true,
              decoration:const InputDecoration(labelText:'کالای مرتبط با انبار (اختیاری)'),
              items:DemoStore.products.map((x)=>DropdownMenuItem<String>(value:x['نام کالا']??'',child:Text(x['نام کالا']??''))).toList(),
              onChanged:(v){if(v!=null)product.text=v;},
            ),
            DropdownButtonFormField<String>(
              value: originRecords.asMap().entries.any((entry) => originId(entry.value,entry.key) == originReference) ? originReference : null,
              isExpanded:true,
              decoration: InputDecoration(labelText:returnType=='برگشت فروش'?'فاکتور فروش مرجع (برای بهای تمام‌شده دقیق)':'خرید مرجع از فروشنده (برای بهای خرید دقیق)'),
              items: originRecords.asMap().entries.map((entry) {
                final row=entry.value;
                final id=originId(row,entry.key);
                final partyName=returnType=='برگشت فروش'?(row['نام مشتری']??''):(row['نام فروشنده']??'');
                final itemName=returnType=='برگشت فروش'?(row['نام کالا (از انبار)']??row['شرح کالا/خدمت']??''):(row['کالا']??'');
                return DropdownMenuItem<String>(value:id,child:Text('$partyName • $itemName',overflow:TextOverflow.ellipsis));
              }).toList(),
              onChanged:(v){
                originReference=v;
                if(v!=null){
                  for(final entry in originRecords.asMap().entries){
                    if(originId(entry.value,entry.key)==v){
                      final row=entry.value;
                      if(returnType=='برگشت فروش'){
                        person.text=row['نام مشتری']??person.text;
                        if((row['نام کالا (از انبار)']??'').isNotEmpty)product.text=row['نام کالا (از انبار)']!;
                      }else{
                        person.text=row['نام فروشنده']??person.text;
                        product.text=row['کالا']??product.text;
                      }
                      break;
                    }
                  }
                }
              },
            ),
            TextField(controller:quantity,keyboardType:TextInputType.number,inputFormatters:[PersianDigitsOnlyFormatter()],decoration:const InputDecoration(labelText:'تعداد برگشتی از انبار (برای برگشت خدمات صفر)')),
            TextField(controller:amount,keyboardType:TextInputType.number,inputFormatters:[PersianDigitsOnlyFormatter()],decoration:const InputDecoration(labelText:'مبلغ برگشت (تومان)')),
            TextField(controller:date,readOnly:true,onTap:()async{
              final picked=await showPersianDatePicker(context:d,initialDate:Jalali.now(),firstDate:Jalali(1300,1,1),lastDate:Jalali(1500,12,29));
              if(picked!=null)date.text=picked.formatCompactDate();
            },decoration:const InputDecoration(labelText:'تاریخ برگشت',suffixIcon:Icon(Icons.calendar_month))),
            TextField(controller:description,maxLines:2,decoration:const InputDecoration(labelText:'شرح / علت برگشت')),
          ]))),
          actions:[_horizontalDialogActions([
            if(existing!=null)TextButton(onPressed:()async{if(!await _confirmDelete(d,1))return;await DemoStore.delete('returns',[existing]);if(d.mounted)Navigator.pop(d,true);},child:const Text('حذف')),
            TextButton(onPressed:()=>Navigator.pop(d,false),child:const Text('انصراف')),
            FilledButton(onPressed:()async{
              if(person.text.trim().isEmpty || PartyAccounting.amount({'مبلغ':amount.text},'مبلغ')<=0){
                ScaffoldMessenger.of(d).showSnackBar(const SnackBar(content:Text('نام شخص و مبلغ برگشت را وارد کنید.')));return;
              }
              final data=<String,String>{
                'نوع برگشت':returnType,'نام شخص':person.text.trim(),'نام کالا':product.text.trim(),
                'تعداد':PartyAccounting._digits(quantity.text).replaceAll(RegExp(r'[^0-9.]'),''),
                'مبلغ':PartyAccounting.amount({'مبلغ':amount.text},'مبلغ').toString(),
                'شناسه مرجع':originReference??'',
                'بهای تمام‌شده هر واحد': (() {
                  if(originReference==null) return '';
                  for(final entry in originRecords.asMap().entries){
                    if(originId(entry.value,entry.key)==originReference){
                      final row=entry.value;
                      if(returnType=='برگشت فروش') return row['بهای تمام‌شده هر واحد']??'';
                      final q=PartyAccounting.amount(row,'تعداد خرید');
                      final v=PartyAccounting.amount(row,'مبلغ خرید');
                      return q>0?(v/q).toStringAsFixed(0):'';
                    }
                  }
                  return '';
                })(),
                'تاریخ':date.text.trim(),'شرح':description.text.trim(),
              };
              try{
                if(existing==null)await DemoStore.add('returns',data);else await DemoStore.update('returns',existing,data);
                if(d.mounted)Navigator.pop(d,true);
              }catch(error){if(d.mounted)ScaffoldMessenger.of(d).showSnackBar(SnackBar(content:Text('ثبت برگشت ناموفق بود: $error')));}
            },child:const Text('ثبت برگشت')),
          ])],
        ),
      ));
      person.dispose();product.dispose();quantity.dispose();amount.dispose();date.dispose();description.dispose();
      if(result==true&&mounted){setState((){});widget.onChanged();}
    }

    await showDialog<void>(context:context,builder:(d)=>Directionality(
      textDirection:TextDirection.rtl,
      child:StatefulBuilder(builder:(d,refresh){
        final items=DemoStore.returns.where((x)=>x['نوع برگشت']==returnType).toList().reversed.toList();
        return AlertDialog(
          title:Text(returnType),
          content:SizedBox(width:420,height:420,child:Column(children:[
            Align(alignment:Alignment.centerRight,child:FilledButton.icon(onPressed:()async{await editReturn();refresh((){});},icon:const Icon(Icons.add),label:const Text('ثبت سند برگشت'))),
            const Divider(),
            Expanded(child:items.isEmpty?const Center(child:Text('سندی ثبت نشده است.')):ListView.builder(itemCount:items.length,itemBuilder:(context,index){
              final item=items[index];
              return Card(child:ListTile(
                title:Text('${item['نام شخص']??''} • ${item['نام کالا']??'خدمت / غیرانبار'}'),
                subtitle:Text('${item['مبلغ']??'0'} تومان • تعداد: ${item['تعداد']??'0'} • ${item['تاریخ']??''}'),
                onTap:()async{await editReturn(existing:Map<String,String>.from(item));refresh((){});},
              ));
            })),
          ])),
          actions:[_horizontalDialogActions([TextButton(onPressed:()=>Navigator.pop(d),child:const Text('بستن'))])],
        );
      }),
    ));
  }

  Future<void> _showGeneralLedger(String title, List<Map<String,String>> rows) async {
    await showDialog<void>(context:context,builder:(d)=>Directionality(
      textDirection:TextDirection.rtl,
      child:AlertDialog(
        title:Text(title),
        content:SizedBox(width:440,height:440,child:rows.isEmpty?const Center(child:Text('هنوز سندی در دفتر ثبت نشده است.')):ListView.builder(
          itemCount:rows.length,
          itemBuilder:(context,index){
            final row=rows[rows.length-1-index];
            return ListTile(
              dense:true,
              title:Text(row['نام حساب']??row['شرح سند']??row['نوع گردش']??'سند'),
              subtitle:Text('${row['تاریخ']??''} • ${row['شرح سند']??row['شرح']??''}'),
              trailing:Column(mainAxisAlignment:MainAxisAlignment.center,crossAxisAlignment:CrossAxisAlignment.end,children:[
                Text('بدهکار ${PartyAccounting.formatMoney(PartyAccounting.amount(row,'بدهکار'))}'),
                Text('بستانکار ${PartyAccounting.formatMoney(PartyAccounting.amount(row,'بستانکار'))}'),
              ]),
            );
          },
        )),
        actions:[_horizontalDialogActions([TextButton(onPressed:()=>Navigator.pop(d),child:const Text('بستن'))])],
      ),
    ));
  }

  Future<void> _openOperation(BuildContext context, String op, {Map<String,String>? existing}) async {
    final name = TextEditingController(text: existing?['نام شخص'] ?? '');
    final amount = TextEditingController(text: existing?['مبلغ'] ?? '');
    final note = TextEditingController(text: existing?['توضیحات'] ?? '');
    final initialName = name.text, initialAmount = amount.text, initialNote = note.text;
    String method = existing?['روش'] ?? 'نقدی';
    final initialMethod = method;
    final methods = ['نقدی', 'چک', 'کارتی / حواله', 'خرج چک'];

    bool dirty() => existing == null
        ? name.text.trim().isNotEmpty || amount.text.trim().isNotEmpty || note.text.trim().isNotEmpty || method != 'نقدی'
        : name.text.trim() != initialName || amount.text.trim() != initialAmount || note.text.trim() != initialNote || method != initialMethod;

    Future<void> requestClose(BuildContext dialogContext) async {
      if (!dirty()) { Navigator.pop(dialogContext, false); return; }
      final discard = await showDialog<bool>(context: dialogContext, builder: (d) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تغییرات ذخیره نشده‌اند'),
          content: const Text('اطلاعات این عملیات ذخیره نشده است. بدون ذخیره خارج می‌شوید؟'),
          actions: [_horizontalDialogActions([
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('ادامه ویرایش')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('خروج بدون ذخیره')),
          ])],
        ),
      ));
      if (discard == true && dialogContext.mounted) Navigator.pop(dialogContext, false);
    }

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope<Object?>(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) { if (!didPop) requestClose(dialogContext); },
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(builder: (dialogContext, set) => AlertDialog(
            title: Text(op),
            content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: InputDecoration(labelText: op == 'ثبت هزینه' || op == 'ثبت درآمد' ? 'عنوان هزینه یا درآمد' : 'نام شخص')),
              TextField(controller: amount, keyboardType: TextInputType.number, inputFormatters: [PersianDigitsOnlyFormatter()], decoration: const InputDecoration(labelText: 'مبلغ (تومان)')),
              if (op == 'پرداخت وجه' || op == 'دریافت وجه')
                const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('اگر همین مبلغ را در فاکتور، خرید یا پذیرش ثبت کرده‌ای، دوباره آن را ثبت نکن.', style: TextStyle(fontSize: 11, color: Colors.orange))),
              if (['پرداخت وجه','دریافت وجه','ثبت هزینه','ثبت درآمد'].contains(op))
                DropdownButtonFormField<String>(value: method, decoration: const InputDecoration(labelText: 'روش عملیات'), items: methods.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(), onChanged: (v) => set(() => method = v ?? 'نقدی')),
              TextField(controller: note, maxLines: 2, decoration: const InputDecoration(labelText: 'توضیحات')),
            ])),
            actions: [_horizontalDialogActions([
              if (existing != null) TextButton.icon(onPressed: () async {
                if (!await _confirmDelete(dialogContext, 1)) return;
                await DemoStore.delete('operations', [existing]);
                if (dialogContext.mounted) Navigator.pop(dialogContext, true);
              }, icon: const Icon(Icons.delete_outline), label: const Text('حذف')),
              TextButton(onPressed: () => requestClose(dialogContext), child: const Text('انصراف')),
              FilledButton(onPressed: () async {
                if (name.text.trim().isEmpty && amount.text.trim().isEmpty && note.text.trim().isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('چیزی برای ثبت یا ذخیره وارد نشده است.')));
                  return;
                }
                if (name.text.trim().isEmpty || amount.text.trim().isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('نام شخص و مبلغ را وارد کنید.')));
                  return;
                }
                final data = {'نوع عملیات': op, 'نام شخص': name.text.trim(), 'مبلغ': amount.text.trim(), 'روش': method, 'تاریخ': existing?['تاریخ'] ?? DateTime.now().toIso8601String(), 'توضیحات': note.text.trim()};
                try {
                  if (existing == null) await DemoStore.add('operations', data);
                  else await DemoStore.update('operations', existing, data);
                  if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                } catch (error) {
                  if (dialogContext.mounted) ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text('ذخیره عملیات ناموفق بود: $error')));
                }
              }, child: const Text('ثبت عملیات')),
            ])],
          )),
        ),
      ),
    );
    name.dispose(); amount.dispose(); note.dispose();
    if (result == true) widget.onChanged();
  }
}

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  final fromController = TextEditingController();
  final toController = TextEditingController();
  String selectedPeriod = 'همه تاریخ‌ها';
  String selectedCheckStatus = 'همه چک‌ها';
  bool saveFilterPermanently = false;

  @override
  void initState() {
    super.initState();
    _loadReportFilters();
  }

  Future<void> _loadReportFilters() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final enabled = prefs.getBool('reports_filter_saved') ?? false;
    setState(() {
      saveFilterPermanently = enabled;
      if (enabled) {
        fromController.text = prefs.getString('reports_filter_from') ?? '';
        toController.text = prefs.getString('reports_filter_to') ?? '';
        selectedPeriod = prefs.getString('reports_filter_period') ?? 'همه تاریخ‌ها';
        selectedCheckStatus = prefs.getString('reports_filter_check_status') ?? 'همه چک‌ها';
      }
    });
  }

  Future<void> _persistReportFilters() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('reports_filter_saved', saveFilterPermanently);
    if (saveFilterPermanently) {
      await prefs.setString('reports_filter_from', fromController.text);
      await prefs.setString('reports_filter_to', toController.text);
      await prefs.setString('reports_filter_period', selectedPeriod);
      await prefs.setString('reports_filter_check_status', selectedCheckStatus);
    } else {
      await prefs.remove('reports_filter_from');
      await prefs.remove('reports_filter_to');
      await prefs.remove('reports_filter_period');
      await prefs.remove('reports_filter_check_status');
    }
  }

  @override
  void dispose() {
    fromController.dispose();
    toController.dispose();
    super.dispose();
  }

  int _amount(Map<String, String> item, String key) => PartyAccounting.amount(item, key);

  String _money(int value) => value.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

  Future<void> _pickDate(TextEditingController controller) async {
    final picked = await showPersianDatePicker(
      context: context,
      initialDate: Jalali.now(),
      firstDate: Jalali(1300, 1, 1),
      lastDate: Jalali(1500, 12, 29),
      helpText: 'انتخاب تاریخ شمسی',
    );
    if (picked != null) {
      setState(() => controller.text = picked.formatCompactDate());
      if (saveFilterPermanently) await _persistReportFilters();
    }
  }


  DateTime? _parseReportDate(String raw) {
    if (raw.trim().isEmpty) return null;
    var value = raw.trim();
    const fa = '۰۱۲۳۴۵۶۷۸۹';
    for (var i = 0; i < 10; i++) {
      value = value.replaceAll(fa[i], '$i');
    }
    final match = RegExp(r'(\d{4})[/-](\d{1,2})[/-](\d{1,2})').firstMatch(value);
    if (match != null) {
      final year = int.parse(match.group(1)!);
      final month = int.parse(match.group(2)!);
      final day = int.parse(match.group(3)!);
      try {
        return year >= 1300 ? Jalali(year, month, day).toDateTime() : DateTime(year, month, day);
      } catch (_) { return null; }
    }
    return DateTime.tryParse(value)?.toLocal();
  }

  List<Map<String, String>> _applyDateFilter(List<Map<String, String>> source) {
    final start = _parseReportDate(fromController.text);
    final rawEnd = _parseReportDate(toController.text);
    final end = rawEnd == null ? null : DateTime(rawEnd.year, rawEnd.month, rawEnd.day, 23, 59, 59);
    if (start == null && end == null) return source;
    return source.where((row) {
      final raw = row['تاریخ'] ?? row['تاریخ فاکتور'] ?? row['تاریخ خرید'] ??
          row['تاریخ ثبت کالا'] ?? row['تاریخ پذیرش'] ?? row['تاریخ سررسید'] ?? '';
      final date = _parseReportDate(raw);
      if (date == null) return false;
      return (start == null || !date.isBefore(start)) && (end == null || !date.isAfter(end));
    }).toList();
  }

  Future<Uint8List> _renderReportPng(String title, List<Map<String,String>> rows, String amountKey) async {
    const width = 1200.0;
    const margin = 42.0;
    const rowHeight = 58.0;
    final height = (300 + rows.length * rowHeight).clamp(520, 12000).toDouble();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src);
    canvas.drawRect(const ui.Rect.fromLTWH(0, 0, width, 160), ui.Paint()..color = const ui.Color(0xFF238B50));

    void drawText(String value, double y, {double size = 27, ui.Color color = const ui.Color(0xFF202020), bool bold = false}) {
      final painter = TextPainter(
        text: TextSpan(text: value, style: TextStyle(fontSize: size, color: color, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
        textDirection: ui.TextDirection.rtl,
        maxLines: 2,
      )..layout(maxWidth: width - margin * 2);
      painter.paint(canvas, ui.Offset(width - margin - painter.width, y));
    }

    drawText(AppSettings.storeName, 28, size: 40, color: const ui.Color(0xFFFFFFFF), bold: true);
    drawText(title, 92, size: 32, color: const ui.Color(0xFFFFFFFF));
    drawText('تاریخ از: ' + (fromController.text.isEmpty ? 'ابتدا' : fromController.text) +
        '    تا: ' + (toController.text.isEmpty ? 'همه تاریخ‌ها' : toController.text), 190, size: 25);
    final total = rows.fold<int>(0, (sum, row) => sum + _amount(row, amountKey));
    drawText('تعداد موارد: ' + rows.length.toString() + '    جمع: ' + _money(total) + ' تومان', 235, size: 26, bold: true);

    var y = 305.0;
    for (final row in rows.take(180)) {
      final name = row['نام حساب'] ?? row['نام مشتری'] ?? row['نام شخص'] ?? row['نام کالا'] ?? row['کالا'] ??
          row['شرح کالا/خدمت'] ?? row['نوع عملیات'] ?? row['عنوان گزارش'] ?? 'بدون عنوان';
      final date = row['تاریخ'] ?? row['تاریخ فاکتور'] ?? row['تاریخ خرید'] ?? row['تاریخ ثبت کالا'] ?? '';
      final line = name + '    |    ' + date + '    |    ' + _money(_amount(row, amountKey)) + ' تومان';
      drawText(line, y, size: 24);
      canvas.drawLine(ui.Offset(margin, y + rowHeight - 8), ui.Offset(width - margin, y + rowHeight - 8),
          ui.Paint()..color = const ui.Color(0xFFE2E2E2)..strokeWidth = 1);
      y += rowHeight;
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    return data!.buffer.asUint8List();
  }

  Future<void> _exportReport(String title, List<Map<String,String>> rows, String amountKey, String type) async {
    try {
      final directory = await getTemporaryDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch.toString();
      if (type == 'اکسل') {
        final book = Excel.createExcel();
        final sheet = book['گزارش'];
        sheet.appendRow([
          TextCellValue('فروشگاه'), TextCellValue('عنوان گزارش'),
          TextCellValue('تاریخ'), TextCellValue('شرح'), TextCellValue('ماهیت'),
          TextCellValue('مبلغ'),
        ]);
        for (final row in rows) {
          final name = row['نام حساب'] ?? row['نام مشتری'] ?? row['نام شخص'] ?? row['نام کالا'] ?? row['کالا'] ??
              row['شرح کالا/خدمت'] ?? row['نوع عملیات'] ?? row['عنوان گزارش'] ?? '';
          final date = row['تاریخ'] ?? row['تاریخ فاکتور'] ?? row['تاریخ خرید'] ?? '';
          sheet.appendRow([
            TextCellValue(AppSettings.storeName),
            TextCellValue(title),
            TextCellValue(date),
            TextCellValue(name),
            TextCellValue(row['ماهیت'] ?? ''),
            IntCellValue(_amount(row, amountKey)),
          ]);
        }
        final bytes = book.encode();
        if (bytes == null) throw Exception('ساخت فایل اکسل ناموفق بود');
        final file = File(directory.path + '/report_' + stamp + '.xlsx');
        await file.writeAsBytes(bytes, flush: true);
        await Share.shareXFiles([XFile(file.path)], text: title);
        return;
      }

      final png = await _renderReportPng(title, rows, amountKey);
      if (type == 'عکس') {
        final file = File(directory.path + '/report_' + stamp + '.png');
        await file.writeAsBytes(png, flush: true);
        await Share.shareXFiles([XFile(file.path)], text: title);
      } else {
        final document = pw.Document();
        document.addPage(pw.Page(build: (_) => pw.Center(
          child: pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.contain),
        )));
        await Printing.sharePdf(bytes: await document.save(), filename: 'report_' + stamp + '.pdf');
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تهیه خروجی ناموفق بود: ' + error.toString())),
        );
      }
    }
  }

  Future<void> _showReport(String title, IconData icon, List<Map<String, String>> rows, String amountKey, String emptyMessage, {bool dateFilter = true}) async {
    final startDate = _parseReportDate(fromController.text);
    final endDate = _parseReportDate(toController.text);
    if (startDate != null && endDate != null && startDate.isAfter(endDate)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تاریخ شروع نباید بعد از تاریخ پایان باشد.')));
      return;
    }
    if (dateFilter) rows = _applyDateFilter(rows);
    final total = rows.fold<int>(0, (sum, item) => sum + _amount(item, amountKey));
    await showDialog<void>(
      context: context,
      builder: (d) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(children: [Icon(icon), const SizedBox(width: 8), Expanded(child: Text(title))]),
          content: SizedBox(
            width: 440,
            child: rows.isEmpty
                ? Text(emptyMessage)
                : Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('تعداد موارد: ${rows.length}'),
                    Text('جمع مبلغ ثبت‌شده: ${_money(total)} تومان', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const Divider(),
                    SizedBox(height: 300, child: ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (_, i) {
                        final item = rows[rows.length - 1 - i];
                        final name = item['نام حساب'] ?? item['نام مشتری'] ?? item['نام شخص'] ?? item['نام کالا'] ?? item['شرح کالا/خدمت'] ?? item['نوع عملیات'] ?? item['عنوان'] ?? 'ثبت بدون عنوان';
                        final date = item['تاریخ'] ?? item['تاریخ سررسید'] ?? item['تاریخ ثبت کالا'] ?? '';
                        final detail = item.containsKey('تعداد قبل')
                            ? 'تاریخ: $date • قبل: ${item['تعداد قبل']} • تغییر: ${item['تغییر تعداد']} • بعد: ${item['تعداد بعد']} • واحد: ${item['واحد'] ?? ''}'
                            : item.containsKey('بدهکار')
                                ? 'بدهکار: ${_money(_amount(item, 'بدهکار'))} • بستانکار: ${_money(_amount(item, 'بستانکار'))} • ماهیت مانده: ${item['ماهیت مانده'] ?? ''}'
                                : date;
                        return ListTile(dense: true, title: Text(name), subtitle: Text(detail), trailing: Text(_money(_amount(item, amountKey))));
                      },
                    )),
                  ]),
          ),
          actions: [Wrap(spacing: 4, runSpacing: 4, children: [
            TextButton(onPressed: () => _exportReport(title, rows, amountKey, 'عکس'), child: const Text('خروجی عکس')),
            TextButton(onPressed: () => _exportReport(title, rows, amountKey, 'اکسل'), child: const Text('خروجی اکسل')),
            TextButton(onPressed: () => _exportReport(title, rows, amountKey, 'PDF'), child: const Text('خروجی PDF')),
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('بستن')),
          ])],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final debtorRows = DemoStore.customers.map((customer) {
      final name = customer['نام مشتری'] ?? '';
      final balance = PartyAccounting.balanceFor(name);
      return <String, String>{'نام مشتری': name, 'مبلغ': balance.toString(), 'ماهیت': 'بدهکار'};
    }).where((row) => PartyAccounting.amount(row, 'مبلغ') > 0).toList();
    final productProfitRows = DemoStore.sales.where((sale) =>
      (sale['نام کالا (از انبار)'] ?? '').trim().isNotEmpty &&
      (sale['سود'] ?? '').trim().isNotEmpty).toList();

    final creditorRows = DemoStore.customers.map((customer) {
      final name = customer['نام مشتری'] ?? '';
      final balance = PartyAccounting.balanceFor(name);
      return <String, String>{'نام مشتری': name, 'مبلغ': (-balance).toString(), 'ماهیت': 'بستانکار'};
    }).where((row) => PartyAccounting.amount(row, 'مبلغ') > 0).toList();

    final filteredChecks = DemoStore.checks.where((check) {
      if (selectedCheckStatus == 'همه چک‌ها') return true;
      if (selectedCheckStatus == 'پاس شده') {
        return (check['وضعیت'] ?? '').startsWith('پاس شده');
      }
      return (check['وضعیت'] ?? 'پاس نشده') == selectedCheckStatus;
    }).toList();

    final reports = <({String title, IconData icon, int count, VoidCallback open})>[
      (title: 'مشتریان بدهکار', icon: Icons.person_search_outlined, count: debtorRows.length, open: () => _showReport('فهرست مشتریان بدهکار', Icons.person_search_outlined, debtorRows, 'مبلغ', 'مشتری بدهکاری وجود ندارد.', dateFilter: false)),
      (title: 'مشتریان بستانکار', icon: Icons.account_balance_wallet_outlined, count: creditorRows.length, open: () => _showReport('فهرست مشتریان بستانکار', Icons.account_balance_wallet_outlined, creditorRows, 'مبلغ', 'مشتری بستانکاری وجود ندارد.', dateFilter: false)),
      (title: 'فاکتور فروش', icon: Icons.receipt_long, count: DemoStore.sales.length, open: () => _showReport('فاکتور فروش', Icons.receipt_long, DemoStore.sales, 'مبلغ کل', 'هنوز فاکتور فروشی ثبت نشده است.')),
      (title: 'فاکتور خرید', icon: Icons.shopping_bag_outlined, count: AppSettings.purchaseRecords.length, open: () => _showReport('سوابق خرید ثبت‌شده', Icons.shopping_bag_outlined, AppSettings.purchaseRecords, 'مبلغ خرید', 'سابقه خریدی در تنظیمات ثبت نشده است.')),
      (title: 'برگشت فروش', icon: Icons.assignment_return, count: DemoStore.returns.where((x) => x['نوع برگشت'] == 'برگشت فروش').length, open: () => _showReport('برگشت فروش', Icons.assignment_return, DemoStore.returns.where((x) => x['نوع برگشت'] == 'برگشت فروش').toList(), 'مبلغ', 'سندی برای برگشت فروش ثبت نشده است.')),
      (title: 'برگشت خرید', icon: Icons.keyboard_return, count: DemoStore.returns.where((x) => x['نوع برگشت'] == 'برگشت خرید').length, open: () => _showReport('برگشت خرید', Icons.keyboard_return, DemoStore.returns.where((x) => x['نوع برگشت'] == 'برگشت خرید').toList(), 'مبلغ', 'سندی برای برگشت خرید ثبت نشده است.')),
      (title: 'فروش کالاها', icon: Icons.point_of_sale, count: DemoStore.sales.length, open: () => _showReport('فروش کالاها', Icons.point_of_sale, DemoStore.sales, 'مبلغ کل', 'اطلاعات فروش کالا موجود نیست.')),
      (title: 'سود کالاها', icon: Icons.trending_up, count: productProfitRows.length, open: () => _showReport('سود کالاها', Icons.trending_up, productProfitRows, 'سود', 'فاکتور کالای انبار با بهای تمام‌شده ثبت نشده است.')),
      (title: 'چک‌ها', icon: Icons.receipt, count: filteredChecks.length, open: () => _showReport('چک‌ها', Icons.receipt, filteredChecks, 'مبلغ', 'چکی با این وضعیت ثبت نشده است.')),
      (title: 'دفتر کل و تراز آزمایشی', icon: Icons.menu_book, count: DemoStore.journalEntries.length, open: () => _showReport('دفتر کل و تراز آزمایشی', Icons.menu_book, AccountingEngine.trialBalance().map((x) => {...x, 'مبلغ': x['مانده'] ?? '0'}).toList(), 'مبلغ', 'سندی برای دفتر کل ثبت نشده است.', dateFilter: false)),
      (title: 'هزینه‌ها', icon: Icons.trending_down, count: DemoStore.operations.where((x) => x['نوع عملیات'] == 'ثبت هزینه').length, open: () => _showReport('هزینه‌ها', Icons.trending_down, DemoStore.operations.where((x) => x['نوع عملیات'] == 'ثبت هزینه').toList(), 'مبلغ', 'هزینه مستقلی ثبت نشده است.')),
      (title: 'درآمدها', icon: Icons.trending_up, count: DemoStore.operations.where((x) => x['نوع عملیات'] == 'ثبت درآمد').length, open: () => _showReport('درآمدها', Icons.trending_up, DemoStore.operations.where((x) => x['نوع عملیات'] == 'ثبت درآمد').toList(), 'مبلغ', 'درآمد مستقلی ثبت نشده است.')),
      (title: 'لیست قیمت انبار', icon: Icons.inventory_2_outlined, count: DemoStore.products.length, open: () => _showReport('لیست قیمت انبار', Icons.inventory_2_outlined, DemoStore.products, 'قیمت فروش', 'کالایی در انبار ثبت نشده است.')),
      (title: 'کاردکس کالا', icon: Icons.history, count: DemoStore.stockMovements.length, open: () => _showReport('کاردکس کالا', Icons.history, DemoStore.stockMovements, 'ارزش گردش', 'گردش انباری ثبت نشده است.')),
      (title: 'ریز خرید', icon: Icons.shopping_cart_outlined, count: AppSettings.purchaseRecords.length, open: () => _showReport('ریز خرید', Icons.shopping_cart_outlined, AppSettings.purchaseRecords, 'مبلغ خرید', 'سابقه خریدی ثبت نشده است.')),
      (title: 'ریز فروش و سود', icon: Icons.analytics_outlined, count: productProfitRows.length, open: () => _showReport('ریز فروش و سود', Icons.analytics_outlined, productProfitRows, 'سود', 'فاکتور کالای انبار با بهای تمام‌شده ثبت نشده است.')),
      (title: 'پذیرش تعمیرات', icon: Icons.build_outlined, count: DemoStore.repairs.length, open: () => _showReport('پذیرش تعمیرات', Icons.build_outlined, DemoStore.repairs, 'اجرت', 'پذیرش تعمیری ثبت نشده است.')),
    ];

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('بازه زمانی گزارش', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: fromController, readOnly: true, onTap: () => _pickDate(fromController), decoration: const InputDecoration(labelText: 'تاریخ از', suffixIcon: Icon(Icons.calendar_month)))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: toController, readOnly: true, onTap: () => _pickDate(toController), decoration: const InputDecoration(labelText: 'تا تاریخ', suffixIcon: Icon(Icons.calendar_month)))),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              ChoiceChip(label: const Text('همه تاریخ‌ها'), selected: selectedPeriod == 'همه تاریخ‌ها', onSelected: (_) { setState(() { selectedPeriod = 'همه تاریخ‌ها'; fromController.clear(); toController.clear(); }); if (saveFilterPermanently) _persistReportFilters(); }),
              ChoiceChip(label: const Text('امروز'), selected: selectedPeriod == 'امروز', onSelected: (_) { setState(() { selectedPeriod = 'امروز'; final today = Jalali.now().formatCompactDate(); fromController.text = today; toController.text = today; }); if (saveFilterPermanently) _persistReportFilters(); }),
              ChoiceChip(label: const Text('این ماه'), selected: selectedPeriod == 'این ماه', onSelected: (_) { setState(() { final now = Jalali.now(); selectedPeriod = 'این ماه'; fromController.text = Jalali(now.year, now.month, 1).formatCompactDate(); toController.text = now.formatCompactDate(); }); if (saveFilterPermanently) _persistReportFilters(); }),
              ChoiceChip(label: const Text('امسال'), selected: selectedPeriod == 'امسال', onSelected: (_) { setState(() { final now = Jalali.now(); selectedPeriod = 'امسال'; fromController.text = Jalali(now.year, 1, 1).formatCompactDate(); toController.text = now.formatCompactDate(); }); if (saveFilterPermanently) _persistReportFilters(); }),
            ]),
            Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () { fromController.clear(); toController.clear(); setState(() => selectedPeriod = 'همه تاریخ‌ها'); if (saveFilterPermanently) _persistReportFilters(); }, icon: const Icon(Icons.clear), label: const Text('پاک کردن فیلتر تاریخ'))),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('ذخیره دائمی فیلترهای گزارش'),
              subtitle: const Text('بازه تاریخ و وضعیت چک برای ورود بعدی حفظ شود'),
              value: saveFilterPermanently,
              onChanged: (value) {
                setState(() => saveFilterPermanently = value);
                _persistReportFilters();
              },
            ),
            DropdownButtonFormField<String>(
              value: selectedCheckStatus,
              decoration: const InputDecoration(labelText: 'فیلتر وضعیت چک‌ها'),
              items: const ['همه چک‌ها','پاس نشده','پاس شده','پاس شده در بانک','پاس شده در صندوق','خرج شده','برگشتی','باطل شده']
                  .map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
              onChanged: (value) { setState(() => selectedCheckStatus = value ?? 'همه چک‌ها'); if (saveFilterPermanently) _persistReportFilters(); },
            ),
          ]),
        )),
        const Padding(padding: EdgeInsets.fromLTRB(4, 12, 4, 8), child: Text('گزارش‌ها و صورت‌حساب‌ها', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold))),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: reports.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.25),
          itemBuilder: (context, index) {
            final report = reports[index];
            return Card(clipBehavior: Clip.antiAlias, child: InkWell(
              onTap: report.open,
              child: Padding(padding: const EdgeInsets.all(10), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(report.icon, size: 34, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 8),
                Text(report.title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('${report.count} مورد', style: Theme.of(context).textTheme.bodySmall),
              ])),
            ));
          },
        ),
        const Padding(padding: EdgeInsets.all(8), child: Text('فیلتر بازه در این مرحله برای انتخاب تاریخ آماده است؛ اعمال دقیق بازه روی همه گزارش‌ها و محاسبه سود، برگشت‌ها و کاردکس پس از تکمیل ثبت تراکنش‌های مربوط انجام می‌شود.', style: TextStyle(color: Colors.orange))),
      ],
    );
  }
}
), '');
    await DemoStore.updateRaw('products', product, changed);
  }

  static Future<void> _addMovement({
    required String reference,
    required String type,
    required Map<String,String> product,
    required double delta,
    required double before,
    required double after,
    required String date,
    required String note,
    double unitCost = 0,
  }) async {
    await DemoStore.add('stockMovements', {
      'مرجع سند': reference,
      'نوع گردش': type,
      'نام کالا': product['نام کالا'] ?? '',
      'کد کالا': product['کد کالا'] ?? '',
      'واحد': product['واحد شمارش'] ?? 'عدد',
      'تغییر تعداد': delta.toString(),
      'تعداد قبل': before.toString(),
      'تعداد بعد': after.toString(),
      'بهای واحد': unitCost.toStringAsFixed(0),
      'ارزش گردش': (delta.abs() * unitCost).toStringAsFixed(0),
      'تاریخ': date,
      'شرح': note,
    });
  }

  static Future<void> _reverseMovements(String reference) async {
    final old = DemoStore.stockMovements.where((x) => x['مرجع سند'] == reference).toList();
    for (final movement in old) {
      final product = _product(movement['نام کالا'] ?? '');
      if (product != null) {
        final delta = _qty(movement, 'تغییر تعداد');
        final movementValue = _qty(movement, 'ارزش گردش');
        final currentQty = _qty(product, 'موجودی');
        final currentCost = _qty(product, 'بهای تمام‌شده هر واحد');
        final currentValue = currentQty * currentCost;
        final nextQty = currentQty - delta;
        final nextValue = delta >= 0 ? currentValue - movementValue : currentValue + movementValue;
        final nextCost = nextQty > 0 ? (nextValue / nextQty).clamp(0, 1e15) : currentCost;
        final changed = Map<String,String>.from(product)
          ..['موجودی'] = nextQty.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+

  static Future<void> _postJournal(String reference, String date, String description,
      List<Map<String,String>> lines) async {
    final debit = lines.fold<int>(0, (sum, x) => sum + PartyAccounting.amount(x, 'بدهکار'));
    final credit = lines.fold<int>(0, (sum, x) => sum + PartyAccounting.amount(x, 'بستانکار'));
    if (debit != credit) {
      throw StateError('سند حسابداری تراز نیست. بدهکار: $debit، بستانکار: $credit');
    }
    final entries = <Map<String,String>>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final value = PartyAccounting.amount(line, 'بدهکار') + PartyAccounting.amount(line, 'بستانکار');
      if (value == 0) continue;
      entries.add({
        'شناسه سند': reference + ':' + (i + 1).toString(),
        'مرجع سند': reference,
        'ردیف': (i + 1).toString(),
        'تاریخ': date,
        'شرح سند': description,
        'کد حساب': line['کد حساب'] ?? '',
        'نام حساب': line['نام حساب'] ?? '',
        'نام شخص': line['نام شخص'] ?? '',
        'بدهکار': PartyAccounting.amount(line, 'بدهکار').toString(),
        'بستانکار': PartyAccounting.amount(line, 'بستانکار').toString(),
      });
    }
    await DemoStore.replaceJournalEntries(reference, entries);
  }

  static Map<String,String> _line(String account, int debit, int credit,
      {String code = '', String party = ''}) => {
    'کد حساب': code,
    'نام حساب': account,
    'نام شخص': party,
    'بدهکار': debit.toString(),
    'بستانکار': credit.toString(),
  };


  static Future<void> syncSupplierPurchase(Map<String,String> item,
      {Map<String,String>? previous}) async {
    final id = _reference('purchase', item);
    if (previous != null) {
      await _reverseMovements(_reference('purchase', previous));
      final oldJournal = DemoStore.journalEntries.where((x) => x['مرجع سند'] == _reference('purchase', previous)).toList();
      if (oldJournal.isNotEmpty) await DemoStore.delete('journalEntries', oldJournal);
    }
    final total = PartyAccounting.amount(item, 'مبلغ خرید');
    final paid = PartyAccounting.amount(item, 'مبلغ پرداختی').clamp(0, total).toInt();
    final payable = total - paid;
    var product = _product(item['کالا'] ?? '');
    final quantity = _qty(item, 'تعداد خرید') <= 0 ? 1.0 : _qty(item, 'تعداد خرید');
    final lines = <Map<String,String>>[];
    if (product != null && total > 0 && quantity > 0) {
      final before = _qty(product, 'موجودی');
      final oldCost = _qty(product, 'بهای تمام‌شده هر واحد') > 0
          ? _qty(product, 'بهای تمام‌شده هر واحد')
          : _qty(product, 'قیمت خرید هر واحد');
      final nextQty = before + quantity;
      final incomingUnitCost = total / quantity;
      final averageCost = nextQty > 0
          ? ((before * oldCost) + total) / nextQty
          : incomingUnitCost;
      final changed = Map<String,String>.from(product)
        ..['موجودی'] = nextQty.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+
    if (category == 'products') {
      final id = _reference(category, item);
      if (previous == null) {
        final product = _product(item['نام کالا'] ?? '');
        if (product != null) {
          final qty = _qty(product, 'موجودی');
          final cost = _qty(product, 'بهای تمام‌شده هر واحد');
          if (qty > 0) {
            await _addMovement(reference: id, type: 'ورود اولیه انبار', product: product,
                delta: qty, before: 0, after: qty,
                date: item['تاریخ ثبت کالا'] ?? Jalali.now().formatCompactDate(),
                note: 'موجودی اولیه هنگام ثبت کالا', unitCost: cost);
          }
          final openingValue = (qty * cost).round();
          if (openingValue > 0) {
            await _postJournal(id + ':opening', item['تاریخ ثبت کالا'] ?? Jalali.now().formatCompactDate(),
                'موجودی اولیه ' + (item['نام کالا'] ?? ''),
                [_line('موجودی کالا', openingValue, 0, code: '120'),
                 _line('سرمایه / مانده افتتاحیه', 0, openingValue, code: '300')]);
          }
        }
      } else {
        final oldQty = _qty(previous, 'موجودی');
        final newQty = _qty(item, 'موجودی');
        final delta = newQty - oldQty;
        if (delta != 0) {
          final product = _product(item['نام کالا'] ?? '');
          if (product != null) {
            final adjustmentRef = id + ':adjust:' + DateTime.now().microsecondsSinceEpoch.toString();
            final unitCost = _qty(item, 'بهای تمام‌شده هر واحد');
            await _addMovement(
              reference: adjustmentRef,
              type: 'اصلاح موجودی',
              product: product, delta: delta, before: oldQty, after: newQty,
              date: item['تاریخ ثبت کالا'] ?? Jalali.now().formatCompactDate(),
              note: 'اصلاح دستی موجودی', unitCost: unitCost);
            final value = (delta.abs() * unitCost).round();
            if (value > 0) {
              await _postJournal(adjustmentRef, item['تاریخ ثبت کالا'] ?? Jalali.now().formatCompactDate(),
                'اصلاح موجودی ' + (item['نام کالا'] ?? ''),
                delta > 0
                  ? [_line('موجودی کالا', value, 0, code: '120'), _line('تعدیلات موجودی', 0, value, code: '300')]
                  : [_line('کسری / ضایعات موجودی', value, 0, code: '520'), _line('موجودی کالا', 0, value, code: '120')]);
            }
          }
        }
      }
      return;
    }

    final reference = _reference(category, item);
    if (previous != null) {
      await _reverseMovements(reference);
    }

    if (category == 'sales') {
      final net = (PartyAccounting.amount(item, 'مبلغ کل') - PartyAccounting.amount(item, 'تخفیف')).clamp(0, 1 << 62).toInt();
      final received = PartyAccounting.amount(item, 'مبلغ دریافتی');
      final receivable = (net - received).clamp(0, 1 << 62).toInt();
      final customerCredit = (received - net).clamp(0, 1 << 62).toInt();
      final lines = <Map<String,String>>[];
      if (received > 0) { final method = item['روش پرداخت'] ?? 'نقدی'; final account = method == 'کارتی / حواله' ? 'بانک' : method == 'چک' ? 'اسناد دریافتنی' : 'صندوق'; lines.add(_line(account, received, 0, code: method == 'چک' ? '112' : '101')); }
      if (receivable > 0) lines.add(_line('حساب‌های دریافتنی - مشتریان', receivable, 0, code: '110', party: item['نام مشتری'] ?? ''));
      if (net > 0) lines.add(_line('درآمد فروش کالا و خدمات', 0, net, code: '401'));
      if (customerCredit > 0) lines.add(_line('اعتبار و پیش‌دریافت مشتریان', 0, customerCredit, code: '215', party: item['نام مشتری'] ?? ''));
      final cost = PartyAccounting.amount(item, 'بهای تمام‌شده کل');
      if (cost > 0) {
        lines.add(_line('بهای تمام‌شده کالای فروش‌رفته', cost, 0, code: '501'));
        lines.add(_line('موجودی کالا', 0, cost, code: '120'));
      }
      await _postJournal(reference, item['تاریخ فاکتور'] ?? Jalali.now().formatCompactDate(), 'فاکتور فروش ' + (item['نام مشتری'] ?? ''), lines);
      final productName = (item['نام کالا (از انبار)'] ?? '').trim();
      final product = _product(productName);
      final qty = _qty(item, 'تعداد');
      if (product != null && qty > 0) {
        final before = _qty(product, 'موجودی');
        final after = before - qty;
        if (after < -0.0001) throw StateError('موجودی کالا برای فروش کافی نیست.');
        await _setProductQuantity(product, after);
        await _addMovement(reference: reference, type: 'خروج بابت فروش', product: product,
          delta: -qty, before: before, after: after,
          date: item['تاریخ فاکتور'] ?? Jalali.now().formatCompactDate(),
          note: 'فروش به ' + (item['نام مشتری'] ?? ''),
          unitCost: _qty(item, 'بهای تمام‌شده هر واحد'));
      }
      return;
    }

    if (category == 'repairs') {
      final total = PartyAccounting.amount(item, 'اجرت');
      final received = PartyAccounting.amount(item, 'مبلغ دریافتی');
      final due = (total - received).clamp(0, 1 << 62).toInt();
      final customerCredit = (received - total).clamp(0, 1 << 62).toInt();
      final lines = <Map<String,String>>[];
      if (received > 0) lines.add(_line('صندوق', received, 0, code: '101'));
      if (due > 0) lines.add(_line('حساب‌های دریافتنی - مشتریان', due, 0, code: '110', party: item['نام مشتری'] ?? ''));
      if (total > 0) lines.add(_line('درآمد خدمات تعمیر', 0, total, code: '402'));
      if (customerCredit > 0) lines.add(_line('اعتبار و پیش‌دریافت مشتریان', 0, customerCredit, code: '215', party: item['نام مشتری'] ?? ''));
      final partName = (item['نام قطعه مصرفی از انبار'] ?? '').trim();
      final part = _product(partName);
      final partQty = _qty(item, 'تعداد قطعه مصرفی');
      if (part != null && partQty > 0) {
        final before = _qty(part, 'موجودی');
        final after = before - partQty;
        final unitCost = _qty(part, 'بهای تمام‌شده هر واحد') > 0 ? _qty(part, 'بهای تمام‌شده هر واحد') : _qty(part, 'قیمت خرید هر واحد');
        if (after < -0.0001) throw StateError('موجودی قطعه برای تعمیر کافی نیست.');
        await _setProductQuantity(part, after);
        await _addMovement(reference: reference, type: 'مصرف قطعه در تعمیر', product: part,
          delta: -partQty, before: before, after: after,
          date: item['تاریخ پذیرش'] ?? Jalali.now().formatCompactDate(),
          note: 'مصرف در تعمیر ' + (item['نوع دستگاه'] ?? ''), unitCost: unitCost);
        final cost = (partQty * unitCost).round();
        if (cost > 0) {
          lines.add(_line('بهای قطعات مصرفی تعمیر', cost, 0, code: '502'));
          lines.add(_line('موجودی کالا', 0, cost, code: '120'));
        }
      }
      await _postJournal(reference, item['تاریخ پذیرش'] ?? Jalali.now().formatCompactDate(), 'اجرت و قطعات تعمیر ' + (item['نوع دستگاه'] ?? ''), lines);
      return;
    }

    if (category == 'returns') {
      await _postReturn(item);
      return;
    }

    if (category == 'checks') {
      await _postCheck(item);
      return;
    }

    if (category == 'operations') {
      final type = item['نوع عملیات'] ?? '';
      final amount = PartyAccounting.amount(item, 'مبلغ');
      final party = item['نام شخص'] ?? '';
      final method = item['روش'] ?? 'نقدی';
      final cashAccount = method == 'کارتی / حواله' ? 'بانک' : method == 'چک' ? 'اسناد دریافتنی' : 'صندوق';
      List<Map<String,String>> lines = [];
      if (type == 'دریافت وجه') {
        lines = [_line(cashAccount, amount, 0, code: method == 'چک' ? '112' : '101'),
          _line('حساب‌های اشخاص', 0, amount, code: '110', party: party)];
      } else if (type == 'پرداخت وجه') {
        lines = [_line('حساب‌های اشخاص', amount, 0, code: '210', party: party),
          _line(method == 'کارتی / حواله' ? 'بانک' : method == 'چک' ? 'اسناد پرداختنی' : 'صندوق', 0, amount, code: method == 'چک' ? '212' : '101')];
      } else if (type == 'ثبت هزینه') {
        lines = [_line('هزینه: ' + (item['نام شخص'] ?? 'عمومی'), amount, 0, code: '520'),
          _line(method == 'کارتی / حواله' ? 'بانک' : method == 'چک' ? 'اسناد پرداختنی' : 'صندوق', 0, amount, code: method == 'کارتی / حواله' ? '102' : method == 'چک' ? '212' : '101')];
      } else if (type == 'ثبت درآمد') {
        lines = [_line(method == 'کارتی / حواله' ? 'بانک' : method == 'چک' ? 'اسناد دریافتنی' : 'صندوق', amount, 0, code: method == 'کارتی / حواله' ? '102' : method == 'چک' ? '112' : '101'),
          _line('درآمد: ' + (item['نام شخص'] ?? 'متفرقه'), 0, amount, code: '409')];
      } else if (type == 'متفرقه شخص بدهکار' || type == 'تخفیف گرفتن') {
        lines = [_line('حساب‌های دریافتنی - اشخاص', amount, 0, code: '110', party: party),
          _line('تعدیلات و مانده افتتاحیه', 0, amount, code: '300')];
      } else if (type == 'متفرقه شخص بستانکار' || type == 'تخفیف دادن') {
        lines = [_line('تعدیلات و مانده افتتاحیه', amount, 0, code: '300'),
          _line('حساب‌های پرداختنی - اشخاص', 0, amount, code: '210', party: party)];
      }
      await _postJournal(reference, item['تاریخ'] ?? Jalali.now().formatCompactDate(), type + ' ' + party, lines);
      return;
    }
  }

  static Future<void> removeDocument(String category, Map<String,String> item) async {
    if (!['sales','repairs','operations','products','returns','checks'].contains(category)) return;
    final reference = _reference(category, item);
    if (category == 'products') {
      final movements = DemoStore.stockMovements.where((x) => (x['کد کالا'] ?? '') == (item['کد کالا'] ?? '')).toList();
      if (movements.isNotEmpty) {
        throw StateError('برای این کالا گردش انبار ثبت شده است؛ ابتدا اسناد مرتبط را اصلاح کنید.');
      }
    }
    if (['sales','repairs','returns'].contains(category)) await _reverseMovements(reference);
    final journal = DemoStore.journalEntries.where((x) => x['مرجع سند'] == reference).toList();
    if (journal.isNotEmpty) await DemoStore.delete('journalEntries', journal);
  }

  static List<Map<String,String>> trialBalance() {
    final accounts = <String, Map<String,int>>{};
    for (final row in DemoStore.journalEntries) {
      final name = row['نام حساب'] ?? '';
      final entry = accounts.putIfAbsent(name, () => {'بدهکار': 0, 'بستانکار': 0});
      entry['بدهکار'] = (entry['بدهکار'] ?? 0) + PartyAccounting.amount(row, 'بدهکار');
      entry['بستانکار'] = (entry['بستانکار'] ?? 0) + PartyAccounting.amount(row, 'بستانکار');
    }
    return accounts.entries.map((entry) => <String,String>{
      'نام حساب': entry.key,
      'بدهکار': entry.value['بدهکار'].toString(),
      'بستانکار': entry.value['بستانکار'].toString(),
      'مانده': ((entry.value['بدهکار'] ?? 0) - (entry.value['بستانکار'] ?? 0)).abs().toString(),
      'ماهیت مانده': ((entry.value['بدهکار'] ?? 0) > (entry.value['بستانکار'] ?? 0)) ? 'بدهکار' : 'بستانکار',
    }).toList();
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  int tab = 0;
  final List<int> _tabHistory = [];
  final TextEditingController drawerSearchController = TextEditingController();
  final titles = const ['داشبورد', 'انبار کالا', 'مشتریان', 'تعمیرات', 'فروش و فاکتور', 'گزارش‌ها', 'تنظیمات برنامه', 'عملیات‌های دیگر'];

  @override
  void dispose() { drawerSearchController.dispose(); super.dispose(); }

  String _scopeForTab() => switch (tab) {
    1 => 'products', 2 => 'customers', 3 => 'repairs', 4 => 'sales', 5 => 'reports', 7 => 'operations', _ => 'all',
  };

  Future<bool> _confirmSettingsExit() async {
    if (tab != 6 || SettingsPage.isDirty?.call() != true) return true;
    final choice = await showDialog<String>(context: context, builder: (d) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('تغییرات ذخیره نشده‌اند'),
        content: const Text('در تنظیمات تغییراتی انجام داده‌اید. قبل از خروج چه کاری انجام شود؟'),
        actions: [_horizontalDialogActions([
          TextButton(onPressed: () => Navigator.pop(d, 'stay'), child: const Text('ادامه ویرایش')),
          TextButton(onPressed: () => Navigator.pop(d, 'discard'), child: const Text('خروج بدون ذخیره')),
          FilledButton(onPressed: () => Navigator.pop(d, 'save'), child: const Text('ذخیره و خروج')),
        ])],
      ),
    ));
    if (choice == 'save') return await SettingsPage.savePending?.call() ?? false;
    return choice == 'discard';
  }

  void _selectTab(int nextTab) async {
    if (nextTab < 0 || nextTab >= titles.length || nextTab == tab) return;
    if (!await _confirmSettingsExit()) return;
    setState(() {
      _tabHistory.add(tab);
      tab = nextTab;
    });
  }

  Future<void> _handleBack() async {
    if (scaffoldKey.currentState?.isDrawerOpen == true) {
      scaffoldKey.currentState?.closeDrawer();
      return;
    }

    if (!await _confirmSettingsExit()) return;

    if (_tabHistory.isNotEmpty) {
      setState(() {
        tab = _tabHistory.removeLast();
      });
      return;
    }

    if (tab != 0) {
      setState(() => tab = 0);
      return;
    }

    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('خروج از برنامه'),
          content: const Text('آیا می‌خواهید از برنامه خارج شوید؟'),
          actions: [_horizontalDialogActions([
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('ادامه کار'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('خروج'),
            ),
          ])],
        ),
      ),
    );

    if (!mounted) return;
    if (shouldExit == true) {
      await SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      Dashboard(onSelect: _selectTab),
      ProductPage(onChanged: () => setState(() {})),
      CustomerPage(onChanged: () => setState(() {})),
      RepairPage(onChanged: () => setState(() {})),
      SalesPage(onChanged: () => setState(() {})),
      const ReportsPage(),
      const SettingsPage(),
      OperationsPage(onChanged: () => setState(() {})),
    ];
    return Directionality(
      textDirection: TextDirection.rtl,
      child: PopScope<Object?>(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) {
            _handleBack();
          }
        },
        child: Scaffold(
          key: scaffoldKey,
          appBar: AppBar(
            title: Text(titles[tab]),
            actions: [
              if (tab == 1)
                PopupMenuButton<String>(
                  tooltip: 'تنظیم نمایش عکس کالا',
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) async {
                    AppSettings.productImageMode = value;
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('product_image_mode', value);
                    if (mounted) setState(() {});
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'عدم نمایش عکس کالا', child: Text('عدم نمایش عکس کالا')),
                    PopupMenuItem(value: 'پیش فرض عکس کالا', child: Text('پیش فرض عکس کالا')),
                    PopupMenuItem(value: 'کوچک کردن عکس کالا', child: Text('کوچک کردن عکس کالا')),
                  ],
                ),
              IconButton(tooltip: 'جست‌وجو', onPressed: () => _showScopedSearch(context, _scopeForTab()), icon: const Icon(Icons.search)),
            ],
          ),
          body: pages[tab],
          drawer: Drawer(
            child: ListView(
              children: [
                DrawerHeader(
                  decoration: const BoxDecoration(color: black),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: AppSettings.drawerImage.isNotEmpty
                            ? Image.memory(base64Decode(AppSettings.drawerImage), width: 68, height: 68, fit: BoxFit.cover)
                            : Image.asset('assets/logo.jpg', width: 68, height: 68, fit: BoxFit.cover),
                      ),
                      const SizedBox(height: 8),
                      Text(AppSettings.storeName, style: const TextStyle(color: yellow, fontSize: 22, fontWeight: FontWeight.bold)),
                      Text('نسخه آزمایشی', style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
                Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 12), child: TextField(
                  controller: drawerSearchController,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    labelText: 'جست‌وجو در کل برنامه',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: () => _showScopedSearch(context, 'all', initialQuery: drawerSearchController.text)),
                  ),
                  onSubmitted: (value) => _showScopedSearch(context, 'all', initialQuery: value),
                )),
                for (int i = 0; i < titles.length; i++)
                  ListTile(
                    leading: Icon([Icons.dashboard, Icons.inventory_2, Icons.people, Icons.build, Icons.receipt_long, Icons.bar_chart, Icons.settings, Icons.account_balance_wallet][i]),
                    title: Text(titles[i]),
                    selected: tab == i,
                    onTap: () {
                      _selectTab(i);
                      Navigator.pop(context);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
