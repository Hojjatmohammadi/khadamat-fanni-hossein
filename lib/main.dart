import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
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
  static double fontScale = 1.0;

  static Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    storeName = _prefs.getString('store_name') ?? storeName;
    managerName = _prefs.getString('manager_name') ?? '';
    phone = _prefs.getString('store_phone') ?? '';
    address = _prefs.getString('store_address') ?? '';
    postalCode = _prefs.getString('store_postal_code') ?? '';
    darkMode = _prefs.getBool('dark_mode') ?? false;
    fontScale = _prefs.getDouble('font_scale') ?? 1.0;
  }

  static Future<void> save({
    required String newStoreName,
    required String newManagerName,
    required String newPhone,
    required String newAddress,
    required String newPostalCode,
    required bool newDarkMode,
    required double newFontScale,
  }) async {
    storeName = newStoreName.trim().isEmpty ? 'فروشگاه من' : newStoreName.trim();
    managerName = newManagerName.trim();
    phone = newPhone.trim();
    address = newAddress.trim();
    postalCode = newPostalCode.trim();
    darkMode = newDarkMode;
    fontScale = newFontScale;
    await _prefs.setString('store_name', storeName);
    await _prefs.setString('manager_name', managerName);
    await _prefs.setString('store_phone', phone);
    await _prefs.setString('store_address', address);
    await _prefs.setString('store_postal_code', postalCode);
    await _prefs.setBool('dark_mode', darkMode);
    await _prefs.setDouble('font_scale', fontScale);
    revision.value++;
  }
}

