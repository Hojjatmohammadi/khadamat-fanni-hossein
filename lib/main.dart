import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:persian_datetime_picker/persian_datetime_picker.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'data/app_database_schema.dart';
import 'accounting/accounting_engine.dart';

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
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static final revision = ValueNotifier<int>(0);
  static String storeName = 'خدمات فنی حسین';
  static String appName = 'خدمات فنی حسین';
  static String currency = 'تومان';
  static double vatPercent = 0;
  static double defaultDiscountPercent = 0;
  static String invoicePrefix = 'HOS';
  static int nextInvoiceNumber = 1;
  static bool pinEnabled = false;
  static String pinCode = '';
  static String managerName = '';
  static String phone = '';
  static String address = '';
  static String postalCode = '';
  static bool darkMode = false;
  static String themeMode = 'روشن';
  static String drawerImage = '';
  static double fontScale = 1.0;
  static String productImageMode = 'عکس پیش‌فرض';
  static Map<String, List<String>> productGroups = {
    'قطعات الکترونیکی': ['خازن‌ها', 'دیودها', 'آی‌سی‌ها', 'مقاومت‌ها', 'ترانزیستورها'],
    'قطعات مکانیکی': ['بلبرینگ', 'چرخ‌دنده', 'شفت', 'بوش'],
  };

  static Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    storeName = _prefs.getString('store_name') ?? storeName;
    appName = _prefs.getString('app_name') ?? appName;
    currency = _prefs.getString('currency') ?? 'تومان';
    vatPercent = _prefs.getDouble('vat_percent') ?? 0;
    defaultDiscountPercent = _prefs.getDouble('default_discount_percent') ?? 0;
    invoicePrefix = _prefs.getString('invoice_prefix') ?? 'HOS';
    nextInvoiceNumber = _prefs.getInt('next_invoice_number') ?? 1;
    pinEnabled = _prefs.getBool('pin_enabled') ?? false;
    pinCode = await _secureStorage.read(key: 'app_pin') ?? '';
    managerName = _prefs.getString('manager_name') ?? '';
    phone = _prefs.getString('store_phone') ?? '';
    address = _prefs.getString('store_address') ?? '';
    postalCode = _prefs.getString('store_postal_code') ?? '';
    darkMode = _prefs.getBool('dark_mode') ?? false;
    themeMode = _prefs.getString('theme_mode') ?? (darkMode ? 'تیره' : 'روشن');
    drawerImage = _prefs.getString('drawer_image') ?? '';
    fontScale = _prefs.getDouble('font_scale') ?? 1.0;
    productImageMode = _prefs.getString('product_image_mode') ?? 'عکس پیش‌فرض';
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
    await _prefs.setString('app_name', appName);
    await _prefs.setString('currency', currency);
    await _prefs.setDouble('vat_percent', vatPercent);
    await _prefs.setDouble('default_discount_percent', defaultDiscountPercent);
    await _prefs.setString('invoice_prefix', invoicePrefix);
    await _prefs.setInt('next_invoice_number', nextInvoiceNumber);
    await _prefs.setBool('pin_enabled', pinEnabled);
    if (pinEnabled) {
      await _secureStorage.write(key: 'app_pin', value: pinCode);
    } else {
      await _secureStorage.delete(key: 'app_pin');
    }
    revision.value++;
  }

  static Future<void> saveProductImageMode(String mode) async {
    productImageMode = mode;
    await _prefs.setString('product_image_mode', mode);
    revision.value++;
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
    await _prefs.setDouble('font_scale', fontScale);
    await _prefs.remove('drawer_image');
    revision.value++;
  }

  static Future<void> restoreBackup(Map<String, dynamic> data) async {
    if (data['store_name'] is String) { storeName = data['store_name']; await _prefs.setString('store_name', storeName); }
    if (data['app_name'] is String) { appName = data['app_name']; await _prefs.setString('app_name', appName); }
    if (data['currency'] is String) { currency = data['currency']; await _prefs.setString('currency', currency); }
    if (data['vat_percent'] is num) { vatPercent = (data['vat_percent'] as num).toDouble(); await _prefs.setDouble('vat_percent', vatPercent); }
    if (data['default_discount_percent'] is num) { defaultDiscountPercent = (data['default_discount_percent'] as num).toDouble(); await _prefs.setDouble('default_discount_percent', defaultDiscountPercent); }
    if (data['invoice_prefix'] is String) { invoicePrefix = data['invoice_prefix']; await _prefs.setString('invoice_prefix', invoicePrefix); }
    if (data['next_invoice_number'] is num) { nextInvoiceNumber = (data['next_invoice_number'] as num).toInt(); await _prefs.setInt('next_invoice_number', nextInvoiceNumber); }

    if (data['manager_name'] is String) { managerName = data['manager_name']; await _prefs.setString('manager_name', managerName); }
    if (data['phone'] is String) { phone = data['phone']; await _prefs.setString('store_phone', phone); }
    if (data['address'] is String) { address = data['address']; await _prefs.setString('store_address', address); }
    if (data['postal_code'] is String) { postalCode = data['postal_code']; await _prefs.setString('store_postal_code', postalCode); }
    if (data['theme_mode'] is String) { themeMode = data['theme_mode']; await _prefs.setString('theme_mode', themeMode); }
    if (data['dark_mode'] is bool) { darkMode = data['dark_mode']; await _prefs.setBool('dark_mode', darkMode); }
    if (data['drawer_image'] is String) { drawerImage = data['drawer_image']; await _prefs.setString('drawer_image', drawerImage); }
    if (data['font_scale'] is num) { fontScale = (data['font_scale'] as num).toDouble(); await _prefs.setDouble('font_scale', fontScale); }
    if (data['product_image_mode'] is String) { productImageMode = data['product_image_mode']; await _prefs.setString('product_image_mode', productImageMode); }
    if (data['product_groups'] is Map) {
      productGroups = (data['product_groups'] as Map).map((k,v)=>MapEntry(k.toString(), (v as List).map((x)=>x.toString()).toList()));
      await _prefs.setString('product_groups', jsonEncode(productGroups));
    }
    revision.value++;
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
            title: AppSettings.appName,
            locale: const Locale('fa', 'IR'),
            supportedLocales: const [Locale('fa', 'IR'), Locale('en', 'US')],
            localizationsDelegates: const [
              PersianMaterialLocalizations.delegate,
              PersianCupertinoLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
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
            home: const PinLockGate(child: HomePage()),
          );
        },
      );
}

class PinLockGate extends StatefulWidget {
  final Widget child;
  const PinLockGate({super.key, required this.child});
  @override
  State<PinLockGate> createState() => _PinLockGateState();
}

class _PinLockGateState extends State<PinLockGate> {
  final controller = TextEditingController();
  bool unlocked = false;
  String error = '';

