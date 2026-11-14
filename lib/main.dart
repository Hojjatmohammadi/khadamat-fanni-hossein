import 'dart:convert';
import 'package:material_ui/material_ui.dart';
import 'backup_service.dart';
import 'backup_page.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'app_database.dart';
import 'trade_repository.dart';
import 'accounting_repository.dart';
import 'financial_management_page.dart';
import 'party_repository.dart';
import 'check_repository.dart';
import 'party_ledger_page.dart';
import 'checks_page.dart';
import 'jalali_date_field.dart';
import 'check_reminder_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DemoStore.init();
  final reminders = CheckReminderService();
  try {
    await reminders.initialize();
    await reminders.notifyDueChecks(DemoStore.checks);
  } catch (error) {
    // Notification permission or platform support must never block app startup.
  }
  runApp(const HoseinApp());
}

const yellow = Color(0xFFFFD400);
const black = Color(0xFF171717);

class HoseinApp extends StatelessWidget {
  const HoseinApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'خدمات فنی حسین',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: yellow, brightness: Brightness.light),
          scaffoldBackgroundColor: const Color(0xFFF7F7F7),
          appBarTheme: const AppBarTheme(backgroundColor: black, foregroundColor: yellow),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        home: const HomePage(),
      );
}

class DemoStore {
  static final AppDatabase _database = AppDatabase();
  static final TradeRepository trades = TradeRepository(_database);
  static final AccountingRepository accounting = AccountingRepository(_database);
  static final PartyRepository parties = PartyRepository(_database);
  static final CheckRepository checks = CheckRepository(_database);
  static final BackupService backups = BackupService(_database);
  static String? backupStartupNotice;
  static final products = <Map<String, String>>[];
  static final customers = <Map<String, String>>[];
  static final repairs = <Map<String, String>>[];
  static final sales = <Map<String, String>>[];

  static Future<void> init() async {
    await _database.database;
    await _loadCategory('products', products);
    await _loadCategory('customers', customers);
    await _loadCategory('repairs', repairs);
    await refreshSales();
    try {
      final dailyBackup = await backups.createDailyBackupIfDue();
      backupStartupNotice = dailyBackup == null
          ? 'نسخه پشتیبان روزانه امروز از قبل موجود است.'
          : 'نسخه پشتیبان روزانه امروز به‌صورت خودکار ایجاد شد.';
    } catch (error) {
      backupStartupNotice = 'هشدار: پشتیبان روزانه ایجاد نشد: $error';
    }
  }

  static Future<void> refreshProducts() => _loadCategory('products', products);

  static Future<void> refreshSales() async {
    final storedSales = await _database.getAll('sales');
    final invoices = await trades.getDocuments(type: 'sale');
    sales
      ..clear()
      ..addAll(storedSales)
      ..addAll(invoices.map((row) => {
        'شماره فاکتور': row['document_number']?.toString() ?? '',
        'نام مشتری': row['counterparty_name']?.toString() ?? '',
        'تاریخ': row['document_date']?.toString() ?? '',
        'مبلغ کل': row['total_amount']?.toString() ?? '0',
        '__database_id': row['id']?.toString() ?? '',
      }));
  }

  static Future<void> _loadCategory(
    String category,
    List<Map<String, String>> target,
  ) async {
    final rows = await _database.getAll(category);
    if (category == 'products') {
      for (final item in rows) {
        final databaseId = int.tryParse(item['__database_id'] ?? '');
        if (databaseId != null) {
          item['موجودی'] = (await _database.getStockOnHand(databaseId)).toString();
        }
      }
    }
    target
      ..clear()
      ..addAll(rows);
  }

