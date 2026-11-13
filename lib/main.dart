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
    await _db!.transaction((txn) async {
      final recordId = await txn.insert('records', {
        'category': category,
        'data': jsonEncode(item),
        'created_at': createdAt,
      });
      await AppDatabaseSchema.insertLegacyRecord(
        txn, category, item, recordId, createdAt,
      );
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
            actions: [IconButton(tooltip: 'جست‌وجو', onPressed: () => _showScopedSearch(context, _scopeForTab()), icon: const Icon(Icons.search))],
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
    if (!await _confirmDelete(context, selected.length)) return;
    final category = widget.title == 'مشتری' ? 'customers' : widget.title == 'پذیرش تعمیر' ? 'repairs' : 'sales';
    await DemoStore.delete(category, selected);
    if (!mounted) return;
    setState(() => _selectedKeys.clear());
    widget.onChanged();
  }

  Future<void> addItem({Map<String, String>? existing}) async {
    final controllers = widget.fields.map((field) => TextEditingController(text: existing?[field] ?? '')).toList();
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
                              final allowed = await FlutterContacts.requestPermission(readonly: true);
                              if (!allowed) {
                                if (dialogContext.mounted) ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('اجازه دسترسی به مخاطبین داده نشد.')));
                                return;
                              }
                              final contacts = await FlutterContacts.getContacts(withProperties: true);
                              if (!dialogContext.mounted) return;
                              if (contacts.isEmpty) {
                                await showDialog<void>(context: dialogContext, builder: (d) => Directionality(
                                  textDirection: TextDirection.rtl,
                                  child: AlertDialog(
                                    title: const Text('مخاطبی پیدا نشد'),
                                    content: const Text('در فهرست مخاطبین گوشی، مخاطبی برای نمایش وجود ندارد.'),
                                    actions: [_horizontalDialogActions([TextButton(onPressed: () => Navigator.pop(d), child: const Text('باشه'))])],
                                  ),
                                ));
                                return;
                              }
                              final selected = await showDialog<Contact>(
                                context: dialogContext,
                                builder: (pickContext) => Directionality(
                                  textDirection: TextDirection.rtl,
                                  child: AlertDialog(
                                    title: const Text('انتخاب از مخاطبین'),
                                    content: SizedBox(
                                      width: 360,
                                      height: 420,
                                      child: ListView.builder(
                                        itemCount: contacts.length,
                                        itemBuilder: (context, index) {
                                          final contact = contacts[index];
                                          return ListTile(
                                            title: Text(contact.displayName),
                                            subtitle: Text(contact.phones.isNotEmpty ? contact.phones.first.number : 'بدون شماره'),
                                            onTap: () => Navigator.pop(pickContext, contact),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              );
                              if (selected != null) {
                                controllers[0].text = selected.displayName;
                                if (controllers.length > 1 && selected.phones.isNotEmpty) {
                                  controllers[1].text = selected.phones.first.number.replaceAll(RegExp(r'[^0-9]'), '');
                                }
                              }
                            } catch (error) {
                              if (dialogContext.mounted) ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text('باز کردن مخاطبین ناموفق بود: $error')));
                            }
                          },
                          icon: const Icon(Icons.contacts_outlined),
                          label: const Text('انتخاب از مخاطبین گوشی'),
                        ),
                      ),
                    for (int i = 0; i < widget.fields.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: TextField(
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
                          decoration: InputDecoration(labelText: widget.fields[i]),
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

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.transparent,
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
                  subtitle: Text(item.entries.where((e) => e.value.isNotEmpty).map((e) => '${e.key}: ${e.value}').join(' • ')),
                  trailing: _selectedKeys.isNotEmpty ? Checkbox(value: _selectedKeys.contains(_keyOf(item)), onChanged: (_) => setState(() { final k=_keyOf(item); _selectedKeys.contains(k) ? _selectedKeys.remove(k) : _selectedKeys.add(k); })) : const Icon(Icons.edit_outlined),
                  onLongPress: () => setState(() => _selectedKeys.add(_keyOf(item))),
                  onTap: () {
                    if (_selectedKeys.isNotEmpty) setState(() { final k=_keyOf(item); _selectedKeys.contains(k) ? _selectedKeys.remove(k) : _selectedKeys.add(k); });
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
    final vatRate = TextEditingController(text: '0');
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
                  leading: (item['تصویر کالا'] ?? '').isNotEmpty
                      ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(base64Decode(item['تصویر کالا']!), width: 48, height: 48, fit: BoxFit.cover))
                      : CircleAvatar(child: Icon(_selectedProducts.contains(jsonEncode(item)) ? Icons.check : Icons.inventory_2)),
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
        fields: const ['نام مشتری', 'شماره تماس', 'آدرس', 'توضیحات'],
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
        fields: const ['نام مشتری', 'نوع دستگاه', 'شرح عیب', 'اجرت', 'وضعیت تعمیر'],
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
        fields: const ['نام مشتری', 'شرح کالا/خدمت', 'تعداد', 'مبلغ کل', 'تخفیف', 'مبلغ دریافتی'],
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
          TextField(controller: phone, keyboardType: TextInputType.phone, inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)], decoration: const InputDecoration(labelText: 'شماره تماس فروشگاه (حداکثر ۱۱ رقم)')),
          const SizedBox(height: 10),
          TextField(controller: address, maxLines: 2, decoration: const InputDecoration(labelText: 'آدرس فروشگاه')),
          const SizedBox(height: 10),
          TextField(controller: postalCode, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)], decoration: const InputDecoration(labelText: 'کد پستی (دقیقاً ۱۰ رقم)')),
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
  static const options = ['تخفیف دادن', 'تخفیف گرفتن', 'متفرقه شخص بدهکار', 'متفرقه شخص بستانکار', 'پرداخت وجه', 'دریافت وجه'];
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
              TextField(controller: name, decoration: const InputDecoration(labelText: 'نام شخص')),
              TextField(controller: amount, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: const InputDecoration(labelText: 'مبلغ (تومان)')),
              if (op == 'پرداخت وجه' || op == 'دریافت وجه')
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

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('گزارش‌های اولیه', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
          for (final r in [
            'تعداد کالاهای ثبت‌شده: ${DemoStore.products.length}',
            'تعداد مشتریان: ${DemoStore.customers.length}',
            'تعداد پذیرش‌های تعمیر: ${DemoStore.repairs.length}',
            'تعداد فاکتورهای فروش: ${DemoStore.sales.length}',
          ])
            Card(child: ListTile(leading: const Icon(Icons.analytics_outlined), title: Text(r))),
          const Text(
            'اطلاعات این نسخه به‌صورت دائمی در SQLite همین گوشی ذخیره می‌شوند. همگام‌سازی چند گوشی و پشتیبان‌گیری ابری در مرحله بعد اضافه می‌شود.',
            style: TextStyle(color: Colors.black54),
          ),
        ],
      );
}