  @override
  void dispose() { controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (!AppSettings.pinEnabled || AppSettings.pinCode.isEmpty || unlocked) return widget.child;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(AppSettings.appName)),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.lock_outline, size: 56),
                const SizedBox(height: 16),
                const Text('برای ورود، رمز PIN را وارد کنید'),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  obscureText: true,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                  onSubmitted: (_) => _unlock(),
                  decoration: const InputDecoration(labelText: 'رمز PIN'),
                ),
                if (error.isNotEmpty) Text(error, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 12),
                FilledButton(onPressed: _unlock, child: const Text('ورود به برنامه')),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  void _unlock() {
    if (controller.text == AppSettings.pinCode) {
      setState(() { unlocked = true; error = ''; });
    } else {
      setState(() => error = 'رمز واردشده صحیح نیست.');
      controller.clear();
    }
  }
}

class DemoStore {
  static Database? _db;
  static Database get database => _db!;
  static final products = <Map<String, String>>[];
  static final customers = <Map<String, String>>[];
  static final repairs = <Map<String, String>>[];
  static final sales = <Map<String, String>>[];
  static final operations = <Map<String, String>>[];
  static final archivedSales = <Map<String, String>>[];

  static Future<void> init() async {
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dbPath, 'khadamat_fanni_hosein.db'),
      version: 5,
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
        await _createInvoiceArchive(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await AppDatabaseSchema.create(db);
          await AppDatabaseSchema.migrateLegacyRecords(db);
        }
        if (oldVersion < 3) {
          await AccountingEngine.createTables(db);
        }
        if (oldVersion >= 2 && oldVersion < 4) {
          // Version 3 stored legacy invoice total as pre-discount amount in the JSON record,
          // but mirrored it as the payable total. Normalize existing mirrored invoices once.
          await db.execute('UPDATE invoices SET subtotal = total, total = MAX(0, total - discount) WHERE legacy_source_id IS NOT NULL');
        }
        if (oldVersion < 5) await _createInvoiceArchive(db);
      },
    );
    await _loadCategory('products', products);
    await _loadCategory('customers', customers);
    await _loadCategory('repairs', repairs);
    await _loadCategory('sales', sales);
    await _loadCategory('operations', operations);
    await _backfillInvoiceArchive(_db!);
    await AccountingEngine.ensureDefaultAccounts(_db!);
  }

  static Future<void> _createInvoiceArchive(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoice_archive (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        legacy_source_id INTEGER NOT NULL UNIQUE,
        invoice_number TEXT NOT NULL UNIQUE,
        snapshot_json TEXT NOT NULL,
        archived_at TEXT NOT NULL
      )
    ''');
    await db.execute('''CREATE TRIGGER IF NOT EXISTS invoice_archive_no_update
      BEFORE UPDATE ON invoice_archive BEGIN
        SELECT RAISE(ABORT, 'Archived invoices are immutable');
      END''');
    await db.execute('''CREATE TRIGGER IF NOT EXISTS invoice_archive_no_delete
      BEFORE DELETE ON invoice_archive BEGIN
        SELECT RAISE(ABORT, 'Archived invoices cannot be deleted');
      END''');
  }

  static Future<void> _backfillInvoiceArchive(DatabaseExecutor db) async {
    final rows = await db.query('records', where: 'category = ?', whereArgs: ['sales'], orderBy: 'id ASC');
    for (final row in rows) {
      final sourceId = row['id'] as int;
      final existing = await db.query('invoice_archive', columns: ['id'], where: 'legacy_source_id = ?', whereArgs: [sourceId], limit: 1);
      if (existing.isNotEmpty) continue;
      final raw = jsonDecode(row['data'] as String) as Map<String, dynamic>;
      final number = 'HOS-$sourceId';
      await db.insert('invoice_archive', {
        'legacy_source_id': sourceId,
        'invoice_number': number,
        'snapshot_json': jsonEncode(raw),
        'archived_at': (row['created_at'] as String?) ?? DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    final archived = await db.query('invoice_archive', orderBy: 'id ASC');
    archivedSales
      ..clear()
      ..addAll(archived.map((row) {
        final data = (jsonDecode(row['snapshot_json'] as String) as Map<String, dynamic>).map((k,v)=>MapEntry(k,v?.toString() ?? ''));
        data['شماره فاکتور'] = row['invoice_number'].toString();
        return data;
      }));
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
    await _db!.update('records', {'data': jsonEncode(newItem)}, where: 'category = ? AND data = ?', whereArgs: [category, jsonEncode(oldItem)]);
    final target = switch (category) {
      'products' => products, 'customers' => customers, 'repairs' => repairs, 'sales' => sales, 'operations' => operations,
      _ => throw ArgumentError('دسته اطلاعات نامعتبر است'),
    };
    final index = target.indexWhere((x) => jsonEncode(x) == jsonEncode(oldItem));
    if (index >= 0) target[index] = Map<String,String>.from(newItem);
  }

  static Future<void> delete(String category, List<Map<String, String>> items) async {
    if (items.isEmpty) return;
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
      _ => throw ArgumentError('دسته اطلاعات نامعتبر است'),
    };
    for (final item in items) {
      final index = target.indexWhere((x) => jsonEncode(x) == jsonEncode(item));
      if (index >= 0) target.removeAt(index);
    }
  }

  static Future<void> add(String category, Map<String, String> item) async {
    final createdAt = DateTime.now().toIso8601String();
    int? newRecordId;
    String? assignedInvoiceNumber;
    if (category == 'sales') {
      assignedInvoiceNumber = '${AppSettings.invoicePrefix}-${AppSettings.nextInvoiceNumber.toString().padLeft(5, '0')}';
      item = <String, String>{...item,
        'شماره فاکتور': assignedInvoiceNumber,
        'نام فروشگاه در زمان صدور': AppSettings.storeName,
        'نام صاحب فروشگاه در زمان صدور': AppSettings.managerName,
        'تلفن فروشگاه در زمان صدور': AppSettings.phone,
        'نشانی فروشگاه در زمان صدور': AppSettings.address,
        'کد پستی در زمان صدور': AppSettings.postalCode,
        'واحد پول در زمان صدور': AppSettings.currency,
      };
    }
    await _db!.transaction((txn) async {
      final recordId = await txn.insert('records', {
        'category': category,
        'data': jsonEncode(item),
        'created_at': createdAt,
      });
      newRecordId = recordId;
      await AppDatabaseSchema.insertLegacyRecord(
        txn, category, item, recordId, createdAt,
      );
      if (category == 'sales') {
        await txn.insert('invoice_archive', {
          'legacy_source_id': recordId,
          'invoice_number': assignedInvoiceNumber ?? 'HOS-$recordId',
          'snapshot_json': jsonEncode(item),
          'archived_at': createdAt,
        });
      }
    });
    final target = switch (category) {
      'products' => products,
      'customers' => customers,
      'repairs' => repairs,
      'sales' => sales,
      'operations' => operations,
      _ => throw ArgumentError('دسته اطلاعات نامعتبر است'),
    };
    target.add(Map<String, String>.from(item));
    if (category == 'sales' && newRecordId != null) {
      AppSettings.nextInvoiceNumber++;
      await AppSettings._prefs.setInt('next_invoice_number', AppSettings.nextInvoiceNumber);
      archivedSales.add(Map<String, String>.from(item));
    }
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  final _productPageKey = GlobalKey<_ProductPageState>();
  final _customerPageKey = GlobalKey<_SimpleListPageState>();
  final _repairPageKey = GlobalKey<_SimpleListPageState>();
  final _salesPageKey = GlobalKey<_SimpleListPageState>();
  final _operationsPageKey = GlobalKey<_OperationsPageState>();

  Future<void> _addForCurrentTab() async {
    switch (tab) {
      case 1: await _productPageKey.currentState?.addProduct(); break;
      case 2: await _customerPageKey.currentState?.addItem(); break;
      case 3: await _repairPageKey.currentState?.addItem(); break;
      case 4: await _salesPageKey.currentState?.addItem(); break;
      case 7: await _operationsPageKey.currentState?.addNewOperation(); break;
    }
  }
  int tab = 0;
  final List<int> _tabHistory = [];
  final TextEditingController drawerSearchController = TextEditingController();
  final titles = const ['داشبورد', 'انبار کالا', 'مشتریان', 'تعمیرات', 'فروش و فاکتور', 'گزارش‌ها', 'تنظیمات برنامه', 'عملیات‌های دیگر', 'خروجی و پشتیبان‌گیری'];

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
      ProductPage(key: _productPageKey, onChanged: () => setState(() {})),
      CustomerPage(pageKey: _customerPageKey, onChanged: () => setState(() {})),
      RepairPage(pageKey: _repairPageKey, onChanged: () => setState(() {})),
      SalesPage(pageKey: _salesPageKey, onChanged: () => setState(() {})),
      const ReportsPage(),
      const SettingsPage(),
      OperationsPage(key: _operationsPageKey, onChanged: () => setState(() {})),
      const ExportBackupPage(),
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
                  initialValue: AppSettings.productImageMode,
                  onSelected: (value) async {
                    await AppSettings.saveProductImageMode(value);
                    if (mounted) setState(() {});
                  },
                  itemBuilder: (context) => [
                    for (final option in ['عدم نمایش عکس کالا', 'عکس پیش‌فرض', 'کوچک کردن عکس کالا'])
                      PopupMenuItem<String>(value: option, child: Row(children: [
                        Expanded(child: Text(option)),
                        if (AppSettings.productImageMode == option) const Icon(Icons.check, size: 18),
                      ])),
                  ],
                ),
              if (tab == 1 || tab == 2 || tab == 3 || tab == 4 || tab == 7)
                IconButton(tooltip: 'افزودن مورد جدید', onPressed: _addForCurrentTab, icon: const Icon(Icons.add)),
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
                    leading: Icon([Icons.dashboard, Icons.inventory_2, Icons.people, Icons.build, Icons.receipt_long, Icons.bar_chart, Icons.settings, Icons.account_balance_wallet, Icons.file_download][i]),
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
      ('خروجی و پشتیبان‌گیری', 'PDF، Excel، عکس و نسخه پشتیبان', Icons.file_download, 8),
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
    if (!await _confirmDelete(context, selected.length)) return;
    final category = widget.title == 'مشتری' ? 'customers' : widget.title == 'پذیرش تعمیر' ? 'repairs' : 'sales';
    await DemoStore.delete(category, selected);
    if (!mounted) return;
    setState(() => _selectedKeys.clear());
    widget.onChanged();
  }

  Future<void> addItem({Map<String, String>? existing}) async {
    final controllers = widget.fields.map((field) {
      var value = existing?[field] ?? '';
      if (field == 'تاریخ') {
        final parsed = DateTime.tryParse(value);
        value = parsed != null ? Jalali.fromDateTime(parsed).formatCompactDate() : (value.isEmpty ? Jalali.now().formatCompactDate() : value);
      }
      return TextEditingController(text: value);
    }).toList();
    final focusNodes = widget.fields.map((_) => FocusNode()).toList();
    final repairCustomerNames = DemoStore.customers
        .map((customer) => (customer['نام مشتری'] ?? '').trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final previousRepairCustomer = existing?['نام مشتری']?.trim() ?? '';
    if (previousRepairCustomer.isNotEmpty && !repairCustomerNames.contains(previousRepairCustomer)) {
      repairCustomerNames.add(previousRepairCustomer);
    }
    final repairOptions = <String, String>{};
    if (widget.title == 'فاکتور فروش') {
      final repairRows = await DemoStore.database.query('records',
        columns: ['id', 'data'], where: 'category = ?', whereArgs: ['repairs'], orderBy: 'id DESC');
      for (final row in repairRows) {
        try {
          final data = (jsonDecode(row['data'] as String) as Map).map((k,v)=>MapEntry(k.toString(), v?.toString() ?? ''));
          final id = row['id'].toString();
          final label = id + ' ـ ' + (data['نام مشتری'] ?? '') + ' ـ ' + (data['نوع دستگاه'] ?? 'تعمیر');
          repairOptions[id] = label;
        } catch (_) {}
      }
    }

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
      if (widget.title == 'پذیرش تعمیر' && (item['نام مشتری'] ?? '').trim().isEmpty) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('برای پذیرش تعمیر، ابتدا یک مشتری از فهرست انتخاب کنید.')));
        return;
      }
      if (widget.title == 'مشتری' && (item['شماره تماس'] ?? '').isNotEmpty &&
          !RegExp(r'^\d{11}$').hasMatch(item['شماره تماس'] ?? '')) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('شماره موبایل در صورت ورود باید دقیقاً ۱۱ رقم باشد.')));
        return;
      }
      final category = widget.title == 'مشتری' ? 'customers' : widget.title == 'پذیرش تعمیر' ? 'repairs' : 'sales';
      if (widget.title == 'پذیرش تعمیر' || widget.title == 'فاکتور فروش') {
        final customerName = (item['نام مشتری'] ?? '').trim();
        final matches = await DemoStore.database.query('customers', columns: ['id'], where: "TRIM(first_name || ' ' || last_name) = ?", whereArgs: [customerName], limit: 2);
        if (matches.length == 1) item['شناسه مشتری'] = matches.first['id'].toString();
      }
      if (widget.title == 'فاکتور فروش') {
        if (existing == null) {
          final gross = _ledgerAmount(item['مبلغ کل']);
          if ((item['تخفیف'] ?? '').trim().isEmpty && AppSettings.defaultDiscountPercent > 0) {
            item['تخفیف'] = (gross * AppSettings.defaultDiscountPercent / 100).toStringAsFixed(0);
          }
          final tax = gross * AppSettings.vatPercent / 100;
          item['درصد مالیات'] = AppSettings.vatPercent.toString();
          item['مبلغ مالیات'] = tax.toStringAsFixed(0);
        }
        final linkedRepairId = (item['پذیرش تعمیر مرتبط'] ?? '').trim();
        if (linkedRepairId.isNotEmpty) {
          if (!repairOptions.containsKey(linkedRepairId)) {
            ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('پذیرش تعمیر انتخاب‌شده معتبر نیست.')));
            return;
          }
          final linkedRows = await DemoStore.database.query('records',
            columns: ['data'], where: 'id = ? AND category = ?', whereArgs: [int.tryParse(linkedRepairId), 'repairs'], limit: 1);
          if (linkedRows.isEmpty) {
            ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('سند پذیرش تعمیر پیدا نشد.')));
            return;
          }
          final linkedData = jsonDecode(linkedRows.first['data'] as String) as Map;
          if ((linkedData['نام مشتری'] ?? '').toString().trim() != (item['نام مشتری'] ?? '').trim()) {
            ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('پذیرش انتخاب‌شده متعلق به این مشتری نیست.')));
            return;
          }
          final repairWage = _ledgerAmount(linkedData['اجرت']);
          final invoiceGross = _ledgerAmount(item['مبلغ کل']);
          if (invoiceGross + 0.001 < repairWage) {
            ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text('مبلغ کل فاکتور باید اجرت ثبت‌شده تعمیر را هم پوشش دهد: ' + repairWage.toStringAsFixed(0) + ' تومان.')));
            return;
          }
        }
        if (existing == null) {
          final customerName = (item['نام مشتری'] ?? '').trim();
          final customerId = item['شناسه مشتری'] ?? '';
          final operationRows = await DemoStore.database.query('records',
            columns: ['data'], where: 'category = ?', whereArgs: ['operations']);
          var deposits = 0.0;
          for (final row in operationRows) {
            try {
              final op = jsonDecode(row['data'] as String) as Map;
              final type = (op['نوع عملیات'] ?? '').toString();
              final partyType = (op['نوع طرف حساب'] ?? 'مشتری').toString();
              final opCustomerId = (op['شناسه مشتری'] ?? '').toString();
              final opName = (op['نام شخص'] ?? '').toString().trim();
              final sameCustomer = customerId.isNotEmpty && opCustomerId.isNotEmpty
                  ? customerId == opCustomerId : opName == customerName;
              if (type == 'ثبت بیعانه' && partyType == 'مشتری' && sameCustomer) deposits += _ledgerAmount(op['مبلغ']);
            } catch (_) {}
          }
          final previousSales = await DemoStore.database.query('records',
            columns: ['data'], where: 'category = ?', whereArgs: ['sales']);
          var alreadyApplied = 0.0;
          for (final row in previousSales) {
            try {
              final sale = jsonDecode(row['data'] as String) as Map;
              final saleId = (sale['شناسه مشتری'] ?? '').toString();
              final saleName = (sale['نام مشتری'] ?? '').toString().trim();
              final sameCustomer = customerId.isNotEmpty && saleId.isNotEmpty
                  ? customerId == saleId : saleName == customerName;
              if (sameCustomer) alreadyApplied += _ledgerAmount(sale['بیعانه تخصیص‌یافته']);
            } catch (_) {}
          }
          final gross = _ledgerAmount(item['مبلغ کل']);
          final tax = gross * AppSettings.vatPercent / 100;
          final net = (gross - _ledgerAmount(item['تخفیف']) + tax).clamp(0, double.infinity).toDouble();
          item['بیعانه تخصیص‌یافته'] = (deposits - alreadyApplied).clamp(0, net).toStringAsFixed(0);
        }
      }
      try {
        if (existing == null) {
          await DemoStore.add(category, item);
        } else {
          await DemoStore.update(category, existing, item);
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
                    if (widget.title == 'مشتری' && existing == null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            try {
                              final selected = await FlutterContacts.openExternalPick();
                              if (selected == null || !dialogContext.mounted) return;
                              final contact = await FlutterContacts.getContact(
                                selected.id,
                                withProperties: true,
                              );
                              if (contact == null || !dialogContext.mounted) return;
                              controllers[0].text = contact.displayName;
                              if (controllers.length > 1 && contact.phones.isNotEmpty) {
                                controllers[1].text = contact.phones.first.number
                                    .replaceAll(RegExp(r'[^0-9]'), '');
                              }
                              if (contact.phones.isEmpty && dialogContext.mounted) {
                                ScaffoldMessenger.of(dialogContext).showSnackBar(
                                  const SnackBar(content: Text('نام مخاطب وارد شد؛ این مخاطب شماره تلفن ذخیره‌شده ندارد.')),
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
                        child: (widget.title == 'پذیرش تعمیر' || widget.title == 'فاکتور فروش') && widget.fields[i] == 'تاریخ'
                            ? TextField(
                                controller: controllers[i], readOnly: true,
                                decoration: const InputDecoration(labelText: 'تاریخ شمسی', suffixIcon: Icon(Icons.calendar_month)),
                                onTap: () async {
                                  final current = controllers[i].text.trim();
                                  Jalali initial = Jalali.now();
                                  final match = RegExp(r'^([0-9]{4})[/-]([0-9]{1,2})[/-]([0-9]{1,2})$').firstMatch(current);
                                  if (match != null) {
                                    try { initial = Jalali(int.parse(match.group(1)!), int.parse(match.group(2)!), int.parse(match.group(3)!)); } catch (_) {}
                                  }
                                  final picked = await showPersianDatePicker(
                                    context: dialogContext, initialDate: initial,
                                    firstDate: Jalali(1300, 1, 1), lastDate: Jalali(1500, 12, 29),
                                    locale: const Locale('fa', 'IR'), textDirection: TextDirection.rtl,
                                    helpText: 'انتخاب تاریخ سند', cancelText: 'انصراف', confirmText: 'تأیید',
                                  );
                                  if (picked != null) controllers[i].text = picked.formatCompactDate();
                                },
                              )
                            : widget.title == 'فاکتور فروش' && widget.fields[i] == 'پذیرش تعمیر مرتبط'
                            ? DropdownButtonFormField<String>(
                                value: repairOptions.containsKey(controllers[i].text.trim()) ? controllers[i].text.trim() : null,
                                isExpanded: true,
                                decoration: const InputDecoration(labelText: 'اتصال به پذیرش تعمیر (اختیاری)', helperText: 'پذیرش مرتبط را انتخاب کنید تا اجرت ثبت‌شده در پذیرش دوباره به بدهی مشتری اضافه نشود.'),
                                items: [
                                  const DropdownMenuItem<String>(value: '', child: Text('بدون اتصال به تعمیر')),
                                  ...repairOptions.entries.map((entry) => DropdownMenuItem<String>(value: entry.key, child: Text(entry.value, overflow: TextOverflow.ellipsis))),
                                ],
                                onChanged: (value) => controllers[i].text = value ?? '',
                              )
                            : (widget.title == 'پذیرش تعمیر' || widget.title == 'فاکتور فروش') && widget.fields[i] == 'نام مشتری'
                            ? DropdownButtonFormField<String>(
                                value: repairCustomerNames.contains(controllers[i].text.trim())
                                    ? controllers[i].text.trim()
                                    : null,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  labelText: 'انتخاب مشتری',
                                  hintText: repairCustomerNames.isEmpty
                                      ? 'ابتدا مشتری را ثبت کنید'
                                      : 'از فهرست مشتریان انتخاب کنید',
                                  helperText: repairCustomerNames.isEmpty
                                      ? 'برای ثبت پذیرش، ابتدا از بخش مشتریان یک مشتری اضافه کنید.'
                                      : 'مشتریان قبلی؛ نیازی به ثبت دوباره نیست.',
                                ),
                                items: repairCustomerNames
                                    .map((name) => DropdownMenuItem<String>(
                                          value: name,
                                          child: Text(name, overflow: TextOverflow.ellipsis),
                                        ))
                                    .toList(),
                                onChanged: (value) {
                                  if (value != null) controllers[i].text = value;
                                },
                              )
                            : TextField(
                                controller: controllers[i],
                                focusNode: focusNodes[i],
                                keyboardType: const ['شماره تماس', 'اجرت', 'تعداد', 'مبلغ کل', 'تخفیف', 'مبلغ دریافتی'].contains(widget.fields[i])
                                    ? TextInputType.number : TextInputType.text,
                                inputFormatters: const ['شماره تماس', 'اجرت', 'تعداد', 'مبلغ کل', 'تخفیف', 'مبلغ دریافتی'].contains(widget.fields[i])
                                    ? [FilteringTextInputFormatter.digitsOnly] : const [],
                                textInputAction: i == widget.fields.length - 1 ? TextInputAction.done : TextInputAction.next,
                                onSubmitted: (_) {
                                  if (i < focusNodes.length - 1) FocusScope.of(dialogContext).requestFocus(focusNodes[i + 1]);
                                  else FocusScope.of(dialogContext).unfocus();
                                },
                                decoration: InputDecoration(
                                  labelText: widget.fields[i],
                                  helperText: widget.title == 'فاکتور فروش' && widget.fields[i] == 'مبلغ کل' ? 'مبلغ قبل از تخفیف؛ مبلغ نهایی پس از کسر تخفیف محاسبه می‌شود.' : widget.title == 'فاکتور فروش' && widget.fields[i] == 'تخفیف' ? 'این مبلغ از مبلغ کل کسر می‌شود.' : widget.title == 'فاکتور فروش' && widget.fields[i] == 'مبلغ دریافتی' ? 'فقط وجه جدید دریافتی را وارد کنید؛ بیعانه قبلی را دوباره وارد نکنید.' : null,
                                ),
                              ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [_horizontalDialogActions([
              if (existing != null) TextButton.icon(
                onPressed: () async {
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

  double _ledgerAmount(Object? raw) {
    var value = (raw ?? '').toString().trim();
    const fa = '۰۱۲۳۴۵۶۷۸۹', ar = '٠١٢٣٤٥٦٧٨٩';
    for (var i = 0; i < 10; i++) { value = value.replaceAll(fa[i], '$i').replaceAll(ar[i], '$i'); }
    return double.tryParse(value.replaceAll(',', '').replaceAll('٬', '')) ?? 0;
  }

  DateTime? _ledgerDate(Object? raw) {
    var value = (raw ?? '').toString().trim();
    const fa = '۰۱۲۳۴۵۶۷۸۹', ar = '٠١٢٣٤٥٦٧٨٩';
    for (var i = 0; i < 10; i++) {
      value = value.replaceAll(fa[i], '$i').replaceAll(ar[i], '$i');
    }
    // Persian dates are stored with slashes; convert them as Jalali before
    // trying DateTime, which could otherwise misread 1405/08/23 as Gregorian.
    final jalaliMatch = RegExp(r'^([0-9]{4})/([0-9]{1,2})/([0-9]{1,2})$').firstMatch(value);
    if (jalaliMatch != null) {
      try {
        return Jalali(int.parse(jalaliMatch.group(1)!), int.parse(jalaliMatch.group(2)!), int.parse(jalaliMatch.group(3)!)).toDateTime();
      } catch (_) {
        return null;
      }
    }
    return DateTime.tryParse(value);
  }

  Future<void> _addCustomerReceipt(String customerName, {bool asDeposit = false, bool asPayment = false, int? customerId}) async {
    final amount = TextEditingController(), note = TextEditingController();
    const methods = ['نقدی', 'کارت‌خوان', 'کارت به کارت', 'حواله بانکی', 'چک'];
    String method = methods.first;
    Jalali selectedDate = Jalali.now();
    final saved = await showDialog<bool>(context: context, builder: (d) => Directionality(
      textDirection: TextDirection.rtl, child: StatefulBuilder(builder: (d, refresh) => AlertDialog(
        title: Text(asDeposit ? 'ثبت بیعانه از ' + customerName : asPayment ? 'ثبت پرداخت به ' + customerName : 'ثبت دریافت از ' + customerName),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: amount, autofocus: true, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: InputDecoration(labelText: asDeposit ? 'مبلغ بیعانه (تومان)' : asPayment ? 'مبلغ پرداختی به مشتری (تومان)' : 'مبلغ دریافتی (تومان)')),
          DropdownButtonFormField<String>(value: method, decoration: InputDecoration(labelText: asDeposit ? 'روش دریافت بیعانه' : 'روش دریافت'), items: methods.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(), onChanged: (v) => refresh(() => method = v ?? methods.first)),
          OutlinedButton.icon(
            onPressed: () async {
              final picked = await showPersianDatePicker(
                context: d, initialDate: selectedDate,
                firstDate: Jalali(1300, 1, 1), lastDate: Jalali(1500, 12, 29),
                locale: const Locale('fa', 'IR'), textDirection: TextDirection.rtl,
                helpText: 'تاریخ دریافت / بیعانه', cancelText: 'انصراف', confirmText: 'تأیید',
              );
              if (picked != null) refresh(() => selectedDate = picked);
            },
            icon: const Icon(Icons.calendar_month),
            label: Text('تاریخ: ${selectedDate.formatCompactDate()}'),
          ),
          TextField(controller: note, maxLines: 2, decoration: const InputDecoration(labelText: 'توضیحات / شماره پیگیری / شماره چک')),
        ]),
        actions: [_horizontalDialogActions([
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('انصراف')),
          FilledButton(onPressed: () { if (_ledgerAmount(amount.text) <= 0) { ScaffoldMessenger.of(d).showSnackBar(const SnackBar(content: Text('مبلغ دریافت باید بیشتر از صفر باشد.'))); return; } Navigator.pop(d, true); }, child: Text(asDeposit ? 'ثبت بیعانه' : asPayment ? 'ثبت پرداخت' : 'ثبت دریافت')),
        ])],
      )),
    ));
    if (saved == true) {
      await DemoStore.add('operations', {'نوع عملیات': asDeposit ? 'ثبت بیعانه' : asPayment ? 'پرداخت وجه' : 'دریافت وجه','نوع طرف حساب':'مشتری','نام شخص':customerName,'شناسه مشتری':customerId?.toString() ?? '', 'مبلغ':amount.text.trim(),'روش':method,'تاریخ':selectedDate.toDateTime().toIso8601String(),'توضیحات':note.text.trim()});
      if (mounted) { setState(() {}); widget.onChanged(); }
    }
    amount.dispose(); note.dispose();
  }

  Future<void> _showCustomerAccount(Map<String, String> customer) async {
    final customerName = (customer['نام مشتری'] ?? '').trim();
    if (customerName.isEmpty) return;
    final customerRecord = await DemoStore.database.query('records', columns: ['id'], where: 'category = ? AND data = ?', whereArgs: ['customers', jsonEncode(customer)], limit: 1);
    int? customerId;
    if (customerRecord.isNotEmpty) {
      final normalized = await DemoStore.database.query('customers', columns: ['id'], where: 'legacy_source_id = ?', whereArgs: [customerRecord.first['id']], limit: 1);
      if (normalized.isNotEmpty) customerId = normalized.first['id'] as int;
    }
    final sameNameRows = await DemoStore.database.rawQuery(
      "SELECT COUNT(*) AS total FROM customers WHERE TRIM(first_name || ' ' || last_name) = ?",
      [customerName],
    );
    final sameNameCount = (sameNameRows.first['total'] as num?)?.toInt() ?? 0;
    final records = await DemoStore.database.query('records', columns: ['id','category','data','created_at'], where: 'category IN (?, ?, ?)', whereArgs: ['sales','operations','repairs']);
    if (!mounted) return;
    final invoicedRepairIds = <String>{};
    for (final record in records.where((r) => r['category'] == 'sales')) {
      try {
        final sale = jsonDecode(record['data'] as String) as Map;
        final repairId = (sale['پذیرش تعمیر مرتبط'] ?? '').toString().trim();
        if (repairId.isNotEmpty) invoicedRepairIds.add(repairId);
      } catch (_) {}
    }
    final rows = <Map<String,Object?>>[];
    for (final record in records) {
      Map<String,dynamic> data;
      try { data = jsonDecode(record['data'] as String) as Map<String,dynamic>; } catch (_) { continue; }
      final person = (data['نام مشتری'] ?? data['نام شخص'] ?? '').toString().trim();
      if (record['category'] == 'operations') {
        final linkedId = int.tryParse((data['شناسه مشتری'] ?? '').toString());
        if (customerId != null && linkedId != null) {
          if (linkedId != customerId) continue;
        } else if (sameNameCount > 1 || person != customerName) {
          continue;
        }
      } else {
        final linkedId = int.tryParse((data['شناسه مشتری'] ?? '').toString());
        if (customerId != null && linkedId != null) {
          if (linkedId != customerId) continue;
        } else if (sameNameCount > 1 || person != customerName) {
          continue;
        }
      }
      if (record['category'] == 'operations') {
        final type = (data['نوع عملیات'] ?? '').toString();
        final partyType = (data['نوع طرف حساب'] ?? (type == 'تخفیف گرفتن' ? 'فروشنده' : 'مشتری')).toString();
        if (partyType != 'مشتری') continue;
      }
      final date = _ledgerDate(data['تاریخ']) ?? _ledgerDate(record['created_at']) ?? DateTime.now();
      double debit = 0, credit = 0; String desc = '', method = '';
      if (record['category'] == 'sales') {
        final gross = _ledgerAmount(data['مبلغ کل']);
        final discount = _ledgerAmount(data['تخفیف']).clamp(0, gross).toDouble();
        final received = _ledgerAmount(data['مبلغ دریافتی']);
        if (gross <= 0 && received <= 0) continue;
        desc = 'فاکتور فروش: ' + (data['شرح کالا/خدمت'] ?? 'فروش کالا یا خدمت').toString();
        if (gross > 0) rows.add({'date':date,'description':desc,'method':'','debit':gross,'credit':0.0});
        if (discount > 0) rows.add({'date':date,'description':'تخفیف فروش به مشتری','method':'','debit':0.0,'credit':discount});
        final tax = _ledgerAmount(data['مبلغ مالیات']);
        if (tax > 0) rows.add({'date':date,'description':'مالیات بر ارزش افزوده فاکتور','method':'','debit':tax,'credit':0.0});
        if (received > 0) rows.add({'date':date,'description':'دریافت بابت فاکتور فروش','method':(data['روش پرداخت'] ?? '').toString(),'debit':0.0,'credit':received});
        continue;
      } else if (record['category'] == 'repairs') {
        if (invoicedRepairIds.contains(record['id'].toString())) continue;
        final wage = _ledgerAmount(data['اجرت']);
        if (wage <= 0) continue;
        debit = wage;
        desc = 'اجرت تعمیر: ' + (data['نوع دستگاه'] ?? 'تعمیر دستگاه').toString();
        final fault = (data['شرح عیب'] ?? '').toString().trim();
        if (fault.isNotEmpty) desc += ' ـ ' + fault;
      } else {
        final type = (data['نوع عملیات'] ?? '').toString(), value = _ledgerAmount(data['مبلغ']);
        if (value <= 0) continue;
        if (['متفرقه شخص بدهکار','پرداخت وجه'].contains(type)) debit = value;
        else if (['متفرقه شخص بستانکار','دریافت وجه','ثبت بیعانه','تخفیف دادن'].contains(type)) credit = value;
        else continue;
        desc = type; final extra = (data['توضیحات'] ?? '').toString().trim(); if (extra.isNotEmpty) desc += ' ـ ' + extra;
        method = (data['روش'] ?? '').toString();
      }
      rows.add({'date':date,'description':desc,'method':method,'debit':debit,'credit':credit});
    }
    rows.sort((a,b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));
    double balance = 0, debitTotal = 0, creditTotal = 0;
    for (final row in rows) { debitTotal += row['debit'] as double; creditTotal += row['credit'] as double; balance += (row['debit'] as double) - (row['credit'] as double); row['balance'] = balance; }
    final edit = await showDialog<bool>(context: context, builder: (d) => Directionality(textDirection: TextDirection.rtl, child: AlertDialog(
      title: Text('دفتر حساب ' + customerName),
      content: SizedBox(width: 650, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(balance > 0.009 ? 'وضعیت: مشتری بدهکار است' : balance < -0.009 ? 'وضعیت: مشتری بستانکار است' : 'وضعیت: حساب تسویه است', style: TextStyle(fontWeight: FontWeight.bold, color: balance > 0.009 ? Colors.red.shade700 : balance < -0.009 ? Colors.green.shade700 : null)),
          Text('مانده: ' + balance.abs().toStringAsFixed(0) + ' تومان'), Text('جمع بدهکار: ' + debitTotal.toStringAsFixed(0) + ' تومان'), Text('جمع بستانکار: ' + creditTotal.toStringAsFixed(0) + ' تومان'),
        ]))),
        if (rows.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('هنوز گردش مالی برای این مشتری ثبت نشده است.'))
        else SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(
          columnSpacing: 10, columns: const [DataColumn(label:Text('تاریخ')),DataColumn(label:Text('شرح')),DataColumn(label:Text('روش')),DataColumn(label:Text('بدهکار')),DataColumn(label:Text('بستانکار')),DataColumn(label:Text('مانده'))],
          rows: rows.map((row) { final date = Jalali.fromDateTime(row['date'] as DateTime).formatCompactDate(); final b = row['balance'] as double; return DataRow(cells: [
            DataCell(Text(date)), DataCell(SizedBox(width:120,child:Text(row['description'] as String,maxLines:2,overflow:TextOverflow.ellipsis))), DataCell(Text((row['method'] as String).isEmpty ? '—' : row['method'] as String)),
            DataCell(Text((row['debit'] as double).toStringAsFixed(0))), DataCell(Text((row['credit'] as double).toStringAsFixed(0))), DataCell(Text(b.abs().toStringAsFixed(0) + ' ' + (b > 0.009 ? 'بدهکار' : b < -0.009 ? 'بستانکار' : 'تسویه'))),
          ]); }).toList(),
        )),
        if (sameNameCount > 1)
          const Text('هشدار: چند مشتری با نام یکسان وجود دارد؛ اسناد قدیمیِ بدون شناسه مشتری برای جلوگیری از اختلاط حساب در این دفتر لحاظ نشده‌اند.', style: TextStyle(fontSize:11,color:Colors.deepOrange)),
        const Text('مانده مثبت یعنی مشتری به فروشگاه بدهکار است؛ مانده منفی یعنی فروشگاه به مشتری بدهکار است.', style: TextStyle(fontSize:11,color:Colors.grey)),
      ]))),
      actions: [_horizontalDialogActions([
        TextButton(onPressed: () => Navigator.pop(d,false), child: const Text('بستن')),
        OutlinedButton.icon(onPressed: () async { Navigator.pop(d,false); await _addCustomerReceipt(customerName, customerId: customerId); if (mounted) await _showCustomerAccount(customer); }, icon: const Icon(Icons.payments_outlined), label: const Text('ثبت دریافت از مشتری')),
        OutlinedButton.icon(onPressed: () async { Navigator.pop(d,false); await _addCustomerReceipt(customerName, asDeposit: true, customerId: customerId); if (mounted) await _showCustomerAccount(customer); }, icon: const Icon(Icons.savings_outlined), label: const Text('ثبت بیعانه')),
        OutlinedButton.icon(onPressed: () async { Navigator.pop(d,false); await _addCustomerReceipt(customerName, asPayment: true, customerId: customerId); if (mounted) await _showCustomerAccount(customer); }, icon: const Icon(Icons.payments_outlined), label: const Text('ثبت پرداخت به مشتری')),
        FilledButton.icon(onPressed: () => Navigator.pop(d,true), icon: const Icon(Icons.edit_outlined), label: const Text('ویرایش مشخصات')),
      ])],
    )));
    if (edit == true && mounted) await addItem(existing: customer);
  }
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.transparent,
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
                  leading: CircleAvatar(child: Icon(_selectedKeys.contains(_keyOf(item)) ? Icons.check : widget.title == 'مشتری' ? Icons.account_balance_wallet_outlined : Icons.description)),
                  title: Text(item[widget.primary]?.isNotEmpty == true ? item[widget.primary]! : 'بدون عنوان'),
                  subtitle: Text(item.entries.where((e) => e.value.isNotEmpty).map((e) => e.key + ': ' + e.value).join(' • ')),
                  trailing: _selectedKeys.isNotEmpty ? Checkbox(value: _selectedKeys.contains(_keyOf(item)), onChanged: (_) => setState(() { final k=_keyOf(item); _selectedKeys.contains(k) ? _selectedKeys.remove(k) : _selectedKeys.add(k); })) : widget.title == 'مشتری' ? IconButton(tooltip:'ویرایش مشخصات مشتری',onPressed:() => addItem(existing:item),icon:const Icon(Icons.edit_outlined)) : const Icon(Icons.edit_outlined),
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

  Future<void> _deleteProducts(List<Map<String, String>> items) async {
    if (items.isEmpty || !await _confirmDelete(context, items.length)) return;
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
    final supplier = TextEditingController();
    final purchasePaid = TextEditingController(text: '0');
    final vatRate = TextEditingController(text: '0');
    String purchaseMethod = 'نقدی';
    bool vatIncluded = false;
    String? productGroup;
    String? productSubgroup;
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
          supplier.text.trim().isNotEmpty || purchasePaid.text.trim() != '0' || purchaseMethod != 'نقدی' ||
          vatRate.text.trim() != '0' || vatIncluded || unit != 'عدد' || isUsed ||
          productGroup != null || productSubgroup != null || productImageBase64 != null;
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
                              ? [FilteringTextInputFormatter.digitsOnly]
                              : [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}'))],
                          textInputAction: TextInputAction.next,
                          onChanged: (_) => refresh(() {}),
                          decoration: InputDecoration(labelText: names[i]),
                        ),
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
                              locale: const Locale('fa', 'IR'),
                              textDirection: TextDirection.rtl,
                              helpText: 'انتخاب تاریخ شمسی',
                              cancelText: 'انصراف',
                              confirmText: 'تأیید',
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
                    TextField(controller: shipping, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], onChanged: (_) => refresh(() {}), decoration: const InputDecoration(labelText: 'هزینه پست')),
                    const SizedBox(height: 10),
                    TextField(controller: freight, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], onChanged: (_) => refresh(() {}), decoration: const InputDecoration(labelText: 'هزینه باربری / حمل')),
                    const SizedBox(height: 10),
                    TextField(controller: other, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], onChanged: (_) => refresh(() {}), decoration: const InputDecoration(labelText: 'سایر هزینه‌های خرید')),
                    const SizedBox(height: 10),
                    const Align(alignment: Alignment.centerRight, child: Text('اطلاعات طرف حساب خرید', style: TextStyle(fontWeight: FontWeight.bold))),
                    const SizedBox(height: 8),
                    TextField(controller: supplier, decoration: const InputDecoration(labelText: 'نام فروشنده / تأمین‌کننده (اختیاری)')),
                    const SizedBox(height: 8),
                    TextField(controller: purchasePaid, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], onChanged: (_) => refresh(() {}), decoration: const InputDecoration(labelText: 'مبلغ پرداخت‌شده هنگام خرید (تومان)')),
                    DropdownButtonFormField<String>(value: purchaseMethod, decoration: const InputDecoration(labelText: 'روش پرداخت خرید'), items: const ['نقدی','کارت به کارت','حواله بانکی','چک'].map((m) => DropdownMenuItem(value:m, child:Text(m))).toList(), onChanged: (v) => refresh(() => purchaseMethod = v ?? 'نقدی')),
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
                  item['نام فروشنده'] = supplier.text.trim();
                  item['مبلغ پرداخت‌شده خرید'] = purchasePaid.text.trim();
                  item['روش پرداخت خرید'] = purchaseMethod;
                  if (number(purchasePaid) > total) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('مبلغ پرداخت‌شده نمی‌تواند از جمع بهای تمام‌شده بیشتر باشد.')));
                    return;
                  }
                  DemoStore.add('products', item).then((_) async {
                    if (supplier.text.trim().isNotEmpty && total > 0) {
                      await DemoStore.add('operations', {
                        'نوع عملیات':'خرید کالا', 'نوع طرف حساب':'فروشنده', 'نام شخص':supplier.text.trim(),
                        'مبلغ':total.toStringAsFixed(0), 'مبلغ پرداخت‌شده':number(purchasePaid).toStringAsFixed(0),
                        'روش':purchaseMethod, 'تاریخ':DateTime.now().toIso8601String(),
                        'توضیحات':'ثبت خرید موجودی: ${c[0].text.trim()} (${qty.toStringAsFixed(0)} عدد)',
                      });
                    }
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
    for (final x in [...c, shipping, freight, other, supplier, purchasePaid, vatRate, saleDate]) { x.dispose(); }
    if (saved == true && mounted) { setState(() {}); widget.onChanged(); }
  }

  Future<void> editProduct(Map<String, String> item) async {
    final groupKey = item['گروه اصلی'] ?? '';
    if (groupKey.isNotEmpty && !AppSettings.productGroups.containsKey(groupKey)) {
      AppSettings.productGroups[groupKey] = item['زیرگروه']?.isNotEmpty == true ? [item['زیرگروه']!] : [];
      await AppSettings.saveProductGroups();
    }
    final editable = item.keys.where((k) => k != 'تصویر کالا' && k != 'گروه اصلی' && k != 'زیرگروه').toList();
    final controllers = {for (final key in editable) key: TextEditingController(text: item[key] ?? '')};
    String? group = groupKey.isEmpty ? null : groupKey;
    String? subgroup = (item['زیرگروه'] ?? '').isEmpty ? null : item['زیرگروه'];

    bool dirty() {
      for (final key in editable) {
        if (controllers[key]!.text.trim() != (item[key] ?? '')) return true;
      }
      return group != (item['گروه اصلی']?.isEmpty == true ? null : item['گروه اصلی']) ||
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
              changed['گروه اصلی'] = group ?? '';
              changed['زیرگروه'] = subgroup ?? '';
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
                          : CircleAvatar(
                              radius: AppSettings.productImageMode == 'کوچک کردن عکس کالا' ? 14 : 20,
                              child: Icon(_selectedProducts.contains(jsonEncode(item)) ? Icons.check : Icons.inventory_2, size: AppSettings.productImageMode == 'کوچک کردن عکس کالا' ? 16 : 24),
                            ),
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
  final GlobalKey<_SimpleListPageState> pageKey;
  const CustomerPage({super.key, required this.pageKey, required this.onChanged});

  @override
  Widget build(BuildContext context) => SimpleListPage(
        key: pageKey,
        title: 'مشتری',
        data: DemoStore.customers,
        fields: const ['نام مشتری', 'شماره تماس', 'آدرس', 'توضیحات'],
        primary: 'نام مشتری',
        onChanged: onChanged,
      );
}

class RepairPage extends StatelessWidget {
  final VoidCallback onChanged;
  final GlobalKey<_SimpleListPageState> pageKey;
  const RepairPage({super.key, required this.pageKey, required this.onChanged});

  @override
  Widget build(BuildContext context) => SimpleListPage(
        key: pageKey,
        title: 'پذیرش تعمیر',
        data: DemoStore.repairs,
        fields: const ['نام مشتری', 'نوع دستگاه', 'شرح عیب', 'اجرت', 'وضعیت تعمیر', 'تاریخ'],
        primary: 'نوع دستگاه',
        onChanged: onChanged,
      );
}

class SalesPage extends StatelessWidget {
  final VoidCallback onChanged;
  final GlobalKey<_SimpleListPageState> pageKey;
  const SalesPage({super.key, required this.pageKey, required this.onChanged});

  @override
  Widget build(BuildContext context) => SimpleListPage(
        key: pageKey,
        title: 'فاکتور فروش',
        data: DemoStore.sales,
        fields: const ['نام مشتری', 'پذیرش تعمیر مرتبط', 'شرح کالا/خدمت', 'تعداد', 'مبلغ کل', 'تخفیف', 'مبلغ دریافتی', 'تاریخ'],
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
  late final TextEditingController appName;
  late final TextEditingController vatPercent;
  late final TextEditingController defaultDiscount;
  late final TextEditingController invoicePrefix;
  late final TextEditingController nextInvoice;
  late final TextEditingController pinCode;
  late String currency;
  late bool pinEnabled;
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
    appName = TextEditingController(text: AppSettings.appName);
    vatPercent = TextEditingController(text: AppSettings.vatPercent.toString());
    defaultDiscount = TextEditingController(text: AppSettings.defaultDiscountPercent.toString());
    invoicePrefix = TextEditingController(text: AppSettings.invoicePrefix);
    nextInvoice = TextEditingController(text: AppSettings.nextInvoiceNumber.toString());
    pinCode = TextEditingController(text: AppSettings.pinCode);
    currency = AppSettings.currency;
    pinEnabled = AppSettings.pinEnabled;
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
      appName.text.trim() != AppSettings.appName ||
      vatPercent.text.trim() != AppSettings.vatPercent.toString() ||
      defaultDiscount.text.trim() != AppSettings.defaultDiscountPercent.toString() ||
      invoicePrefix.text.trim() != AppSettings.invoicePrefix ||
      nextInvoice.text.trim() != AppSettings.nextInvoiceNumber.toString() ||
      pinCode.text != AppSettings.pinCode || pinEnabled != AppSettings.pinEnabled || currency != AppSettings.currency ||
      themeMode != AppSettings.themeMode || fontScale != AppSettings.fontScale || drawerImage != AppSettings.drawerImage;

  @override
  void dispose() {
    storeName.dispose();
    managerName.dispose();
    phone.dispose();
    address.dispose();
    postalCode.dispose(); appName.dispose(); vatPercent.dispose(); defaultDiscount.dispose(); invoicePrefix.dispose(); nextInvoice.dispose(); pinCode.dispose();
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
      final vat = double.tryParse(vatPercent.text.replaceAll(',', '.'));
      final discount = double.tryParse(defaultDiscount.text.replaceAll(',', '.'));
      final sequence = int.tryParse(nextInvoice.text);
      if (vat == null || vat < 0 || vat > 100 || discount == null || discount < 0 || discount > 100 || sequence == null || sequence < 1 || invoicePrefix.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('مالیات و تخفیف باید بین صفر تا ۱۰۰ و شماره فاکتور عدد مثبت باشد.')));
        return false;
      }
      if (pinEnabled && !RegExp(r'^[0-9]{4,8}$'