  static Future<void> add(
    String category,
    Map<String, String> item,
  ) async {
    final target = switch (category) {
      'products' => products,
      'customers' => customers,
      'repairs' => repairs,
      'sales' => sales,
      _ => throw ArgumentError('دسته اطلاعات نامعتبر است'),
    };

    final id = await _database.insert(category, item);
    final saved = Map<String, String>.from(item)
      ..['__database_id'] = id.toString();
    if (category == 'products') {
      saved['موجودی'] = (await _database.getStockOnHand(id)).toString();
    }
    if (category == 'customers') {
      await parties.ensureParty(
        PartyDraft(
          partyType: 'customer',
          preferredId: 'customer:$id',
          displayName: item['نام مشتری'] ?? item['نام'] ?? 'مشتری $id',
          phone: item['شماره تماس'],
          address: item['آدرس'],
          notes: item['توضیحات'],
          sourceCategory: 'customers',
          sourceId: id.toString(),
        ),
      );
    }
    target.add(saved);
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
  final titles = const ['داشبورد', 'انبار کالا', 'خرید و برگشت', 'مشتریان', 'تعمیرات', 'فروش و فاکتور', 'دفتر گردش اشخاص', 'مدیریت چک‌ها', 'گزارش‌ها', 'دفتر روزنامه و هزینه‌ها', 'پشتیبان‌گیری و بازیابی'];

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
      PurchasePage(onChanged: () => setState(() {})),
      CustomerPage(onChanged: () => setState(() {})),
      RepairPage(onChanged: () => setState(() {})),
      SalesPage(onChanged: () => setState(() {})),
      PartyLedgerPage(repository: DemoStore.parties),
      CheckPage(
        checks: DemoStore.checks,
        parties: DemoStore.parties,
        trades: DemoStore.trades,
        onChanged: () => setState(() {}),
      ),
      const ReportsPage(),
      FinancialManagementPage(repository: DemoStore.accounting),
      BackupPage(
        service: DemoStore.backups,
        initialMessage: DemoStore.backupStartupNotice,
      ),
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
                      const Text('خدمات فنی حسین', style: TextStyle(color: yellow, fontSize: 22, fontWeight: FontWeight.bold)),
                      Text('نسخه آزمایشی', style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
                for (int i = 0; i < titles.length; i++)
                  ListTile(
                    leading: Icon([Icons.dashboard, Icons.inventory_2, Icons.shopping_bag, Icons.people, Icons.build, Icons.receipt_long, Icons.account_balance, Icons.request_quote, Icons.bar_chart, Icons.menu_book, Icons.backup][i]),
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
      ('کالاهای ثبت‌شده', DemoStore.products.length.toString(), Icons.inventory_2),
      ('مشتریان', DemoStore.customers.length.toString(), Icons.people),
      ('پذیرش تعمیرات', DemoStore.repairs.length.toString(), Icons.build),
      ('فاکتورهای فروش', DemoStore.sales.length.toString(), Icons.receipt),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: black, borderRadius: BorderRadius.circular(18)),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  'assets/logo.jpg',
                  width: 62,
                  height: 62,
                  fit: BoxFit.cover,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('خدمات فنی حسین', style: TextStyle(color: yellow, fontWeight: FontWeight.bold, fontSize: 20)),
                    Text('مدیریت فروشگاه و تعمیرات', style: TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
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
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const Text('دسترسی سریع', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        for (final e in [(1, 'ثبت کالا'), (2, 'ثبت خرید'), (3, 'ثبت مشتری'), (4, 'پذیرش تعمیر'), (5, 'صدور فاکتور'), (6, 'دفتر گردش اشخاص'), (7, 'مدیریت چک‌ها'), (9, 'دفتر روزنامه و هزینه‌ها')])
          Card(
            child: ListTile(
              title: Text(e.$2),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => onSelect(e.$1),
            ),
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
                if (item.values.any((value) => value.isNotEmpty)) {
                  final category = widget.title == 'مشتری' ? 'customers' : widget.title == 'پذیرش تعمیر' ? 'repairs' : 'sales';
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
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: addItem,
                icon: const Icon(Icons.add),
                label: const Text('ثبت مورد جدید'),
              ),
            ),
            const SizedBox(height: 8),
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
                    item.entries.where((e) => !e.key.startsWith('__') && e.value.isNotEmpty).map((e) => '${e.key}: ${e.value}').join(' • '),
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
                    for (int i = 0; i < names.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: TextField(
                          controller: c[i],
                          keyboardType: i >= 4 ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
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
                    TextField(controller: shipping, keyboardType: TextInputType.number, onChanged: (_) => refresh(() {}), decoration: const InputDecoration(labelText: 'هزینه پست')),
                    const SizedBox(height: 10),
                    TextField(controller: freight, keyboardType: TextInputType.number, onChanged: (_) => refresh(() {}), decoration: const InputDecoration(labelText: 'هزینه باربری / حمل')),
                    const SizedBox(height: 10),
                    TextField(controller: other, keyboardType: TextInputType.number, onChanged: (_) => refresh(() {}), decoration: const InputDecoration(labelText: 'سایر هزینه‌های خرید')),
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
            Align(alignment: Alignment.centerLeft, child: FilledButton.icon(onPressed: addProduct, icon: const Icon(Icons.add), label: const Text('ثبت کالا'))),
            const SizedBox(height: 8),
            if (DemoStore.products.isEmpty)
              const Padding(padding: EdgeInsets.all(28), child: Center(child: Text('هنوز کالایی ثبت نشده است'))),
            for (final item in DemoStore.products.reversed)
              Card(child: ListTile(
                leading: (item['تصویر کالا'] ?? '').isNotEmpty
                    ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(base64Decode(item['تصویر کالا']!), width: 48, height: 48, fit: BoxFit.cover))
                    : const CircleAvatar(child: Icon(Icons.inventory_2)),
                title: Text(item['نام کالا'] ?? 'بدون نام'),
                subtitle: Text('موجودی: ${item['موجودی'] ?? '0'}  •  بهای تمام‌شده هر واحد: ${item['بهای تمام‌شده هر واحد'] ?? '0'} تومان'),
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

class RepairPage extends StatefulWidget {
  final VoidCallback onChanged;
  const RepairPage({super.key, required this.onChanged});

  @override
  State<RepairPage> createState() => _RepairPageState();
}

class _RepairPageState extends State<RepairPage> {
  Future<void> _recordPartConsumption() async {
    final repairOptions = DemoStore.repairs
        .where((item) => int.tryParse(item['__database_id'] ?? '') != null)
        .toList();
    final productOptions = DemoStore.products
        .where((item) => int.tryParse(item['__database_id'] ?? '') != null)
        .toList();

    if (repairOptions.isEmpty || productOptions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ابتدا پذیرش تعمیر و کالا را ثبت کنید')),
      );
      return;
    }

    int? selectedRepairId =
        int.tryParse(repairOptions.first['__database_id'] ?? '');
    int? selectedProductId =
        int.tryParse(productOptions.first['__database_id'] ?? '');
    final quantityController = TextEditingController(text: '1');

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('ثبت مصرف قطعه در تعمیر'),
            content: SizedBox(
              width: 380,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      key: ValueKey(selectedRepairId),
                      initialValue: selectedRepairId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'پذیرش تعمیر'),
                      items: [
                        for (final repair in repairOptions)
                          DropdownMenuItem(
                            value: int.parse(repair['__database_id']!),
                            child: Text(
                              '${repair['نوع دستگاه'] ?? 'دستگاه'} — ${repair['نام مشتری'] ?? 'بدون نام'}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) =>
                          refresh(() => selectedRepairId = value),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      key: ValueKey(selectedProductId),
                      initialValue: selectedProductId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'قطعه مصرفی'),
                      items: [
                        for (final product in productOptions)
                          DropdownMenuItem(
                            value: int.parse(product['__database_id']!),
                            child: Text(
                              '${product['نام کالا'] ?? 'کالای بدون نام'} — موجودی: ${product['موجودی'] ?? '0'}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) =>
                          refresh(() => selectedProductId = value),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: quantityController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'تعداد مصرفی'),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'هزینه قطعه بر اساس میانگین بهای موجودی محاسبه و به هزینه قطعات مصرفی تعمیر منتقل می‌شود.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('انصراف'),
              ),
              FilledButton(
                onPressed: () async {
                  final quantity = double.tryParse(quantityController.text.trim());
                  if (selectedRepairId == null ||
                      selectedProductId == null ||
                      quantity == null ||
                      quantity <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('اطلاعات مصرف قطعه را بررسی کنید')),
                    );
                    return;
                  }
                  final repair = repairOptions.firstWhere(
                    (item) => item['__database_id'] == selectedRepairId.toString(),
                  );
                  try {
                    await DemoStore.trades.recordRepairConsumption(
                      documentDate: DateTime.now().toIso8601String().split('T').first,
                      repairId: selectedRepairId.toString(),
                      customerName: repair['نام مشتری'] ?? 'مشتری تعمیر',
                      customerId: null,
                      idempotencyKey:
                          'repair-parts-${selectedRepairId}-${DateTime.now().microsecondsSinceEpoch}',
                      parts: [
                        TradeLineDraft(
                          productId: selectedProductId!,
                          quantity: quantity,
                          unitPrice: 0,
                        ),
                      ],
                    );
                    await DemoStore.refreshProducts();
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext, true);
                    }
                  } catch (error) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('ثبت مصرف قطعه ناموفق بود: $error')),
                    );
                  }
                },
                child: const Text('ثبت مصرف قطعه'),
              ),
            ],
          ),
        ),
      ),
    );

    quantityController.dispose();
    if (saved == true && mounted) {
      widget.onChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('مصرف قطعه و سند حسابداری ثبت شد')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Expanded(
            child: SimpleListPage(
              title: 'پذیرش تعمیر',
              data: DemoStore.repairs,
              fields: const ['نام مشتری', 'نوع دستگاه', 'شرح عیب', 'اجرت', 'وضعیت تعمیر'],
              primary: 'نوع دستگاه',
              onChanged: widget.onChanged,
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _recordPartConsumption,
                  icon: const Icon(Icons.inventory),
                  label: const Text('ثبت مصرف قطعه در تعمیر'),
                ),
              ),
            ),
          ),
        ],
      );
}