class HoseinApp extends StatelessWidget {
  const HoseinApp({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: AppSettings.revision,
        builder: (context, _, __) {
          final brightness = AppSettings.darkMode ? Brightness.dark : Brightness.light;
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'خدمات فنی حسین',
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(seedColor: yellow, brightness: brightness),
              scaffoldBackgroundColor: AppSettings.darkMode ? const Color(0xFF121212) : const Color(0xFFF7F7F7),
              appBarTheme: const AppBarTheme(backgroundColor: black, foregroundColor: yellow),
              inputDecorationTheme: InputDecorationTheme(
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: AppSettings.darkMode ? const Color(0xFF252525) : Colors.white,
              ),
              textTheme: ThemeData(brightness: brightness).textTheme.apply(fontSizeFactor: AppSettings.fontScale),
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
  final titles = const ['داشبورد', 'انبار کالا', 'مشتریان', 'تعمیرات', 'فروش و فاکتور', 'گزارش‌ها', 'تنظیمات برنامه'];

  void _selectTab(int nextTab) {
    if (nextTab < 0 || nextTab >= titles.length || nextTab == tab) return;
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
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('ادامه کار'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('خروج'),
            ),
          ],
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
                        child: Image.asset(
                          'assets/logo.jpg',
                          width: 68,
                          height: 68,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(AppSettings.storeName, style: const TextStyle(color: yellow, fontSize: 22, fontWeight: FontWeight.bold)),
                      Text('نسخه آزمایشی', style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
                for (int i = 0; i < titles.length; i++)
                  ListTile(
                    leading: Icon([Icons.dashboard, Icons.inventory_2, Icons.people, Icons.build, Icons.receipt_long, Icons.bar_chart, Icons.settings][i]),
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
                        Text(s.$2, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                        Text(s.$1, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
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
  Future<void> addItem() async {
    final controllers = widget.fields.map((_) => TextEditingController()).toList();
    final focusNodes = widget.fields.map((_) => FocusNode()).toList();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('ثبت ${widget.title} جدید'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < widget.fields.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TextField(
                        controller: controllers[i],
                        focusNode: focusNodes[i],
                        keyboardType: const [
                          'شماره تماس', 'اجرت', 'تعداد', 'مبلغ کل', 'تخفیف', 'مبلغ دریافتی'
                        ].contains(widget.fields[i]) ? TextInputType.number : TextInputType.text,
                        inputFormatters: const [
                          'شماره تماس', 'اجرت', 'تعداد', 'مبلغ کل', 'تخفیف', 'مبلغ دریافتی'
                        ].contains(widget.fields[i])
                            ? [FilteringTextInputFormatter.digitsOnly]
                            : const [],
                        textInputAction: i == widget.fields.length - 1
                            ? TextInputAction.done
                            : TextInputAction.next,
                        onSubmitted: (_) {
                          if (i < focusNodes.length - 1) {
                            FocusScope.of(dialogContext).requestFocus(focusNodes[i + 1]);
                          } else {
                            FocusScope.of(dialogContext).unfocus();
                          }
                        },
                        decoration: InputDecoration(labelText: widget.fields[i]),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')),
            FilledButton(
              onPressed: () {
                final item = <String, String>{};
                for (int i = 0; i < widget.fields.length; i++) {
                  item[widget.fields[i]] = controllers[i].text.trim();
                }
                if (widget.title == 'مشتری' &&
                    !RegExp(r'^\d{11}$').hasMatch(item['شماره تماس'] ?? '')) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('شماره موبایل باید دقیقاً ۱۱ رقم باشد.')),
                  );
                  return;
                }
                if (item.values.any((value) => value.isNotEmpty)) {
                  final category = widget.title == 'مشتری'
                      ? 'customers'
                      : widget.title == 'پذیرش تعمیر'
                          ? 'repairs'
                          : 'sales';
                  DemoStore.add(category, item).then((_) {
                    if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                  }).catchError((error) {
                    if (dialogContext.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ذخیره اطلاعات ناموفق بود: $error')));
                    }
                  });
                } else {
                  Navigator.pop(dialogContext, false);
                }
              },
              child: const Text('ذخیره'),
            ),
          ],
        ),
      ),
    );
    for (final controller in controllers) {
      controller.dispose();
    }
    for (final node in focusNodes) {
      node.dispose();
    }
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
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (widget.data.isEmpty)
              const Padding(
                padding: EdgeInsets.all(28),
                child: Center(child: Text('هنوز اطلاعاتی ثبت نشده است')),
              ),
            for (final item in widget.data.reversed)
              Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.description)),
                  title: Text(item[widget.primary]?.isNotEmpty == true ? item[widget.primary]! : 'بدون عنوان'),
                  subtitle: Text(
                    item.entries.where((e) => e.value.isNotEmpty).map((e) => '${e.key}: ${e.value}').join(' • '),
                  ),
                ),
              ),
          ],
        ),
      );
}

class ProductPage extends StatefulWidget {
  final VoidCallback onChanged;
  const ProductPage({super.key, required this.onChanged});

  @override
  State<ProductPage> createState() => _ProductPageState();
}

