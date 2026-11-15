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
import 'product_duplicate_checker.dart';
import 'localized_number.dart';
import 'invoice_archive_repository.dart';
import 'invoice_settings_repository.dart';
import 'reports_page.dart';
import 'invoice_pdf_service.dart';

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
          colorScheme: ColorScheme.fromSeed(
            seedColor: yellow,
            brightness: Brightness.light,
          ).copyWith(
            primary: black,
            onPrimary: yellow,
            secondary: yellow,
            onSecondary: black,
            tertiary: const Color(0xFFB58B00),
            surface: Colors.white,
          ),
          scaffoldBackgroundColor: const Color(0xFFF5F5F5),
          canvasColor: Colors.white,
          cardColor: Colors.white,
          dividerColor: const Color(0xFFE5E1D5),
          appBarTheme: const AppBarTheme(
            backgroundColor: black,
            foregroundColor: yellow,
            surfaceTintColor: Colors.transparent,
            elevation: 1,
            centerTitle: false,
            iconTheme: IconThemeData(color: yellow),
            actionsIconTheme: IconThemeData(color: yellow),
          ),
          drawerTheme: const DrawerThemeData(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            width: 304,
          ),
          listTileTheme: const ListTileThemeData(
            iconColor: black,
            textColor: black,
            selectedColor: black,
            selectedTileColor: Color(0xFFFFF4BF),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFD6D1C5)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFD6D1C5)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: yellow, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFB3261E)),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFB3261E), width: 2),
            ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: black,
              foregroundColor: yellow,
              disabledBackgroundColor: const Color(0xFFE0E0E0),
              disabledForegroundColor: const Color(0xFF777777),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: yellow,
              foregroundColor: black,
              disabledBackgroundColor: const Color(0xFFE0E0E0),
              disabledForegroundColor: const Color(0xFF777777),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              foregroundColor: black,
              side: const BorderSide(color: black, width: 1.2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            ),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          checkboxTheme: CheckboxThemeData(
            fillColor: WidgetStateProperty.resolveWith((states) =>
                states.contains(WidgetState.selected) ? yellow : Colors.white),
            checkColor: WidgetStateProperty.all(black),
            side: const BorderSide(color: black),
          ),
          radioTheme: RadioThemeData(
            fillColor: WidgetStateProperty.resolveWith((states) =>
                states.contains(WidgetState.selected) ? black : Colors.grey),
          ),
          switchTheme: SwitchThemeData(
            thumbColor: WidgetStateProperty.resolveWith((states) =>
                states.contains(WidgetState.selected) ? black : Colors.white),
            trackColor: WidgetStateProperty.resolveWith((states) =>
                states.contains(WidgetState.selected) ? yellow : Colors.grey.shade300),
          ),
          progressIndicatorTheme: const ProgressIndicatorThemeData(
            color: Color(0xFFB58B00),
          ),
          snackBarTheme: SnackBarThemeData(
            backgroundColor: black,
            contentTextStyle: const TextStyle(color: Colors.white),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          dialogTheme: DialogThemeData(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            titleTextStyle: const TextStyle(
              color: black,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          popupMenuTheme: PopupMenuThemeData(
            color: Colors.white,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
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
  static final InvoiceArchiveRepository invoiceArchives = InvoiceArchiveRepository(_database);
  static final InvoiceSettingsRepository invoiceSettings = InvoiceSettingsRepository(_database);
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

  static Future<void> updateProduct(
    int productId,
    Map<String, String> changes,
  ) async {
    final current = products.firstWhere(
      (item) => item['__database_id'] == productId.toString(),
      orElse: () => throw StateError('کالا پیدا نشد'),
    );
    final updated = Map<String, String>.from(current)..addAll(changes);
    // Stock is ledger-derived and cannot be edited from the product form.
    updated['موجودی'] = current['موجودی'] ?? '0';
    await _database.updateRecord('products', productId, updated);
    await refreshProducts();
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

  Future<List<Map<String, Object>>> _globalSearchEntries() async {
    final entries = <Map<String, Object>>[];
    void addRows({required int tab, required String category, required Iterable<Map<String, Object?>> rows, required List<String> labels}) {
      for (final row in rows) {
        final values = row.entries.where((e) => !e.key.startsWith('__') && e.value != null).map((e) => '${e.key}: ${e.value}').toList();
        final label = labels.map((key) => row[key]?.toString().trim() ?? '').firstWhere((v) => v.isNotEmpty, orElse: () => category);
        entries.add({'tab': tab, 'category': category, 'label': label, 'details': values.take(3).join(' • '), 'searchText': row.values.where((v) => v != null).join(' ').toLowerCase()});
      }
    }
    addRows(tab: 1, category: 'کالا', rows: DemoStore.products, labels: const ['نام کالا', 'کد کالا']);
    addRows(tab: 3, category: 'مشتری', rows: DemoStore.customers, labels: const ['نام مشتری', 'نام', 'شماره تماس']);
    addRows(tab: 4, category: 'پذیرش تعمیر', rows: DemoStore.repairs, labels: const ['نام مشتری', 'نام دستگاه', 'نوع دستگاه']);
    final docs = await DemoStore.trades.getDocuments();
    for (final doc in docs) {
      final type = doc['document_type']?.toString() ?? '';
      final targetTab = (type == 'purchase' || type == 'supplier_return') ? 2 : 5;
      final category = switch (type) {'purchase' => 'فاکتور خرید', 'sale' => 'فاکتور فروش', 'supplier_return' => 'برگشت از خرید', 'customer_return' => 'برگشت از فروش', _ => 'سند تجاری'};
      final id = int.tryParse(doc['id']?.toString() ?? '');
      final lines = id == null ? <Map<String, Object?>>[] : await DemoStore.trades.getDocumentLines(id);
      final searchable = [...doc.values.map((v) => v?.toString() ?? ''), ...lines.expand((line) => line.values.map((v) => v?.toString() ?? ''))].join(' ').toLowerCase();
      entries.add({'tab': targetTab, 'category': category, 'label': doc['document_number']?.toString() ?? category, 'details': '${doc['counterparty_name'] ?? ''} • ${doc['document_date'] ?? ''} • ${doc['total_amount'] ?? ''}', 'searchText': searchable});
    }
    addRows(tab: 6, category: 'طرف حساب', rows: await DemoStore.parties.getParties(), labels: const ['display_name', 'phone']);
    addRows(tab: 7, category: 'چک', rows: await DemoStore.checks.getChecks(), labels: const ['check_number', 'bank_name', 'serial_number']);
    for (final entry in await DemoStore.accounting.getJournalEntries()) {
      final lines = entry['lines'] is List ? entry['lines'] as List : const <Object?>[];
      final searchable = [...entry.values.where((v) => v is! List).map((v) => v?.toString() ?? ''), ...lines.expand((line) => line is Map ? line.values.map((v) => v?.toString() ?? '') : const <String>[])].join(' ').toLowerCase();
      entries.add({'tab': 9, 'category': 'سند حسابداری', 'label': entry['description']?.toString() ?? 'سند حسابداری', 'details': entry['entry_date']?.toString() ?? '', 'searchText': searchable});
    }
    return entries;
  }

  Future<void> _showGlobalSearch() async {
    final controller = TextEditingController();
    List<Map<String, Object>> entries = [];
    var loadError = false;
    try { entries = await _globalSearchEntries(); } catch (_) { loadError = true; }
    if (!mounted) { controller.dispose(); return; }
    await showDialog<void>(context: context, builder: (dialogContext) => Directionality(textDirection: TextDirection.rtl, child: StatefulBuilder(builder: (context, refresh) {
      final query = controller.text.trim().toLowerCase();
      final results = query.isEmpty ? <Map<String, Object>>[] : entries.where((e) => (e['searchText']! as String).contains(query)).take(50).toList();
      return AlertDialog(title: const Text('جست‌وجوی سراسری'), content: SizedBox(width: 460, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(autofocus: true, controller: controller, onChanged: (_) => refresh(() {}), decoration: const InputDecoration(hintText: 'کالا، خرید، فروش، اشخاص، چک و حسابداری', prefixIcon: Icon(Icons.search))),
        const SizedBox(height: 8),
        ConstrainedBox(constraints: const BoxConstraints(maxHeight: 360), child: loadError ? const Text('بارگذاری اطلاعات جست‌وجو ناموفق بود.') : query.isEmpty ? const Text('عبارت موردنظر را وارد کنید.') : results.isEmpty ? const Text('نتیجه‌ای پیدا نشد.') : ListView.builder(shrinkWrap: true, itemCount: results.length, itemBuilder: (context, index) {
          final item = results[index];
          return ListTile(dense: true, title: Text(item['label']! as String), subtitle: Text('${item['category']} • ${item['details']}', maxLines: 2, overflow: TextOverflow.ellipsis), onTap: () { Navigator.pop(dialogContext); _selectTab(item['tab']! as int); });
        })),
      ])), actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('بستن'))]);
    })));
    controller.dispose();
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
            leading: IconButton(
              key: const ValueKey('open-navigation-drawer'),
              tooltip: 'باز کردن فهرست',
              icon: const Icon(Icons.menu),
              onPressed: () => scaffoldKey.currentState?.openDrawer(),
            ),
            title: tab == 0
                ? Row(
                    key: const ValueKey('home-brand-title'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset(
                          'assets/logo.jpg',
                          width: 36,
                          height: 36,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Flexible(
                        child: Text(
                          'خدمات فنی حسین',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  )
                : Text(titles[tab]),
            actions: [
              IconButton(
                tooltip: 'جست‌وجوی سراسری',
                onPressed: _showGlobalSearch,
                icon: const Icon(Icons.search),
              ),
              PopupMenuButton<int>(
                tooltip: 'افزودن مورد جدید',
                icon: const Icon(Icons.add_circle_outline),
                onSelected: _selectTab,
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 1, child: Text('ثبت کالا')),
                  PopupMenuItem(value: 2, child: Text('ثبت خرید')),
                  PopupMenuItem(value: 3, child: Text('ثبت مشتری')),
                  PopupMenuItem(value: 4, child: Text('پذیرش تعمیر')),
                  PopupMenuItem(value: 5, child: Text('صدور فاکتور فروش')),
                ],
              ),
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          IconButton(
                            key: const ValueKey('drawer-settings-button'),
                            tooltip: 'تنظیمات برنامه',
                            onPressed: () {
                              scaffoldKey.currentState?.closeDrawer();
                              Navigator.of(context).push(MaterialPageRoute<void>(
                                builder: (_) => const AppSettingsPage(),
                              ));
                            },
                            icon: const Icon(
                              Icons.settings_outlined,
                              color: yellow,
                              size: 30,
                            ),
                          ),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.asset(
                              'assets/logo.jpg',
                              width: 52,
                              height: 52,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text('خدمات فنی حسین', style: TextStyle(color: yellow, fontSize: 18, fontWeight: FontWeight.bold)),
                      const Text('مدیریت فروشگاه و تعمیرات', style: TextStyle(color: Colors.white70, fontSize: 11)),
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

  static const _homeCards = <({String title, IconData icon, int tab})>[
    (title: 'خرید', icon: Icons.shopping_bag_outlined, tab: 2),
    (title: 'فروش', icon: Icons.point_of_sale_outlined, tab: 5),
    (title: 'انبار', icon: Icons.inventory_2_outlined, tab: 1),
    (title: 'پشتیبان‌گیری', icon: Icons.backup_outlined, tab: 10),
    (title: 'فاکتور', icon: Icons.receipt_long_outlined, tab: 5),
    (title: 'پذیرش دستگاه', icon: Icons.build_outlined, tab: 4),
    (title: 'صورت‌حساب اشخاص', icon: Icons.account_balance_wallet_outlined, tab: 6),
    (title: 'تماس / ارسال پیامک', icon: Icons.contact_phone_outlined, tab: 3),
  ];

  void _showOtherOperations(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('عملیات‌های دیگر'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.request_quote_outlined),
                title: const Text('مدیریت چک‌ها'),
                onTap: () {
                  Navigator.pop(dialogContext);
                  onSelect(7);
                },
              ),
              ListTile(
                leading: const Icon(Icons.bar_chart_outlined),
                title: const Text('گزارش‌ها'),
                onTap: () {
                  Navigator.pop(dialogContext);
                  onSelect(8);
                },
              ),
              ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: const Text('دفتر روزنامه و هزینه‌ها'),
                onTap: () {
                  Navigator.pop(dialogContext);
                  onSelect(9);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('بستن'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 600 ? 3 : 2;
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            itemCount: _homeCards.length + 1,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              childAspectRatio: 1.35,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemBuilder: (context, index) {
              final isOtherOperations = index == _homeCards.length;
              final card = isOtherOperations ? null : _homeCards[index];
              final title = isOtherOperations ? 'عملیات‌های دیگر' : card!.title;
              final icon = isOtherOperations ? Icons.apps_outlined : card!.icon;
              return Card(
                clipBehavior: Clip.antiAlias,
                elevation: 2,
                child: InkWell(
                  key: ValueKey('home-card-$index'),
                  onTap: () => isOtherOperations
                      ? _showOtherOperations(context)
                      : onSelect(card!.tab),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, size: 36, color: Colors.amber.shade800),
                        const SizedBox(height: 12),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
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
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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
                  }).catchError((Object error, StackTrace stackTrace) {
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
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'جست‌وجو در ${widget.title}',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'پاک کردن جست‌وجو',
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.close),
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: addItem,
                  icon: const Icon(Icons.add),
                  label: const Text('ثبت مورد جدید'),
                ),
              ),
            ),
            Expanded(
              child: Builder(
                builder: (context) {
                  final query = ProductDuplicateChecker.normalize(_searchController.text);
                  final filtered = widget.data.reversed.where((item) {
                    if (query.isEmpty) return true;
                    return item.entries.any((entry) =>
                        !entry.key.startsWith('__') &&
                        ProductDuplicateChecker.normalize(entry.key + ' ' + entry.value).contains(query));
                  }).toList();
                  if (filtered.isEmpty) {
                    return Center(
                      child: Text(_searchController.text.trim().isEmpty
                          ? 'هنوز اطلاعاتی ثبت نشده است'
                          : 'در ${widget.title} نتیجه‌ای پیدا نشد'),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      return Card(
                        child: ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.description)),
                          title: Text(item[widget.primary]?.isNotEmpty == true ? item[widget.primary]! : 'بدون عنوان'),
                          subtitle: Text(
                            item.entries.where((e) => !e.key.startsWith('__') && e.value.isNotEmpty).map((e) => '${e.key}: ${e.value}').join(' • '),
                          ),
                        ),
                      );
                    },
                  );
                },
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
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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

    double number(TextEditingController x) => LocalizedNumber.parseDoubleOrZero(x.text);
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
                    TextField(
                        textInputAction: TextInputAction.next,controller: shipping, keyboardType: TextInputType.number, onChanged: (_) => refresh(() {}), decoration: const InputDecoration(labelText: 'هزینه پست')),
                    const SizedBox(height: 10),
                    TextField(
                        textInputAction: TextInputAction.next,controller: freight, keyboardType: TextInputType.number, onChanged: (_) => refresh(() {}), decoration: const InputDecoration(labelText: 'هزینه باربری / حمل')),
                    const SizedBox(height: 10),
                    TextField(
                        textInputAction: TextInputAction.next,controller: other, keyboardType: TextInputType.number, onChanged: (_) => refresh(() {}), decoration: const InputDecoration(labelText: 'سایر هزینه‌های خرید')),
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
                        textInputAction: TextInputAction.next,
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
                  final duplicates = ProductDuplicateChecker.findDuplicates(
                    DemoStore.products,
                    item,
                  );

                  Future<void> saveProduct() async {
                    try {
                      await DemoStore.add('products', item);
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext, true);
                      }
                    } catch (error) {
                      if (dialogContext.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('ذخیره کالا ناموفق بود: $error')),
                        );
                      }
                    }
                  }

                  if (duplicates.isEmpty) {
                    saveProduct();
                    return;
                  }

                  var allowDuplicate = false;
                  showDialog<bool>(
                    context: dialogContext,
                    builder: (warningContext) => StatefulBuilder(
                      builder: (warningContext, refreshWarning) => Directionality(
                        textDirection: TextDirection.rtl,
                        child: AlertDialog(
                          title: const Text('احتمال ثبت کالای تکراری'),
                          content: SizedBox(
                            width: 360,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('کالایی با مشخصات مشابه قبلاً ثبت شده است:'),
                                const SizedBox(height: 8),
                                for (final duplicate in duplicates.take(3))
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    dense: true,
                                    leading: const Icon(Icons.inventory_2_outlined),
                                    title: Text(duplicate['نام کالا'] ?? 'بدون نام'),
                                    subtitle: Text(
                                      'کد: ${duplicate['کد کالا'] ?? '—'}  •  موجودی: ${duplicate['موجودی'] ?? '—'}',
                                    ),
                                  ),
                                if (duplicates.length > 3)
                                  Text('و ${duplicates.length - 3} مورد مشابه دیگر'),
                                const SizedBox(height: 8),
                                CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: allowDuplicate,
                                  controlAffinity: ListTileControlAffinity.leading,
                                  title: const Text('با اطلاع از تکراری بودن، اجازه ثبت می‌دهم'),
                                  onChanged: (value) => refreshWarning(
                                    () => allowDuplicate = value ?? false,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(warningContext, false),
                              child: const Text('بازگشت و اصلاح'),
                            ),
                            FilledButton(
                              onPressed: allowDuplicate
                                  ? () => Navigator.pop(warningContext, true)
                                  : null,
                              child: const Text('ثبت با وجود تکراری بودن'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ).then((approved) {
                    if (approved == true && dialogContext.mounted) {
                      saveProduct();
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

  Future<void> adjustProductStock(Map<String, String> product) async {
    final productId = int.tryParse(product['__database_id'] ?? '');
    if (productId == null) return;

    final countedController =
        TextEditingController(text: product['موجودی'] ?? '0');
    final reasonController = TextEditingController();
    final currentStock =
        LocalizedNumber.parseDoubleOrZero(product['موجودی'] ?? '0');
    final fallbackCost = LocalizedNumber.parseIntOrZero(
      product['بهای تمام‌شده هر واحد'] ??
          product['قیمت خرید هر واحد'] ??
          '0',
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('انبارگردانی: ${product['نام کالا'] ?? 'کالا'}'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('موجودی فعلی دفتر: ${currentStock.toString()} عدد'),
                const SizedBox(height: 12),
                TextField(
                        textInputAction: TextInputAction.next,
                  controller: countedController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'تعداد واقعی شمارش‌شده',
                    helperText: 'عدد نهایی موجودی را وارد کنید، نه مقدار اختلاف را',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                        textInputAction: TextInputAction.next,
                  controller: reasonController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'علت اصلاح موجودی',
                    hintText: 'مثلاً شمارش دوره‌ای یا ثبت کسری',
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'اختلاف به‌صورت خودکار با میانگین بهای تمام‌شده موجودی ارزش‌گذاری و همراه سند حسابداری ثبت می‌شود.',
                  style: TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () async {
                final counted =
                    LocalizedNumber.tryParseDouble(countedController.text);
                final reason = reasonController.text.trim();
                if (counted == null || counted < 0 || reason.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تعداد واقعی و علت معتبر را وارد کنید'),
                    ),
                  );
                  return;
                }
                if ((counted - currentStock).abs() < 0.0000001) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تعداد شمارش‌شده با دفتر برابر است و اصلاح لازم نیست'),
                    ),
                  );
                  return;
                }
                try {
                  await DemoStore.accounting.recordStockAdjustment(
                    productId: productId,
                    countedQuantity: counted,
                    fallbackUnitCost: fallbackCost,
                    occurredAt: DateTime.now().toIso8601String(),
                    reason: reason,
                    idempotencyKey:
                        'stock-count-$productId-${DateTime.now().microsecondsSinceEpoch}',
                  );
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, true);
                  }
                } catch (error) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('انبارگردانی ثبت نشد: $error')),
                    );
                  }
                }
              },
              child: const Text('ثبت اصلاح موجودی'),
            ),
          ],
        ),
      ),
    );

    countedController.dispose();
    reasonController.dispose();
    if (saved == true && mounted) {
      await DemoStore.refreshProducts();
      if (!mounted) return;
      setState(() {});
      widget.onChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('انبارگردانی و سند حسابداری با موفقیت ثبت شد'),
        ),
      );
    }
  }

  Future<void> viewProductMovements(Map<String, String> product) async {
    final productId = int.tryParse(product['__database_id'] ?? '');
    if (productId == null) return;
    final productName = product['نام کالا'] ?? 'کالا';

    try {
      final movements =
          await DemoStore.accounting.getStockMovements(productId);
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: Text('گردش انبار: $productName'),
              content: SizedBox(
                width: 480,
                height: 420,
                child: movements.isEmpty
                    ? const Center(
                        child: Text('برای این کالا گردش انباری ثبت نشده است'),
                      )
                    : ListView.separated(
                        itemCount: movements.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final movement =
                              movements[movements.length - index - 1];
                          final rawType =
                              movement['movement_type']?.toString() ?? '';
                          String type;
                          switch (rawType) {
                            case 'opening_balance':
                              type = 'موجودی اولیه';
                              break;
                            case 'purchase':
                              type = 'خرید';
                              break;
                            case 'sale':
                              type = 'فروش';
                              break;
                            case 'repair_consumption':
                              type = 'مصرف در تعمیر';
                              break;
                            case 'customer_return':
                              type = 'برگشت از مشتری';
                              break;
                            case 'supplier_return':
                              type = 'برگشت به فروشنده';
                              break;
                            case 'adjustment':
                              type = 'اصلاح موجودی';
                              break;
                            default:
                              type = rawType.isEmpty ? 'گردش انبار' : rawType;
                          }

                          final quantity =
                              (movement['quantity_delta'] as num?)
                                      ?.toDouble() ??
                                  0;
                          final unitCost =
                              (movement['unit_cost'] as num?)?.toInt() ?? 0;
                          final totalCost =
                              (movement['total_cost'] as num?)?.toInt() ?? 0;
                          final rawDate =
                              movement['occurred_at']?.toString() ?? '';
                          final parsedDate = DateTime.tryParse(rawDate);
                          final date = parsedDate == null
                              ? rawDate
                              : formatJalaliDate(parsedDate);
                          final positive = quantity >= 0;
                          final quantityText =
                              '${quantity > 0 ? '+' : ''}${quantity.toString()}';

                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: positive
                                  ? Colors.green.shade50
                                  : Colors.red.shade50,
                              child: Icon(
                                positive
                                    ? Icons.add_circle_outline
                                    : Icons.remove_circle_outline,
                                color: positive ? Colors.green : Colors.red,
                              ),
                            ),
                            title: Text(type),
                            subtitle: Text(
                              '$date\n'
                              'مقدار: $quantityText'
                              ' • بهای واحد: $unitCost تومان\n'
                              'ارزش گردش: $totalCost تومان',
                            ),
                            isThreeLine: true,
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('بستن'),
                ),
              ],
            ),
          );
        },
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('دریافت گردش انبار ناموفق بود: $error')),
        );
      }
    }
  }

  Future<void> editProduct(Map<String, String> product) async {
    final productId = int.tryParse(product['__database_id'] ?? '');
    if (productId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('شناسه کالا معتبر نیست')),
      );
      return;
    }

    const fields = [
      'نام کالا',
      'گروه اصلی',
      'زیرگروه',
      'کد کالا',
      'قیمت خرید هر واحد',
      'قیمت فروش',
    ];
    final controllers = fields
        .map((field) => TextEditingController(text: product[field] ?? ''))
        .toList(growable: false);

    final changes = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('ویرایش مشخصات کالا'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < fields.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TextField(
                        controller: controllers[i],
                        keyboardType: i >= 4
                            ? const TextInputType.numberWithOptions(decimal: true)
                            : TextInputType.text,
                        textInputAction: i == fields.length - 1
                            ? TextInputAction.done
                            : TextInputAction.next,
                        decoration: InputDecoration(labelText: fields[i]),
                      ),
                    ),
                  Card(
                    color: const Color(0xFFFFF4CC),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('موجودی فعلی: ${product['موجودی'] ?? '0'}'),
                          const SizedBox(height: 4),
                          const Text(
                            'موجودی فقط از طریق خرید، فروش، مصرف تعمیر یا اصلاح موجودی تغییر می‌کند. ویرایش مشخصات، سوابق انبار و حسابداری را تغییر نمی‌دهد.',
                            style: TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () {
                final name = controllers[0].text.trim();
                final purchasePrice = LocalizedNumber.tryParseDouble(controllers[4].text);
                final salePrice = LocalizedNumber.tryParseDouble(controllers[5].text);
                if (name.isEmpty ||
                    purchasePrice == null ||
                    salePrice == null ||
                    purchasePrice < 0 ||
                    salePrice < 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('نام کالا و قیمت‌های معتبر و غیرمنفی وارد کنید'),
                    ),
                  );
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  {
                    for (var i = 0; i < fields.length; i++)
                      fields[i]: controllers[i].text.trim(),
                  },
                );
              },
              child: const Text('ذخیره تغییرات'),
            ),
          ],
        ),
      ),
    );

    for (final controller in controllers) {
      controller.dispose();
    }
    if (changes == null || !mounted) return;

    final candidate = Map<String, String>.from(product)..addAll(changes);
    final duplicates = ProductDuplicateChecker.findDuplicates(
      DemoStore.products.where(
        (item) => item['__database_id'] != productId.toString(),
      ),
      candidate,
    );

    if (duplicates.isNotEmpty) {
      var allowDuplicate = false;
      final approved = await showDialog<bool>(
        context: context,
        builder: (warningContext) => StatefulBuilder(
          builder: (warningContext, refreshWarning) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Text('احتمال تکراری شدن کالا'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('مشخصات جدید با کالای دیگری مشابه است:'),
                  for (final duplicate in duplicates.take(3))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(duplicate['نام کالا'] ?? 'بدون نام'),
                      subtitle: Text('کد: ${duplicate['کد کالا'] ?? '—'}'),
                    ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: allowDuplicate,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('با آگاهی از تکراری بودن، اجازه می‌دهم'),
                    onChanged: (value) =>
                        refreshWarning(() => allowDuplicate = value ?? false),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(warningContext, false),
                  child: const Text('بازگشت'),
                ),
                FilledButton(
                  onPressed: allowDuplicate
                      ? () => Navigator.pop(warningContext, true)
                      : null,
                  child: const Text('ادامه و ذخیره'),
                ),
              ],
            ),
          ),
        ),
      );
      if (approved != true || !mounted) return;
    }

    try {
      await DemoStore.updateProduct(productId, changes);
      if (!mounted) return;
      setState(() {});
      widget.onChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('مشخصات کالا ذخیره شد؛ سوابق موجودی حفظ شدند')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ویرایش کالا ناموفق بود: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = ProductDuplicateChecker.normalize(_searchController.text);
    final filteredProducts = DemoStore.products.where((item) {
      if (query.isEmpty) return true;
      return item.entries.any(
        (entry) =>
            !entry.key.startsWith('__') &&
            ProductDuplicateChecker.normalize(entry.value).contains(query),
      );
    }).toList().reversed.toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        heroTag: 'add-product',
        backgroundColor: yellow,
        foregroundColor: black,
        onPressed: addProduct,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
                        textInputAction: TextInputAction.next,
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'جست‌وجوی کالا، گروه یا کد کالا',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'پاک کردن جست‌وجو',
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close),
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Text('کالاها: ${filteredProducts.length}'),
                const Spacer(),
                FilledButton.icon(
                  onPressed: addProduct,
                  icon: const Icon(Icons.add),
                  label: const Text('ثبت کالا'),
                ),
              ],
            ),
          ),
          Expanded(
            child: filteredProducts.isEmpty
                ? Center(
                    child: Text(
                      DemoStore.products.isEmpty
                          ? 'هنوز کالایی ثبت نشده است'
                          : 'کالایی با این عبارت پیدا نشد',
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
                    itemCount: filteredProducts.length,
                    itemBuilder: (context, index) {
                      final item = filteredProducts[index];
                      final image = item['تصویر کالا'] ?? '';
                      return Card(
                        child: ListTile(
                          leading: image.isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.memory(
                                    base64Decode(image),
                                    width: 48,
                                    height: 48,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        const CircleAvatar(
                                      child: Icon(Icons.broken_image_outlined),
                                    ),
                                  ),
                                )
                              : const CircleAvatar(
                                  child: Icon(Icons.inventory_2),
                                ),
                          title: Text(item['نام کالا'] ?? 'بدون نام'),
                          subtitle: Text(
                            'گروه: ${item['گروه اصلی'] ?? '—'}'
                            ' • زیرگروه: ${item['زیرگروه'] ?? '—'}\n'
                            'کد: ${item['کد کالا'] ?? '—'}'
                            ' • موجودی: ${item['موجودی'] ?? '0'}'
                            ' • خرید: ${item['بهای تمام‌شده هر واحد'] ?? item['قیمت خرید هر واحد'] ?? '0'}'
                            ' • فروش: ${item['قیمت فروش'] ?? '0'} تومان',
                          ),
                          isThreeLine: true,
                          trailing: PopupMenuButton<String>(
                            tooltip: 'عملیات کالا',
                            onSelected: (action) {
                              switch (action) {
                                case 'edit':
                                  editProduct(item);
                                  break;
                                case 'history':
                                  viewProductMovements(item);
                                  break;
                                case 'count':
                                  adjustProductStock(item);
                                  break;
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'edit',
                                child: ListTile(
                                  leading: Icon(Icons.edit_outlined),
                                  title: Text('ویرایش مشخصات'),
                                ),
                              ),
                              PopupMenuItem(
                                value: 'history',
                                child: ListTile(
                                  leading: Icon(Icons.history),
                                  title: Text('گردش ورود و خروج'),
                                ),
                              ),
                              PopupMenuItem(
                                value: 'count',
                                child: ListTile(
                                  leading: Icon(Icons.fact_check_outlined),
                                  title: Text('انبارگردانی و اصلاح موجودی'),
                                ),
                              ),
                            ],
                          ),
                          onTap: () => editProduct(item),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
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
                        textInputAction: TextInputAction.next,
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
                  final quantity = LocalizedNumber.tryParseDouble(quantityController.text);
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

  Future<void> _recordRepairServiceIncome() async {
    final repairs = DemoStore.repairs.where((item) => int.tryParse(item['__database_id'] ?? '') != null).toList();
    if (repairs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ابتدا پذیرش تعمیر را ثبت کنید')));
      return;
    }
    final repairId = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('انتخاب پذیرش تعمیر'),
        children: [
          for (final item in repairs)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, item['__database_id']),
              child: Text((item['نوع دستگاه'] ?? 'دستگاه') + ' — ' + (item['نام مشتری'] ?? 'بدون نام') + ' | اجرت: ' + (item['اجرت'] ?? '0')),
            ),
        ],
      ),
    );
    if (repairId == null || !mounted) return;
    final repair = repairs.firstWhere((item) => item['__database_id'] == repairId);
    final amount = LocalizedNumber.tryParseInt(repair['اجرت'] ?? '');
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('برای این پذیرش اجرت معتبر ثبت نشده است')));
      return;
    }
    final paidController = TextEditingController(text: amount.toString());
    final paid = await showDialog<int>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('ثبت درآمد اجرت تعمیر'),
      content: TextField(
                        textInputAction: TextInputAction.next,controller: paidController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'مبلغ دریافت‌شده (تومان)', helperText: 'برای اجرت دریافت‌نشده عدد صفر وارد کنید')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, LocalizedNumber.tryParseInt(paidController.text)), child: const Text('ثبت')),
      ],
    ));
    paidController.dispose();
    if (paid == null || paid < 0 || paid > amount || !mounted) return;
    try {
      final customerName = (repair['نام مشتری'] ?? '').trim();
      if (customerName.isEmpty) throw ArgumentError('نام مشتری ثبت نشده است');
      final customerId = await DemoStore.parties.ensureParty(PartyDraft(partyType: 'customer', displayName: customerName));
      await DemoStore.accounting.recordRepairServiceIncome(
        serviceDate: DateTime.now().toIso8601String().split('T').first,
        description: 'اجرت تعمیر ' + (repair['نوع دستگاه'] ?? ''),
        amount: amount,
        paidAmount: paid,
        cashAccountCode: '1000',
        customerId: customerId,
        idempotencyKey: 'repair-service-income-' + repairId,
        repairId: repairId,
      );
      widget.onChanged();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('درآمد اجرت ثبت شد؛ مانده دریافت‌نشده در حساب مشتری باقی ماند')));
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ثبت درآمد ناموفق بود: ' + error.toString())));
    }
  }

  Future<void> _collectRepairServiceReceivable() async {
    final repairs = DemoStore.repairs.where((item) => int.tryParse(item['__database_id'] ?? '') != null).toList();
    if (repairs.isEmpty) return;
    final repairId = await showDialog<String>(context: context, builder: (dialogContext) => SimpleDialog(
      title: const Text('انتخاب تعمیر برای دریافت مانده اجرت'),
      children: [for (final item in repairs) SimpleDialogOption(
        onPressed: () => Navigator.pop(dialogContext, item['__database_id']),
        child: Text((item['نوع دستگاه'] ?? 'دستگاه') + ' — ' + (item['نام مشتری'] ?? 'بدون نام')),
      )],
    ));
    if (repairId == null || !mounted) return;
    final repair = repairs.firstWhere((item) => item['__database_id'] == repairId);
    final customerName = (repair['نام مشتری'] ?? '').trim();
    if (customerName.isEmpty) return;
    final amountController = TextEditingController();
    final amount = await showDialog<int>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('دریافت مانده اجرت'),
      content: TextField(
                        textInputAction: TextInputAction.next,controller: amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'مبلغ دریافتی (تومان)')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, LocalizedNumber.tryParseInt(amountController.text)), child: const Text('ثبت دریافت')),
      ],
    ));
    amountController.dispose();
    if (amount == null || amount <= 0 || !mounted) return;
    try {
      final customerId = await DemoStore.parties.ensureParty(PartyDraft(partyType: 'customer', displayName: customerName));
      await DemoStore.accounting.recordRepairServiceReceipt(
        receiptDate: DateTime.now().toIso8601String().split('T').first,
        repairId: repairId,
        customerId: customerId,
        description: 'اجرت تعمیر ' + (repair['نوع دستگاه'] ?? ''),
        amount: amount,
        cashAccountCode: '1000',
        idempotencyKey: 'repair-service-receipt-' + repairId + '-' + DateTime.now().microsecondsSinceEpoch.toString(),
      );
      widget.onChanged();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('دریافت مانده اجرت ثبت شد')));
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ثبت دریافت ناموفق بود: ' + error.toString())));
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: _recordPartConsumption,
                    icon: const Icon(Icons.inventory),
                    label: const Text('ثبت مصرف قطعه در تعمیر'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _recordRepairServiceIncome,
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('ثبت درآمد اجرت تعمیر'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _collectRepairServiceReceivable,
                    icon: const Icon(Icons.price_check_outlined),
                    label: const Text('دریافت مانده اجرت تعمیر'),
                  ),
                ],
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
  final _documentSearchController = TextEditingController();
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
    _documentSearchController.dispose();
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
    return LocalizedNumber.parseIntOrZero(controller.text);
  }

  double _double(TextEditingController controller) {
    return LocalizedNumber.parseDoubleOrZero(controller.text);
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
      final archivedInvoice = await DemoStore.invoiceArchives.getArchive(id);
      documents.add({
        ...row,
        'outstanding_amount': outstanding,
        'invoice_archived': archivedInvoice != null,
      });
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

  Future<void> _editInvoiceHeader() async {
    final values = await DemoStore.invoiceSettings.getSettings();
    if (!mounted) return;

    final fields = <String, String>{
      'shopName': 'نام فروشگاه',
      'ownerName': 'نام مسئول فاکتور',
      'phone': 'شماره تماس',
      'postalCode': 'کد پستی',
      'address': 'نشانی فروشگاه',
    };
    final controllers = {
      for (final entry in fields.entries)
        entry.key: TextEditingController(text: values[entry.key] ?? ''),
    };
    final picker = ImagePicker();

    Future<void> chooseInvoiceImage(
      StateSetter refreshDialog,
      String field,
      String title,
    ) async {
      try {
        final picked = await picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 70,
          maxWidth: 1100,
          maxHeight: 1100,
        );
        if (picked == null) return;
        final compressed = await FlutterImageCompress.compressWithFile(
          picked.path,
          minWidth: 700,
          minHeight: 700,
          quality: 55,
          format: CompressFormat.jpeg,
        );
        if (compressed == null || compressed.isEmpty) {
          throw Exception('فشرده‌سازی تصویر انجام نشد');
        }
        values[field] = base64Encode(compressed);
        refreshDialog(() {});
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('انتخاب $title ناموفق بود: $error')),
          );
        }
      }
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, refreshDialog) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('تنظیم سربرگ فاکتور فروش'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final entry in fields.entries) ...[
                      TextField(
                        textInputAction: TextInputAction.next,
                        controller: controllers[entry.key],
                        decoration: InputDecoration(labelText: entry.value),
                      ),
                      const SizedBox(height: 10),
                    ],
                    _invoiceImageSetting(
                      title: 'مهر فروشگاه',
                      value: values['stampImageBase64'] ?? '',
                      onPick: () => chooseInvoiceImage(
                        refreshDialog,
                        'stampImageBase64',
                        'مهر',
                      ),
                      onRemove: () => refreshDialog(
                        () => values['stampImageBase64'] = '',
                      ),
                    ),
                    const SizedBox(height: 12),
                    _invoiceImageSetting(
                      title: 'امضای مسئول',
                      value: values['signatureImageBase64'] ?? '',
                      onPick: () => chooseInvoiceImage(
                        refreshDialog,
                        'signatureImageBase64',
                        'امضا',
                      ),
                      onRemove: () => refreshDialog(
                        () => values['signatureImageBase64'] = '',
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'سربرگ، مهر و امضای این صفحه فقط برای فاکتورهای بعدی اعمال می‌شوند؛ نسخه‌های بایگانی‌شده قبلی تغییر نمی‌کنند.',
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
                onPressed: () {
                  for (final entry in controllers.entries) {
                    values[entry.key] = entry.value.text.trim();
                  }
                  Navigator.pop(dialogContext, true);
                },
                child: const Text('ذخیره تنظیمات'),
              ),
            ],
          ),
        ),
      ),
    );

    for (final controller in controllers.values) {
      controller.dispose();
    }
    if (saved != true || !mounted) return;

    try {
      await DemoStore.invoiceSettings.saveSettings(values);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تنظیمات سربرگ، مهر و امضا ذخیره شد')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ذخیره تنظیمات ناموفق بود: $error')),
        );
      }
    }
  }

  Widget _invoiceImageSetting({
    required String title,
    required String value,
    required VoidCallback onPick,
    required VoidCallback onRemove,
  }) {
    Widget? preview;
    if (value.isNotEmpty) {
      try {
        preview = Image.memory(
          base64Decode(value),
          height: 64,
          width: 100,
          fit: BoxFit.contain,
        );
      } catch (_) {
        preview = const Icon(Icons.broken_image_outlined);
      }
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            SizedBox(
              width: 104,
              height: 68,
              child: Center(child: preview ?? const Icon(Icons.image_outlined, size: 32)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  TextButton.icon(
                    onPressed: onPick,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('انتخاب تصویر'),
                  ),
                  if (value.isNotEmpty)
                    TextButton(
                      onPressed: onRemove,
                      child: const Text('حذف تصویر'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _viewArchivedInvoice(Map<String, Object?> document) async {
    final id = (document['id'] as num).toInt();
    try {
      final archive = await DemoStore.invoiceArchives.getArchive(id);
      if (archive == null || !mounted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('نسخه بایگانی‌شده‌ای برای این فاکتور پیدا نشد')),
          );
        }
        return;
      }
      final snapshot = archive['snapshot'] as Map<String, dynamic>;
      final items = (snapshot['items'] as List? ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);

      Widget imagePreview(String key, String label) {
        final encoded = snapshot[key]?.toString() ?? '';
        if (encoded.isEmpty) return const SizedBox.shrink();
        try {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label),
                const SizedBox(height: 4),
                Image.memory(base64Decode(encoded), height: 64, fit: BoxFit.contain),
              ],
            ),
          );
        } catch (_) {
          return Text('$label: تصویر قابل نمایش نیست');
        }
      }

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text('نسخه بایگانی فاکتور ${snapshot['documentNumber'] ?? ''}'),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(snapshot['shopName']?.toString() ?? ''),
                    Text('مسئول: ${snapshot['ownerName'] ?? ''}'),
                    Text('تلفن: ${snapshot['phone'] ?? ''}'),
                    Text('کد پستی: ${snapshot['postalCode'] ?? ''}'),
                    Text('نشانی: ${snapshot['address'] ?? ''}'),
                    const Divider(),
                    Text('مشتری: ${snapshot['counterpartyName'] ?? ''}'),
                    Text('تاریخ: ${snapshot['documentDate'] ?? ''}'),
                    const SizedBox(height: 8),
                    for (final item in items)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(item['productName']?.toString() ?? ''),
                        subtitle: Text(
                          'تعداد: ${item['quantity']} × ${item['unitPrice']} تومان',
                        ),
                        trailing: Text('${item['lineTotal']} تومان'),
                      ),
                    const Divider(),
                    Text('جمع: ${snapshot['subtotal']} تومان'),
                    Text('تخفیف: ${snapshot['discountAmount']} تومان'),
                    Text('ارزش افزوده: ${snapshot['vatAmount']} تومان'),
                    Text('مبلغ نهایی: ${snapshot['totalAmount']} تومان'),
                    Text('پرداخت‌شده: ${snapshot['paidAmount']} تومان'),
                    Text('مانده: ${snapshot['outstandingAmount']} تومان'),
                    imagePreview('stampImageBase64', 'مهر ثبت‌شده هنگام صدور'),
                    imagePreview('signatureImageBase64', 'امضای ثبت‌شده هنگام صدور'),
                    const SizedBox(height: 8),
                    Text(
                      'زمان بایگانی: ${archive['archived_at']}',
                      style: const TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                    const Text(
                      'این نسخه ثابت است و تغییر تنظیمات فعلی فروشگاه، آن را عوض نمی‌کند.',
                      style: TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    await InvoicePdfService().shareImage(snapshot);
                  } catch (error) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('ساخت یا اشتراک تصویر ناموفق بود: $error')),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.image_outlined),
                label: const Text('خروجی تصویر'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    await InvoicePdfService().share(snapshot);
                  } catch (error) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('ساخت یا اشتراک PDF ناموفق بود: $error')),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('خروجی PDF'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('بستن'),
              ),
            ],
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('نمایش فاکتور بایگانی‌شده ناموفق بود: $error')),
        );
      }
    }
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
        final invoiceHeader = await DemoStore.invoiceSettings.getSettings();
        await DemoStore.trades.recordSale(
          draft,
          invoiceHeaderSnapshot: invoiceHeader,
        );
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
        SnackBar(content: Text(_isPurchase ? 'فاکتور خرید ثبت شد' : 'فاکتور فروش ثبت و بایگانی شد')),
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
                        textInputAction: TextInputAction.next,
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
                        textInputAction: TextInputAction.next,
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
    final documentQuery = ProductDuplicateChecker.normalize(_documentSearchController.text);
    final visibleDocuments = _documents.where((document) {
      if (documentQuery.isEmpty) return true;
      return document.entries.any((entry) => ProductDuplicateChecker.normalize('${entry.key} ${entry.value}').contains(documentQuery));
    }).toList();
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
                        textInputAction: TextInputAction.next,
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
          if (!_isPurchase)
            OutlinedButton.icon(
              onPressed: _saving ? null : _editInvoiceHeader,
              icon: const Icon(Icons.tune),
              label: const Text('تنظیم سربرگ، مهر و امضای فاکتور'),
            ),
          if (!_isPurchase) const SizedBox(height: 8),
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
                        textInputAction: TextInputAction.next,
                  controller: _quantityController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'تعداد'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                        textInputAction: TextInputAction.next,
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
                        textInputAction: TextInputAction.next,
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
                        textInputAction: TextInputAction.next,
              controller: _vatRateController,
              onChanged: (_) => setState(() {}),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'درصد ارزش افزوده'),
            ),
          if (_isPurchase) ...[
            const SizedBox(height: 10),
            TextField(
                        textInputAction: TextInputAction.next,
              controller: _shippingController,
              onChanged: (_) => setState(() {}),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'هزینه پست'),
            ),
            const SizedBox(height: 10),
            TextField(
                        textInputAction: TextInputAction.next,
              controller: _freightController,
              onChanged: (_) => setState(() {}),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'هزینه باربری / حمل'),
            ),
            const SizedBox(height: 10),
            TextField(
                        textInputAction: TextInputAction.next,
              controller: _otherCostController,
              onChanged: (_) => setState(() {}),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'سایر هزینه‌های خرید'),
            ),
          ],
          const SizedBox(height: 10),
          TextField(
                        textInputAction: TextInputAction.next,
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
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: TextField(
              controller: _documentSearchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: _isPurchase ? 'جست‌وجو در فاکتورهای خرید' : 'جست‌وجو در فاکتورهای فروش',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _documentSearchController.text.isEmpty ? null : IconButton(
                  tooltip: 'پاک کردن جست‌وجو',
                  onPressed: () { _documentSearchController.clear(); setState(() {}); },
                  icon: const Icon(Icons.close),
                ),
              ),
            ),
          ),
          if (visibleDocuments.isEmpty)
            Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: Text(_documents.isEmpty ? 'هنوز فاکتوری ثبت نشده است' : 'نتیجه‌ای در این بخش پیدا نشد')),
            ),
          for (final document in visibleDocuments)
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
                        if (!_isPurchase)
                          TextButton.icon(
                            onPressed: document['invoice_archived'] == true
                                ? () => _viewArchivedInvoice(document)
                                : null,
                            icon: const Icon(Icons.archive_outlined),
                            label: const Text('نسخه بایگانی'),
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



class AppSettingsPage extends StatefulWidget {
  const AppSettingsPage({super.key});
  @override State<AppSettingsPage> createState() => _AppSettingsPageState();
}

class _AppSettingsPageState extends State<AppSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{for (final k in ['shopName','ownerName','phone','postalCode','address','vatPercent','defaultDiscount','invoicePrefix']) k: TextEditingController()};
  String _currency = 'تومان'; bool _loading = true; bool _saving = false;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try { final values = await DemoStore.invoiceSettings.getSettings(); for (final e in _controllers.entries) { e.value.text = values[e.key] ?? ''; } if (mounted) setState(() { _currency = values['currency'] ?? 'تومان'; _loading = false; }); }
    catch (error) { if (mounted) { setState(() => _loading = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خواندن تنظیمات ناموفق بود: $error'))); } }
  }
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return; setState(() => _saving = true);
    try { await DemoStore.invoiceSettings.saveSettings({for (final e in _controllers.entries) e.key: e.value.text, 'currency': _currency}); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تنظیمات ذخیره شد.'))); }
    catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ذخیره ناموفق بود: $error'))); }
    finally { if (mounted) setState(() => _saving = false); }
  }
  @override void dispose() { for (final c in _controllers.values) { c.dispose(); } super.dispose(); }
  Widget _field(String key, String label, {TextInputType? type, int lines = 1}) => Padding(padding: const EdgeInsets.only(bottom: 12), child: TextFormField(controller: _controllers[key], keyboardType: type, maxLines: lines, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()), validator: (v) {
    if ((key == 'shopName' || key == 'ownerName') && (v == null || v.trim().isEmpty)) return 'این فیلد الزامی است';
    if (key == 'vatPercent' || key == 'defaultDiscount') { final n = double.tryParse((v ?? '').trim()); if (n == null || n < 0 || n > 100) return 'عدد باید بین صفر تا ۱۰۰ باشد'; } return null;
  }));
  @override Widget build(BuildContext context) => Directionality(textDirection: TextDirection.rtl, child: Scaffold(appBar: AppBar(title: const Text('تنظیمات برنامه')), body: _loading ? const Center(child: CircularProgressIndicator()) : Form(key: _formKey, child: ListView(padding: const EdgeInsets.all(16), children: [
    Text('اطلاعات فروشگاه و سربرگ فاکتور', style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 12),
    _field('shopName','نام فروشگاه'), _field('ownerName','نام مسئول'), _field('phone','شماره تماس',type: TextInputType.phone), _field('postalCode','کد پستی'), _field('address','نشانی',lines: 2),
    const Divider(height: 28), Text('تنظیمات مالی', style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 12),
    DropdownButtonFormField<String>(value: _currency, decoration: const InputDecoration(labelText: 'واحد پول', border: OutlineInputBorder()), items: const [DropdownMenuItem(value: 'تومان', child: Text('تومان')), DropdownMenuItem(value: 'ریال', child: Text('ریال'))], onChanged: (v) => setState(() => _currency = v ?? 'تومان')),
    const SizedBox(height: 12), _field('vatPercent','درصد مالیات بر ارزش افزوده',type: const TextInputType.numberWithOptions(decimal: true)), _field('defaultDiscount','درصد تخفیف پیش‌فرض',type: const TextInputType.numberWithOptions(decimal: true)), _field('invoicePrefix','پیشوند شماره فاکتور'),
    FilledButton.icon(onPressed: _saving ? null : _save, icon: _saving ? const SizedBox(width: 18,height: 18,child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined), label: const Text('ذخیره تنظیمات')),
  ]))));
}