class PurchasePage extends StatelessWidget {
  final VoidCallback onChanged;
  const PurchasePage({super.key, required this.onChanged});

  @override
  Widget build(BuildContext context) => TradeEntryPage(
        documentType: 'purchase',
        onChanged: onChanged,
      );
}

class SalesPage extends StatelessWidget {
  final VoidCallback onChanged;
  const SalesPage({super.key, required this.onChanged});

  @override
  Widget build(BuildContext context) => TradeEntryPage(
        documentType: 'sale',
        onChanged: onChanged,
      );
}

class TradeEntryPage extends StatefulWidget {
  final String documentType;
  final VoidCallback onChanged;

  const TradeEntryPage({
    super.key,
    required this.documentType,
    required this.onChanged,
  });

  @override
  State<TradeEntryPage> createState() => _TradeEntryPageState();
}

class _TradeEntryPageState extends State<TradeEntryPage> {
  final _partyController = TextEditingController();
  DateTime _documentDate = DateTime.now();
  final _quantityController = TextEditingController(text: '1');
  final _priceController = TextEditingController();
  final _discountController = TextEditingController(text: '0');
  final _vatRateController = TextEditingController(text: '0');
  final _paidController = TextEditingController(text: '0');
  final _shippingController = TextEditingController(text: '0');
  final _freightController = TextEditingController(text: '0');
  final _otherCostController = TextEditingController(text: '0');