class _ProductPageState extends State<ProductPage> {
  Future<void> addProduct() async {
    final names = ['نام کالا', 'گروه اصلی', 'زیرگروه', 'کد کالا', 'موجودی', 'قیمت خرید هر واحد', 'قیمت فروش'];
    final c = List.generate(names.length, (_) => TextEditingController());
    final shipping = TextEditingController(text: '0');
    final freight = TextEditingController(text: '0');
    final other = TextEditingController(text: '0');
    final vatRate = TextEditingController(text: '0');
    bool vatIncluded = false;
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
      final qty = number(c[4]);
      final purchase = number(c[5]) * qty;
      final extra = number(shipping) + number(freight) + number(other);
      final vat = vatIncluded ? purchase * number(vatRate) / 100 : 0;
      return purchase + extra + vat;
    }

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Directionality(
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
                    for (int i = 0; i < names.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: TextField(
                          controller: c[i],
                          keyboardType: i >= 3
                              ? TextInputType.numberWithOptions(decimal: i == 4 && unit != 'عدد')
                              : TextInputType.text,
                          inputFormatters: i == 3 || i >= 5 || (i == 4 && unit == 'عدد')
                              ? [FilteringTextInputFormatter.digitsOnly]
                              : i == 4
                                  ? [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}'))]
                                  : const [],
                          textInputAction: TextInputAction.next,
                          onChanged: (_) => refresh(() {}),
                          decoration: InputDecoration(labelText: names[i]),
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
                          Text('مبلغ ارزش افزوده: ${(vatIncluded ? number(c[5]) * number(c[4]) * number(vatRate) / 100 : 0).toStringAsFixed(0)} تومان'),
                          Text('جمع کل خرید و هزینه‌ها: ${totalCost().toStringAsFixed(0)} تومان'),
                          Text('بهای تمام‌شده هر واحد: ${((number(c[4]) > 0) ? totalCost() / number(c[4]) : 0).toStringAsFixed(0)} تومان'),
                          const Text('هزینه‌ها به نسبت تعداد، بین کالاها سرشکن می‌شوند.', style: TextStyle(fontSize: 11, color: Colors.black54)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')),
              FilledButton(
                onPressed: () {
                  if (c[0].text.trim().isEmpty) return;
                  final qty = number(c[4]);
                  final total = totalCost();
                  final item = <String, String>{};
                  for (int i = 0; i < names.length; i++) { item[names[i]] = c[i].text.trim(); }
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
            ],
          ),
        ),
      ),
    );
    for (final x in [...c, shipping, freight, other, vatRate]) { x.dispose(); }
    if (saved == true && mounted) { setState(() {}); widget.onChanged(); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton(
          heroTag: 'add-product', backgroundColor: yellow, foregroundColor: black,
          onPressed: addProduct, child: const Icon(Icons.add),
        ),
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [

            if (DemoStore.products.isEmpty)
              const Padding(padding: EdgeInsets.all(28), child: Center(child: Text('هنوز کالایی ثبت نشده است'))),
            for (final item in DemoStore.products.reversed)
              Card(child: ListTile(
                leading: (item['تصویر کالا'] ?? '').isNotEmpty
                    ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(base64Decode(item['تصویر کالا']!), width: 48, height: 48, fit: BoxFit.cover))
                    : const CircleAvatar(child: Icon(Icons.inventory_2)),
                title: Text(item['نام کالا'] ?? 'بدون نام'),
                subtitle: Text('موجودی: ${item['موجودی'] ?? '0'} ${item['واحد شمارش'] ?? 'عدد'}  •  ${item['وضعیت کالا'] ?? 'نو'}  •  بهای تمام‌شده هر واحد: ${item['بهای تمام‌شده هر واحد'] ?? '0'} تومان'),
              )),
          ],
        ),
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
    fontScale = AppSettings.fontScale;
  }

  @override
  void dispose() {
    storeName.dispose();
    managerName.dispose();
    phone.dispose();
    address.dispose();
    postalCode.dispose();
    super.dispose();
  }

  Future<void> saveSettings() async {
    await AppSettings.save(
      newStoreName: storeName.text,
      newManagerName: managerName.text,
      newPhone: phone.text,
      newAddress: address.text,
      newPostalCode: postalCode.text,
      newDarkMode: darkMode,
      newFontScale: fontScale,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تنظیمات با موفقیت ذخیره شد')),
    );
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
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'شماره تماس فروشگاه')),
          const SizedBox(height: 10),
          TextField(controller: address, maxLines: 2, decoration: const InputDecoration(labelText: 'آدرس فروشگاه')),
          const SizedBox(height: 10),
          TextField(controller: postalCode, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'کد پستی')),
          const Divider(height: 32),
          const Text('تنظیمات ظاهری', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('حالت تیره'),
            value: darkMode,
            onChanged: (value) => setState(() => darkMode = value),
          ),
          Text('اندازه نوشته‌ها: ${(fontScale * 100).round()}٪'),
          Slider(
            value: fontScale,
            min: 0.85,
            max: 1.25,
            divisions: 8,
            label: '${(fontScale * 100).round()}٪',
            onChanged: (value) => setState(() => fontScale = value),
          ),
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