  final List<TradeLineDraft> _lines = [];
  List<Map<String, Object?>> _documents = [];
  List<Map<String, Object?>> _partyOptions = [];
  String? _selectedPartyId;
  int? _selectedProductId;
  String _cashAccountCode = '1000';
  bool _vatExempt = false;
  bool _saving = false;

  bool get _isPurchase => widget.documentType == 'purchase';
  String get _partyLabel => _isPurchase ? 'نام فروشنده' : 'نام مشتری';
  String get _pageTitle => _isPurchase ? 'ثبت فاکتور خرید' : 'ثبت فاکتور فروش';

  @override
  void initState() {
    super.initState();
    _selectedProductId = _firstProductId();
    _loadDocuments();
    _loadParties();
  }

  @override
  void dispose() {
    _partyController.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    _discountController.dispose();
    _vatRateController.dispose();
    _paidController.dispose();
    _shippingController.dispose();
    _freightController.dispose();
    _otherCostController.dispose();
    super.dispose();
  }

  int? _firstProductId() {
    for (final product in DemoStore.products) {
      final id = int.tryParse(product['__database_id'] ?? '');
      if (id != null) return id;
    }
    return null;
  }

  int _int(TextEditingController controller) {
    return int.tryParse(controller.text.replaceAll(',', '').trim()) ?? 0;
  }

  double _double(TextEditingController controller) {
    return double.tryParse(controller.text.replaceAll(',', '').trim()) ?? 0;
  }

  String _productName(int id) {
    for (final product in DemoStore.products) {
      if (product['__database_id'] == id.toString()) {
        return product['نام کالا'] ?? 'کالای شماره $id';
      }
    }
    return 'کالای شماره $id';
  }

  int get _subtotal => _lines.fold<int>(
        0,
        (sum, line) => sum + (line.quantity * line.unitPrice).round(),
      );

  int get _previewTotal {
    final net = (_subtotal - _int(_discountController)).clamp(0, _subtotal);
    final charges = _isPurchase
        ? _int(_shippingController) + _int(_freightController) + _int(_otherCostController)
        : 0;
    final vat = _vatExempt ? 0 : (net * _double(_vatRateController) / 100).round();
    return net + charges + vat;
  }

  Future<void> _loadParties() async {
    final rows = await DemoStore.parties.getParties(
      partyType: _isPurchase ? 'supplier' : 'customer',
    );
    if (mounted) setState(() => _partyOptions = rows);
  }

  Future<void> _loadDocuments() async {
    final rows = await DemoStore.trades.getDocuments(type: widget.documentType);
    final documents = <Map<String, Object?>>[];
    for (final row in rows) {
      final id = (row['id'] as num).toInt();
      final outstanding = await DemoStore.trades.getOutstandingAmount(id);
      documents.add({...row, 'outstanding_amount': outstanding});
    }
    if (mounted) setState(() => _documents = documents);
  }

  void _addLine() {
    final productId = _selectedProductId;
    final quantity = _double(_quantityController);
    final price = _int(_priceController);
    if (productId == null || quantity <= 0 || price < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('کالا، تعداد و قیمت را بررسی کنید')),
      );
      return;
    }
    setState(() {
      _lines.add(TradeLineDraft(
        productId: productId,
        quantity: quantity,
        unitPrice: price,
      ));
      _quantityController.text = '1';
      _priceController.clear();
    });
  }

  Future<void> _saveDocument() async {
    if (_saving) return;
    if (_partyController.text.trim().isEmpty || _lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('نام شخص، تاریخ و حداقل یک ردیف کالا الزامی است')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final partyName = _partyController.text.trim();
      final partyId = await DemoStore.parties.ensureParty(
        PartyDraft(
          partyType: _isPurchase ? 'supplier' : 'customer',
          displayName: partyName,
          preferredId: _selectedPartyId,
        ),
      );
      final draft = TradeDocumentDraft(
        documentDate: _documentDate.toIso8601String().split('T').first,
        counterpartyName: partyName,
        counterpartyId: partyId,
        idempotencyKey:
            '${widget.documentType}-${DateTime.now().microsecondsSinceEpoch}',
        lines: List<TradeLineDraft>.from(_lines),
        discountAmount: _int(_discountController),
        shippingCost: _isPurchase ? _int(_shippingController) : 0,
        freightCost: _isPurchase ? _int(_freightController) : 0,
        otherCost: _isPurchase ? _int(_otherCostController) : 0,
        vatRate: _double(_vatRateController),
        vatExempt: _vatExempt,
        paidAmount: _int(_paidController),
        cashAccountCode: _cashAccountCode,
      );
      if (_isPurchase) {
        await DemoStore.trades.recordPurchase(draft);
      } else {
        await DemoStore.trades.recordSale(draft);
      }
      await DemoStore.refreshProducts();
      await DemoStore.refreshSales();
      await _loadDocuments();
      await _loadParties();
      if (!mounted) return;
      setState(() {
        _lines.clear();
        _documentDate = DateTime.now();
        _partyController.clear();
        _selectedPartyId = null;
        _discountController.text = '0';
        _vatRateController.text = '0';
        _paidController.text = '0';
        _shippingController.text = '0';
        _freightController.text = '0';
        _otherCostController.text = '0';
        _vatExempt = false;
      });
      widget.onChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isPurchase ? 'فاکتور خرید ثبت شد' : 'فاکتور فروش ثبت شد')),
      );
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ثبت فاکتور ناموفق بود: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _returnDocument(Map<String, Object?> document) async {
    final documentId = (document['id'] as num).toInt();
    final lines = await DemoStore.trades.getDocumentLines(documentId);
    if (lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('برای این فاکتور ردیف کالایی پیدا نشد')),
      );
      return;
    }

    int? selectedLineId = (lines.first['id'] as num).toInt();
    final quantityController = TextEditingController(text: '1');
    final returnLine = await showDialog<ReturnLineDraft?>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text(_isPurchase ? 'برگشت از خرید' : 'برگشت از فروش'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    key: ValueKey(selectedLineId),
                    initialValue: selectedLineId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'ردیف فاکتور'),
                    items: [
                      for (final line in lines)
                        DropdownMenuItem(
                          value: (line['id'] as num).toInt(),
                          child: Text(
                            '${line['product_name']} — تعداد: ${line['quantity']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) => refresh(() => selectedLineId = value),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: quantityController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'تعداد مرجوعی'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('انصراف'),
              ),
              FilledButton(
                onPressed: () {
                  final quantity = double.tryParse(quantityController.text.trim());
                  if (selectedLineId == null || quantity == null || quantity <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('ردیف و تعداد مرجوعی را بررسی کنید')),
                    );
                    return;
                  }
                  Navigator.pop(
                    dialogContext,
                    ReturnLineDraft(sourceLineId: selectedLineId!, quantity: quantity),
                  );
                },
                child: const Text('ادامه'),
              ),
            ],
          ),
        ),
      ),
    );
    quantityController.dispose();
    if (returnLine == null || !mounted) return;

    try {
      final draft = ReturnDocumentDraft(
        documentDate: DateTime.now().toIso8601String().split('T').first,
        sourceDocumentId: documentId,
        counterpartyName: document['counterparty_name']?.toString() ?? 'شخص',
        counterpartyId: document['counterparty_id']?.toString(),
        idempotencyKey:
            'return-${documentId}-${DateTime.now().microsecondsSinceEpoch}',
        lines: [returnLine],
      );
      if (_isPurchase) {
        await DemoStore.trades.recordSupplierReturn(draft);
      } else {
        await DemoStore.trades.recordCustomerReturn(draft);
      }
      await DemoStore.refreshProducts();
      await _loadDocuments();
      widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('برگشت کالا و ثبت‌های حسابداری انجام شد')),
        );
      }
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ثبت برگشت ناموفق بود: $error')),
      );
    }
  }

  Future<void> _settleDocument(Map<String, Object?> document) async {
    final outstanding = (document['outstanding_amount'] as num?)?.toInt() ?? 0;
    if (outstanding <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('این فاکتور مانده‌ای برای تسویه ندارد')),
      );
      return;
    }
    final amountController = TextEditingController(text: outstanding.toString());
    String accountCode = '1000';
    final amount = await showDialog<int?>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text(_isPurchase ? 'ثبت پرداخت به فروشنده' : 'ثبت دریافت از مشتری'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'مبلغ',
                    helperText: 'مانده فاکتور: $outstanding تومان',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: accountCode,
                  decoration: const InputDecoration(labelText: 'محل دریافت / پرداخت'),
                  items: const [
                    DropdownMenuItem(value: '1000', child: Text('صندوق')),
                    DropdownMenuItem(value: '1010', child: Text('بانک')),
                  ],
                  onChanged: (value) => refresh(() => accountCode = value ?? '1000'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('انصراف'),
              ),
              FilledButton(
                onPressed: () {
                  final value = int.tryParse(amountController.text.trim());
                  if (value == null || value <= 0 || value > outstanding) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('مبلغ باید از صفر بیشتر و حداکثر برابر مانده فاکتور باشد')),
                    );
                    return;
                  }
                  Navigator.pop(dialogContext, value);
                },
                child: const Text('ثبت'),
              ),
            ],
          ),
        ),
      ),
    );
    amountController.dispose();
    if (amount == null || !mounted) return;

    try {
      final draft = PartyPaymentDraft(
        documentDate: DateTime.now().toIso8601String().split('T').first,
        counterpartyName: document['counterparty_name']?.toString() ?? 'شخص',
        counterpartyId: document['counterparty_id']?.toString(),
        amount: amount,
        idempotencyKey:
            'settlement-${document['id']}-${DateTime.now().microsecondsSinceEpoch}',
        cashAccountCode: accountCode,
        referenceId: document['id'].toString(),
      );
      if (_isPurchase) {
        await DemoStore.trades.recordSupplierPayment(draft);
      } else {
        await DemoStore.trades.recordCustomerReceipt(draft);
      }
      await _loadDocuments();
      widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تسویه و سند دریافت / پرداخت ثبت شد')),
        );
      }
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ثبت تسویه ناموفق بود: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = DemoStore.products
        .where((item) => int.tryParse(item['__database_id'] ?? '') != null)
        .toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(_pageTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
          const SizedBox(height: 12),
          if (_partyOptions.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: _selectedPartyId,
              isExpanded: true,
              decoration: InputDecoration(labelText: 'انتخاب از اشخاص ثبت‌شده ($_partyLabel)'),
              items: [
                for (final party in _partyOptions)
                  DropdownMenuItem(
                    value: party['id'] as String,
                    child: Text(
                      '${party['display_name']}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedPartyId = value;
                  if (value != null) {
                    final selected = _partyOptions.firstWhere((p) => p['id'] == value);
                    _partyController.text = selected['display_name']?.toString() ?? '';
                  }
                });
              },
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _partyController,
            decoration: InputDecoration(labelText: _partyLabel),
            onChanged: (value) {
              if (_selectedPartyId != null) {
                final selected = _partyOptions.firstWhere(
                  (p) => p['id'] == _selectedPartyId,
                );
                if (value.trim() != selected['display_name']?.toString()) {
                  setState(() => _selectedPartyId = null);
                }
              }
            },
          ),
          const SizedBox(height: 10),
          JalaliDateField(
            initialDate: _documentDate,
            label: 'تاریخ فاکتور (شمسی)',
            onChanged: (date) => setState(() => _documentDate = date),
          ),
          const SizedBox(height: 10),
          if (products.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('برای ثبت فاکتور، ابتدا کالا را در انبار ثبت کنید'),
            )
          else
            DropdownButtonFormField<int>(
              key: ValueKey(_selectedProductId),
              initialValue: _selectedProductId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'انتخاب کالا'),
              items: [
                for (final product in products)
                  DropdownMenuItem(
                    value: int.parse(product['__database_id']!),
                    child: Text(
                      '${product['نام کالا'] ?? 'کالای بدون نام'} — موجودی: ${product['موجودی'] ?? '0'}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _selectedProductId = value),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _quantityController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'تعداد'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _priceController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: _isPurchase ? 'قیمت خرید واحد' : 'قیمت فروش واحد'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: products.isEmpty ? null : _addLine,
            icon: const Icon(Icons.add),
            label: const Text('افزودن کالا به فاکتور'),
          ),
          if (_lines.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (var i = 0; i < _lines.length; i++)
              Card(
                child: ListTile(
                  title: Text(_productName(_lines[i].productId)),
                  subtitle: Text(
                    'تعداد: ${_lines[i].quantity} × ${_lines[i].unitPrice} تومان',
                  ),
                  trailing: IconButton(
                    tooltip: 'حذف ردیف',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() => _lines.removeAt(i)),
                  ),
                ),
              ),
          ],
          const Divider(height: 24),
          TextField(
            controller: _discountController,
            onChanged: (_) => setState(() {}),
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'تخفیف کل (تومان)'),
          ),
          const SizedBox(height: 10),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _vatExempt,
            title: const Text('معاف از ارزش افزوده'),
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (value) => setState(() => _vatExempt = value ?? false),
          ),
          if (!_vatExempt)
            TextField(
              controller: _vatRateController,
              onChanged: (_) => setState(() {}),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'درصد ارزش افزوده'),
            ),
          if (_isPurchase) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _shippingController,
              onChanged: (_) => setState(() {}),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'هزینه پست'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _freightController,
              onChanged: (_) => setState(() {}),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'هزینه باربری / حمل'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _otherCostController,
              onChanged: (_) => setState(() {}),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'سایر هزینه‌های خرید'),
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _paidController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'مبلغ پرداخت‌شده هنگام ثبت'),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _cashAccountCode,
            decoration: const InputDecoration(labelText: 'صندوق یا بانک'),
            items: const [
              DropdownMenuItem(value: '1000', child: Text('صندوق')),
              DropdownMenuItem(value: '1010', child: Text('بانک')),
            ],
            onChanged: (value) => setState(() => _cashAccountCode = value ?? '1000'),
          ),
          const SizedBox(height: 12),
          Card(
            color: const Color(0xFFFFF4CC),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('پیش‌نمایش مبلغ', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('جمع ردیف‌ها: $_subtotal تومان'),
                  Text('مبلغ تقریبی فاکتور: $_previewTotal تومان'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _saving ? null : _saveDocument,
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save),
            label: Text(_saving ? 'در حال ثبت...' : 'ثبت قطعی فاکتور'),
          ),
          const Divider(height: 32),
          Text(
            _isPurchase ? 'فاکتورهای خرید ثبت‌شده' : 'فاکتورهای فروش ثبت‌شده',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          if (_documents.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: Text('هنوز فاکتوری ثبت نشده است')),
            ),
          for (final document in _documents)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${document['document_number']} — ${document['counterparty_name']}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text('تاریخ: ${formatJalaliDate(DateTime.parse(document['document_date'] as String))}'),
                    Text('مبلغ: ${document['total_amount']} تومان  •  پرداخت اولیه: ${document['paid_amount']} تومان'),
                    Text('مانده: ${document['outstanding_amount']} تومان'),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        TextButton.icon(
                          onPressed: () => _returnDocument(document),
                          icon: const Icon(Icons.assignment_return),
                          label: const Text('برگشت کالا'),
                        ),
                        TextButton.icon(
                          onPressed: (document['outstanding_amount'] as num).toInt() > 0
                              ? () => _settleDocument(document)
                              : null,
                          icon: const Icon(Icons.payments_outlined),
                          label: Text(_isPurchase ? 'ثبت پرداخت' : 'ثبت دریافت'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
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
