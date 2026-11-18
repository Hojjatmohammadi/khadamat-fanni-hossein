import 'dart:async';
import 'dart:convert';
import 'package:material_ui/material_ui.dart';
import 'backup_service.dart';
import 'phone_contact_picker.dart';
import 'backup_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart' as flutter_localizations;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'app_database.dart';
import 'trade_repository.dart';
import 'accounting_repository.dart';
import 'financial_management_page.dart';
import 'loan_repository.dart';
import 'loan_management_page.dart';
import 'party_repository.dart';
import 'check_repository.dart';
import 'party_ledger_page.dart';
import 'contacts_page.dart';
import 'checks_page.dart';
import 'jalali_date_field.dart';
import 'check_reminder_service.dart';
import 'product_duplicate_checker.dart';
import 'localized_number.dart';
import 'numeric_input.dart';
import 'invoice_archive_repository.dart';
import 'invoice_settings_repository.dart';
import 'reports_page.dart';
import 'invoice_pdf_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DemoStore.init();
  try {
    await DemoStore.reminders.initialize();
    await DemoStore.reminders.synchronize(DemoStore.checks);
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
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
        valueListenable: DemoStore.appName,
        builder: (context, appName, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: appName,
        localizationsDelegates: flutter_localizations.GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('fa'), Locale('en')],
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
        ),
      );
}

class DemoStore {
  static final ValueNotifier<String?> appLogo = ValueNotifier<String?>(null);
  static final ValueNotifier<String> appName = ValueNotifier<String>('خدمات فنی حسین');
  static final AppDatabase _database = AppDatabase();
  static final TradeRepository trades = TradeRepository(_database);
  static final AccountingRepository accounting = AccountingRepository(_database);
  static final LoanRepository loans = LoanRepository(_database);
  static final PartyRepository parties = PartyRepository(_database);
  static final CheckRepository checks = CheckRepository(_database);
  static final CheckReminderService reminders = CheckReminderService();
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
    final settings = await invoiceSettings.getSettings();
    appLogo.value = settings['appLogoBase64'];
    appName.value = settings['appName']?.trim().isNotEmpty == true
        ? settings['appName']!.trim()
        : 'خدمات فنی حسین';
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
  static Future<void> refreshCustomers() => _loadCategory('customers', customers);
  static Future<void> refreshRepairs() => _loadCategory('repairs', repairs);

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

  static Future<void> deleteRecord(String category, int id) async {
    await _database.deleteRecord(category, id);
    final target = switch (category) {
      'products' => products,
      'customers' => customers,
      'repairs' => repairs,
      _ => throw ArgumentError('دسته اطلاعات قابل حذف نیست'),
    };
    target.removeWhere((item) => item['__database_id'] == id.toString());
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  bool _dailyBackupCheckRunning = false;
  bool _isDrawerOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkDailyBackup();
    }
  }

  Future<void> _checkDailyBackup() async {
    if (_dailyBackupCheckRunning) return;
    _dailyBackupCheckRunning = true;
    try {
      final backup = await DemoStore.backups.createDailyBackupIfDue();
      if (backup != null) {
        DemoStore.backupStartupNotice =
            'نسخه پشتیبان روزانه پس از بازگشت به برنامه ایجاد شد.';
      }
    } catch (error) {
      DemoStore.backupStartupNotice = 'هشدار: پشتیبان روزانه ایجاد نشد: $error';
    } finally {
      _dailyBackupCheckRunning = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  final GlobalKey<_ProductPageState> _productPageKey = GlobalKey<_ProductPageState>();
  final GlobalKey<_SimpleListPageState> _customerPageKey = GlobalKey<_SimpleListPageState>();
  final GlobalKey<_RepairPageState> _repairPageKey = GlobalKey<_RepairPageState>();
  int tab = 0;
  final List<int> _tabHistory = [];
  final titles = const ['داشبورد', 'انبار کالا', 'خرید و برگشت', 'مشتریان', 'تعمیرات', 'فروش و فاکتور', 'دفتر گردش اشخاص', 'مدیریت چک‌ها', 'گزارش‌ها', 'دفتر روزنامه و هزینه‌ها', 'پشتیبان‌گیری و بازیابی', 'قرض‌ها و اقساط', 'دفتر مخاطبین'];

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
        entries.add({'tab': tab, 'category': category, 'label': label, 'details': values.take(3).join(' • '), 'searchText': ProductDuplicateChecker.normalize(row.values.where((v) => v != null).join(' '))});
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
      final searchable = [...doc.values.map((v) => v?.toString() ?? ''), ...lines.expand((line) => line.values.map((v) => v?.toString() ?? ''))].join(' ');
      entries.add({'tab': targetTab, 'category': category, 'label': doc['document_number']?.toString() ?? category, 'details': '${doc['counterparty_name'] ?? ''} • ${doc['document_date'] ?? ''} • ${doc['total_amount'] ?? ''}', 'searchText': ProductDuplicateChecker.normalize(searchable)});
    }
    addRows(tab: 6, category: 'طرف حساب', rows: await DemoStore.parties.getParties(), labels: const ['display_name', 'phone']);
    addRows(tab: 7, category: 'چک', rows: await DemoStore.checks.getChecks(), labels: const ['check_number', 'bank_name', 'serial_number']);
    for (final entry in await DemoStore.accounting.getJournalEntries()) {
      final lines = entry['lines'] is List ? entry['lines'] as List : const <Object?>[];
      final searchable = [...entry.values.where((v) => v is! List).map((v) => v?.toString() ?? ''), ...lines.expand((line) => line is Map ? line.values.map((v) => v?.toString() ?? '') : const <String>[])].join(' ');
      entries.add({'tab': 9, 'category': 'سند حسابداری', 'label': entry['description']?.toString() ?? 'سند حسابداری', 'details': entry['entry_date']?.toString() ?? '', 'searchText': ProductDuplicateChecker.normalize(searchable)});
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
      final query = ProductDuplicateChecker.normalize(controller.text);
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
  void _openNavigationDrawer() {
    if (mounted) setState(() => _isDrawerOpen = true);
  }

  void _closeNavigationDrawer() {
    if (mounted && _isDrawerOpen) setState(() => _isDrawerOpen = false);
  }

  Future<void> _handleBack() async {
    if (_isDrawerOpen) {
      _closeNavigationDrawer();
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
      ProductPage(key: _productPageKey, onChanged: () => setState(() {})),
      PurchasePage(onChanged: () => setState(() {})),
      CustomerPage(listKey: _customerPageKey, onChanged: () => setState(() {})),
      RepairPage(key: _repairPageKey, onChanged: () => setState(() {})),
      SalesPage(onChanged: () => setState(() {})),
      PartyLedgerPage(
        repository: DemoStore.parties,
        reminders: DemoStore.reminders,
        trades: DemoStore.trades,
        checks: DemoStore.checks,
        onChanged: () => setState(() {}),
      ),
      CheckPage(
        checks: DemoStore.checks,
        parties: DemoStore.parties,
        trades: DemoStore.trades,
        reminders: DemoStore.reminders,
        onChanged: () => setState(() {}),
      ),
      const ReportsPage(),
      FinancialManagementPage(repository: DemoStore.accounting, parties: DemoStore.parties),
      BackupPage(
        service: DemoStore.backups,
        initialMessage: DemoStore.backupStartupNotice,
      ),
      LoanManagementPage(repository: DemoStore.loans),
      ContactsPage(
        repository: DemoStore.parties,
        reminders: DemoStore.reminders,
        trades: DemoStore.trades,
        checks: DemoStore.checks,
        onChanged: () async {
          await Future.wait([
            DemoStore.refreshCustomers(),
            DemoStore.refreshRepairs(),
          ]);
          if (mounted) setState(() {});
        },
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
        child: Stack(
          children: [
          Scaffold(
          key: scaffoldKey,
          appBar: AppBar(
            leading: IconButton(
              key: const ValueKey('open-navigation-drawer'),
              tooltip: 'باز کردن فهرست',
              icon: const Icon(Icons.menu),
              onPressed: _openNavigationDrawer,
            ),
            title: tab == 0
                ? Row(
                    key: const ValueKey('home-brand-title'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: ValueListenableBuilder<String?>(
                          valueListenable: DemoStore.appLogo,
                          builder: (context, logo, _) => logo?.isNotEmpty == true
                              ? Image.memory(base64Decode(logo!), width: 36, height: 36, fit: BoxFit.cover)
                              : Image.asset('assets/logo.jpg', width: 36, height: 36, fit: BoxFit.cover),
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
              if (tab == 1) ...[
                IconButton(
                  tooltip: 'ثبت کالا',
                  onPressed: () => _productPageKey.currentState?.addProduct(),
                  icon: const Icon(Icons.add_circle_outline),
                ),
                PopupMenuButton<String>(
                  // In RTL the actions row is on the left edge. Shift this
                  // menu into the viewport so all three choices can be tapped.
                  offset: const Offset(180, 0),
                  tooltip: 'تنظیم نمایش عکس کالا',
                  onSelected: (option) =>
                      _productPageKey.currentState?.setProductImageDisplay(option),
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'hide',
                      child: Text('عدم نمایش عکس کالا'),
                    ),
                    PopupMenuItem(
                      value: 'default',
                      child: Text('پیش‌فرض عکس کالا'),
                    ),
                    PopupMenuItem(
                      value: 'small',
                      child: Text('کوچک کردن عکس کالا'),
                    ),
                  ],
                ),
              ] else if (tab == 3)
                IconButton(
                  tooltip: 'ثبت مشتری',
                  onPressed: () => _customerPageKey.currentState?.addItem(),
                  icon: const Icon(Icons.add_circle_outline),
                )
              else if (tab == 4)
                IconButton(
                  tooltip: 'ثبت پذیرش تعمیر',
                  onPressed: () => _repairPageKey.currentState?.addRepair(),
                  icon: const Icon(Icons.add_circle_outline),
                )
              else
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
          body: Padding(
            key: const ValueKey('app-page-bottom-gap'),
            padding: const EdgeInsets.only(bottom: 24),
            child: SafeArea(
              top: false,
              child: pages[tab],
            ),
          ),
          if (_isDrawerOpen) ...[
            Positioned.fill(
              child: GestureDetector(
                key: const ValueKey('navigation-drawer-scrim'),
                onTap: _closeNavigationDrawer,
                child: const ColoredBox(color: Color(0x66000000)),
              ),
            ),
            Positioned(
              key: const ValueKey('navigation-drawer-panel'),
              top: 0,
              bottom: 0,
              right: 0,
              width: MediaQuery.sizeOf(context).width < 360
                  ? MediaQuery.sizeOf(context).width * 0.86
                  : 304,
              child: Material(
                color: Colors.white,
                elevation: 16,
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
                          ClipRRect(
                            key: const ValueKey('drawer-logo'),
                            borderRadius: BorderRadius.circular(10),
                            child: ValueListenableBuilder<String?>(
                              valueListenable: DemoStore.appLogo,
                              builder: (context, logo, _) => logo?.isNotEmpty == true
                                  ? Image.memory(base64Decode(logo!), width: 52, height: 52, fit: BoxFit.cover)
                                  : Image.asset('assets/logo.jpg', width: 52, height: 52, fit: BoxFit.cover),
                            ),
                          ),
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
                        ],
                      ),
                      const SizedBox(height: 4),
                      ValueListenableBuilder<String>(
                        valueListenable: DemoStore.appName,
                        builder: (context, appName, _) => Text(
                          appName,
                          style: const TextStyle(color: yellow, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const Text('مدیریت فروشگاه و تعمیرات', style: TextStyle(color: Colors.white70, fontSize: 11)),
                    ],
                  ),
                ),
                for (int i = 0; i < titles.length; i++)
                  ListTile(
                    leading: Icon([Icons.dashboard, Icons.inventory_2, Icons.shopping_bag, Icons.people, Icons.build, Icons.receipt_long, Icons.account_balance, Icons.request_quote, Icons.bar_chart, Icons.menu_book, Icons.backup, Icons.payments, Icons.contacts][i]),
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
          ],
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
    (title: 'مخاطبین', icon: Icons.contacts_outlined, tab: 12),
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

List<Map<String, String>> filterCategoryRecords(Iterable<Map<String, String>> records, String query) {
  final normalizedQuery = ProductDuplicateChecker.normalize(query);
  return records.where((item) => normalizedQuery.isEmpty || item.entries.any((entry) =>
      !entry.key.startsWith('__') &&
      ProductDuplicateChecker.normalize('${entry.key} ${entry.value}').contains(normalizedQuery))).toList();
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
    String? selectedRepairCustomerPartyId;
    StateSetter? refreshRepairDialog;
    final repairCustomerOptions = widget.title == 'پذیرش تعمیر'
        ? await DemoStore.parties.getParties(partyType: 'customer')
        : <Map<String, Object?>>[];
    final focusNodes = widget.fields.map((_) => FocusNode()).toList();

    Future<void> addRepairCustomer() async {
      final nameController = TextEditingController();
      final phoneController = TextEditingController();
      final addressController = TextEditingController();
      final formKey = GlobalKey<FormState>();
      final savedCustomer = await showDialog<bool>(
        context: context,
        builder: (nestedContext) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('افزودن مشتری به دفتر مخاطبین'),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'نام مشتری'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'نام مشتری را وارد کنید'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  PhoneContactPickerButton(
                    onSelected: (contact) {
                      nameController.text = contact.name;
                      phoneController.text = contact.phone;
                      if (contact.name.isNotEmpty) {
                        nameController.selection = TextSelection.collapsed(
                          offset: nameController.text.length,
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    inputFormatters: numericInputFormattersForField('شماره همراه'),
                    decoration: const InputDecoration(labelText: 'شماره همراه'),
                    validator: (value) => validateNumericField('شماره همراه', value),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: addressController,
                    decoration: const InputDecoration(labelText: 'نشانی'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(nestedContext, false),
                child: const Text('انصراف'),
              ),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState!.validate()) {
                    Navigator.pop(nestedContext, true);
                  }
                },
                child: const Text('ذخیره و انتخاب'),
              ),
            ],
          ),
        ),
      );
      if (savedCustomer == true && mounted) {
        try {
          final id = await DemoStore.parties.ensureParty(
            PartyDraft(
              partyType: 'customer',
              displayName: nameController.text.trim(),
              phone: phoneController.text.trim(),
              address: addressController.text.trim(),
            ),
          );
          repairCustomerOptions
            ..removeWhere((party) => party['id'] == id)
            ..add({
              'id': id,
              'display_name': nameController.text.trim(),
              'phone': phoneController.text.trim(),
            });
          selectedRepairCustomerPartyId = id;
          controllers[0].text = nameController.text.trim();
          refreshRepairDialog?.call(() {});
          if (mounted) setState(() {});
        } catch (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('افزودن مشتری ناموفق بود: $error')),
            );
          }
        }
      }
      nameController.dispose();
      phoneController.dispose();
      addressController.dispose();
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, refreshDialog) {
          refreshRepairDialog = refreshDialog;
          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: Text('ثبت ${widget.title} جدید'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.title == 'مشتری')
                    PhoneContactPickerButton(
                      onSelected: (contact) {
                        if (controllers.isNotEmpty) {
                          controllers[0].text = contact.name;
                        }
                        if (controllers.length > 1) {
                          controllers[1].text = contact.phone;
                        }
                      },
                    ),
                  if (widget.title == 'پذیرش تعمیر') ...[
                    if (repairCustomerOptions.isNotEmpty)
                      DropdownButtonFormField<String>(
                        key: const ValueKey('repair-existing-customer-selector'),
                        decoration: const InputDecoration(
                          labelText: 'انتخاب مشتری ثبت‌شده',
                        ),
                        isExpanded: true,
                        items: [
                          for (final customer in repairCustomerOptions)
                            DropdownMenuItem<String>(
                              value: customer['id'] as String,
                              child: Text(
                                '${customer['display_name'] ?? ''} • ${customer['phone'] ?? 'بدون شماره'}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (partyId) {
                          if (partyId == null) return;
                          selectedRepairCustomerPartyId = partyId;
                          final customer = repairCustomerOptions.firstWhere(
                            (item) => item['id'] == partyId,
                          );
                          controllers[0].text =
                              customer['display_name']?.toString() ?? '';
                        },
                      ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        key: const ValueKey('repair-inline-add-customer'),
                        onPressed: addRepairCustomer,
                        icon: const Icon(Icons.person_add_alt_1),
                        label: const Text('افزودن مشتری جدید'),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  for (int i = 0; i < widget.fields.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TextField(
                        controller: controllers[i],
                        focusNode: focusNodes[i],
                        keyboardType: numericKeyboardTypeForField(widget.fields[i]),
                        inputFormatters: numericInputFormattersForField(widget.fields[i]),
                        textInputAction: i == widget.fields.length - 1
                            ? TextInputAction.done
                            : TextInputAction.next,
                        onChanged: i == 0 && widget.title == 'پذیرش تعمیر'
                            ? (value) {
                                final selectedId = selectedRepairCustomerPartyId;
                                if (selectedId != null) {
                                  final selected = repairCustomerOptions.firstWhere(
                                    (item) => item['id'] == selectedId,
                                    orElse: () => const <String, Object?>{},
                                  );
                                  if (value.trim() !=
                                      (selected['display_name']?.toString() ?? '').trim()) {
                                    selectedRepairCustomerPartyId = null;
                                  }
                                }
                              }
                            : null,
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
                  final label = widget.fields[i];
                  final raw = controllers[i].text.trim();
                  final error = validateNumericField(label, raw);
                  if (error != null) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text(error)));
                    return;
                  }
                  item[label] = normalizeNumericField(label, raw);
                }
                final category = widget.title == 'مشتری'
                    ? 'customers'
                    : widget.title == 'پذیرش تعمیر'
                        ? 'repairs'
                        : 'sales';
                final requiredFields = category == 'customers'
                    ? const ['نام مشتری']
                    : category == 'repairs'
                        ? const ['نام مشتری', 'نوع دستگاه']
                        : const <String>[];
                final missingRequired = requiredFields.where(
                  (field) => (item[field] ?? '').trim().isEmpty,
                );
                if (missingRequired.isNotEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'لطفاً ${missingRequired.join(' و ')} را وارد کنید.',
                      ),
                    ),
                  );
                  return;
                }
                if (item.values.any((value) => value.isNotEmpty)) {
                  if (category == 'repairs' && selectedRepairCustomerPartyId != null) {
                    item['شناسه طرف حساب'] = selectedRepairCustomerPartyId!;
                    item['شناسه مشتری'] = selectedRepairCustomerPartyId!.startsWith('customer:')
                        ? selectedRepairCustomerPartyId!.substring('customer:'.length)
                        : selectedRepairCustomerPartyId!;
                  }
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
        );
        },
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

  Future<void> deleteItem(Map<String, String> item) async {
    final id = int.tryParse(item['__database_id'] ?? '');
    final category = switch (widget.title) {
      'مشتری' => 'customers',
      'پذیرش تعمیر' => 'repairs',
      _ => null,
    };
    if (id == null || category == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('شناسه یا نوع رکورد برای حذف معتبر نیست')),
      );
      return;
    }

    final displayName = item[widget.primary]?.trim().isNotEmpty == true
        ? item[widget.primary]!
        : widget.title;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('حذف $displayName'),
          content: const Text(
            'در صورت نداشتن سابقهٔ وابسته، این رکورد حذف می‌شود. '
            'سوابق فاکتور، انبار و حسابداری قابل حذف نیستند. ادامه می‌دهید؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await DemoStore.deleteRecord(category, id);
      if (!mounted) return;
      setState(() {});
      widget.onChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('رکورد حذف شد.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst('Bad state: ', ''),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.transparent,
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
            Expanded(
              child: Builder(
                builder: (context) {
                  final filtered = filterCategoryRecords(widget.data.reversed, _searchController.text);
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
                          trailing: IconButton(
                            tooltip: 'حذف رکورد',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => deleteItem(item),
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
  bool _hideProductImages = false;
  bool _smallProductImages = false;

  void setProductImageDisplay(String option) {
    setState(() {
      switch (option) {
        case 'hide':
          _hideProductImages = true;
          _smallProductImages = false;
          break;
        case 'small':
          _hideProductImages = false;
          _smallProductImages = true;
          break;
        case 'default':
          _hideProductImages = false;
          _smallProductImages = false;
          break;
      }
    });
  }

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
                          keyboardType: i >= 4 ? const TextInputType.numberWithOptions(decimal: true) : numericKeyboardTypeForField(names[i]),
                          inputFormatters: numericInputFormattersForField(names[i], forceNumeric: i >= 4, allowDecimal: true),
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
                        textInputAction: TextInputAction.next,controller: shipping, keyboardType: TextInputType.number,
                        inputFormatters: const [NumericInputFormatter()], onChanged: (_) => refresh(() {}), decoration: const InputDecoration(labelText: 'هزینه پست')),
                    const SizedBox(height: 10),
                    TextField(
                        textInputAction: TextInputAction.next,controller: freight, keyboardType: TextInputType.number,
                        inputFormatters: const [NumericInputFormatter()], onChanged: (_) => refresh(() {}), decoration: const InputDecoration(labelText: 'هزینه باربری / حمل')),
                    const SizedBox(height: 10),
                    TextField(
                        textInputAction: TextInputAction.next,controller: other, keyboardType: TextInputType.number,
                        inputFormatters: const [NumericInputFormatter()], onChanged: (_) => refresh(() {}), decoration: const InputDecoration(labelText: 'سایر هزینه‌های خرید')),
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
                        inputFormatters: const [NumericInputFormatter(allowDecimal: true)],
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
                  final productName = c[0].text.trim();
                  final stockText = c[4].text.trim();
                  final stockValue = LocalizedNumber.tryParseDouble(stockText);
                  if (productName.isEmpty || stockText.isEmpty ||
                      stockValue == null || !stockValue.isFinite ||
                      stockValue < 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'نام کالا و موجودی معتبر و غیرمنفی را وارد کنید.',
                        ),
                      ),
                    );
                    return;
                  }
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
    final costController = TextEditingController();
    final currentStock =
        LocalizedNumber.parseDoubleOrZero(product['موجودی'] ?? '0');
    final fallbackCost = LocalizedNumber.parseIntOrZero(
      product['بهای تمام‌شده هر واحد'] ??
          product['قیمت خرید هر واحد'] ??
          '0',
    );
    costController.text = fallbackCost > 0 ? fallbackCost.toString() : '';

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('انبارگردانی: ${product['نام کالا'] ?? 'کالا'}'),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('موجودی فعلی دفتر: ${currentStock.toString()} عدد'),
                const SizedBox(height: 12),
                TextField(
                        textInputAction: TextInputAction.next,
                  controller: countedController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: const [NumericInputFormatter(allowDecimal: true)],
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
                if (currentStock <= 0) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: costController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: false),
                    inputFormatters: numericInputFormattersForField('بهای تمام‌شده', forceNumeric: true),
                    decoration: const InputDecoration(
                      labelText: 'بهای تمام‌شده هر واحد (تومان)',
                      helperText: 'برای ارزش‌گذاری موجودی جدید الزامی است',
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                const Text(
                  'اختلاف به‌صورت خودکار با میانگین بهای تمام‌شده موجودی ارزش‌گذاری و همراه سند حسابداری ثبت می‌شود.',
                  style: TextStyle(fontSize: 11, color: Colors.black54),
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
                final counted =
                    LocalizedNumber.tryParseDouble(countedController.text);
                final reason = reasonController.text.trim();
                final enteredCost = LocalizedNumber.tryParseInt(costController.text);
                final effectiveCost = currentStock > 0 ? fallbackCost : (enteredCost ?? 0);
                if (counted == null || counted < 0 || reason.isEmpty ||
                    (currentStock <= 0 && (enteredCost == null || enteredCost <= 0))) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(currentStock <= 0 && (enteredCost == null || enteredCost <= 0)
                          ? 'برای کالایی با موجودی صفر، بهای تمام‌شده معتبر و بیشتر از صفر وارد کنید'
                          : 'تعداد واقعی و علت معتبر را وارد کنید'),
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
                    fallbackUnitCost: effectiveCost,
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
    costController.dispose();
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
                            : numericKeyboardTypeForField(fields[i]),
                        inputFormatters: numericInputFormattersForField(fields[i], forceNumeric: i >= 4, allowDecimal: true),
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

  Future<void> _deleteProduct(Map<String, String> product) async {
    final id = int.tryParse(product['__database_id'] ?? '');
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('شناسه کالا معتبر نیست')),
      );
      return;
    }
    final name = product['نام کالا']?.trim().isNotEmpty == true
        ? product['نام کالا']!
        : 'این کالا';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('حذف $name'),
          content: const Text(
            'فقط کالایی حذف می‌شود که هیچ سابقهٔ ورود و خروج انبار یا فاکتور نداشته باشد. ادامه می‌دهید؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('حذف کالا'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await DemoStore.deleteRecord('products', id);
      if (!mounted) return;
      setState(() {});
      widget.onChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('کالا حذف شد.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
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
                          leading: _hideProductImages
                              ? null
                              : image.isNotEmpty
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.memory(
                                        base64Decode(image),
                                        width: _smallProductImages ? 26 : 48,
                                        height: _smallProductImages ? 26 : 48,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => CircleAvatar(
                                          radius: _smallProductImages ? 13 : 24,
                                          child: Icon(
                                            Icons.broken_image_outlined,
                                            size: _smallProductImages ? 16 : 24,
                                          ),
                                        ),
                                      ),
                                    )
                                  : CircleAvatar(
                                      radius: _smallProductImages ? 13 : 24,
                                      child: Icon(
                                        Icons.inventory_2,
                                        size: _smallProductImages ? 16 : 24,
                                      ),
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
                                case 'delete':
                                  _deleteProduct(item);
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
                              PopupMenuItem(
                                value: 'delete',
                                child: ListTile(
                                  leading: Icon(Icons.delete_outline),
                                  title: Text('حذف کالا'),
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
  final GlobalKey<_SimpleListPageState> listKey;
  const CustomerPage({super.key, required this.onChanged, required this.listKey});

  @override
  Widget build(BuildContext context) => SimpleListPage(
        key: listKey,
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
  final GlobalKey<_SimpleListPageState> _listKey =
      GlobalKey<_SimpleListPageState>();

  Future<void> addRepair() async {
    await _listKey.currentState?.addItem();
  }

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
    String selectedUiSize = 'معمولی';

    double uiScale() => switch (selectedUiSize) {
      'ریز' => 0.80,
      'کوچک' => 0.90,
      'بزرگ' => 1.15,
      _ => 1.0,
    };

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text(
              'ثبت مصرف قطعه در تعمیر',
              style: TextStyle(fontSize: 20 * uiScale()),
            ),
            content: SizedBox(
              width: 380 * uiScale(),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      key: ValueKey('repair-parts-ui-size-$selectedUiSize'),
                      initialValue: selectedUiSize,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'اندازه نمایش بخش قطعات',
                        labelStyle: TextStyle(fontSize: 14 * uiScale()),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 14 * uiScale(),
                          vertical: 14 * uiScale(),
                        ),
                      ),
                      items: [
                        for (final size in const ['ریز', 'کوچک', 'معمولی', 'بزرگ'])
                          DropdownMenuItem(
                            value: size,
                            child: Text(size, style: TextStyle(fontSize: 14 * uiScale())),
                          ),
                      ],
                      onChanged: (value) {
                        refresh(() => selectedUiSize = value ?? 'معمولی');
                      },
                    ),
                    SizedBox(height: 12 * uiScale()),
                    DropdownButtonFormField<int>(
                      key: ValueKey('repair-parts-repair-$selectedRepairId'),
                      initialValue: selectedRepairId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'پذیرش تعمیر',
                        labelStyle: TextStyle(fontSize: 14 * uiScale()),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 14 * uiScale(),
                          vertical: 14 * uiScale(),
                        ),
                      ),
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
                    SizedBox(height: 12 * uiScale()),
                    DropdownButtonFormField<int>(
                      key: ValueKey('repair-parts-product-$selectedProductId'),
                      initialValue: selectedProductId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'قطعه مصرفی',
                        labelStyle: TextStyle(fontSize: 14 * uiScale()),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 14 * uiScale(),
                          vertical: 14 * uiScale(),
                        ),
                      ),
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
                    SizedBox(height: 12 * uiScale()),
                    SizedBox(
                      height: 58 * uiScale(),
                      child: TextField(
                        textInputAction: TextInputAction.next,
                        controller: quantityController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: const [NumericInputFormatter(allowDecimal: true)],
                        style: TextStyle(fontSize: 16 * uiScale()),
                        decoration: InputDecoration(
                          labelText: 'تعداد مصرفی',
                          labelStyle: TextStyle(fontSize: 14 * uiScale()),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 14 * uiScale(),
                            vertical: 14 * uiScale(),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 8 * uiScale()),
                    Text(
                      'هزینه قطعه بر اساس میانگین بهای موجودی محاسبه و به هزینه قطعات مصرفی تعمیر منتقل می‌شود.',
                      style: TextStyle(fontSize: 12 * uiScale(), color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                style: TextButton.styleFrom(
                  textStyle: TextStyle(fontSize: 14 * uiScale()),
                  padding: EdgeInsets.symmetric(
                    horizontal: 16 * uiScale(),
                    vertical: 12 * uiScale(),
                  ),
                ),
                child: const Text('انصراف'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  textStyle: TextStyle(fontSize: 14 * uiScale()),
                  padding: EdgeInsets.symmetric(
                    horizontal: 18 * uiScale(),
                    vertical: 12 * uiScale(),
                  ),
                ),
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
                      customerId: repair['شناسه طرف حساب'],
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
                        textInputAction: TextInputAction.next,controller: paidController, keyboardType: TextInputType.number,
                        inputFormatters: const [NumericInputFormatter()], decoration: const InputDecoration(labelText: 'مبلغ دریافت‌شده (تومان)', helperText: 'برای اجرت دریافت‌نشده عدد صفر وارد کنید')),
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
      final linkedPartyId = repair['شناسه طرف حساب']?.trim();
      final customerId = linkedPartyId != null && linkedPartyId.isNotEmpty
          ? linkedPartyId
          : await DemoStore.parties.ensureParty(
              PartyDraft(partyType: 'customer', displayName: customerName),
            );
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
                        textInputAction: TextInputAction.next,controller: amountController, keyboardType: TextInputType.number,
                        inputFormatters: const [NumericInputFormatter()], decoration: const InputDecoration(labelText: 'مبلغ دریافتی (تومان)')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, LocalizedNumber.tryParseInt(amountController.text)), child: const Text('ثبت دریافت')),
      ],
    ));
    amountController.dispose();
    if (amount == null || amount <= 0 || !mounted) return;
    try {
      final linkedPartyId = repair['شناسه طرف حساب']?.trim();
      final customerId = linkedPartyId != null && linkedPartyId.isNotEmpty
          ? linkedPartyId
          : await DemoStore.parties.ensureParty(
              PartyDraft(partyType: 'customer', displayName: customerName),
            );
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
              key: _listKey,
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
  double _defaultDiscountPercent = 0;
  bool _discountManuallyEdited = false;
  final _paidController = TextEditingController(text: '0');
  final _shippingController = TextEditingController(text: '0');
  final _freightController = TextEditingController(text: '0');
  final _otherCostController = TextEditingController(text: '0');

  final List<TradeLineDraft> _lines = [];
  String _currency = 'تومان';
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
    _loadInvoiceDefaults();
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

  int get _previewDiscount => _int(_discountController);

  int get _previewCharges => _isPurchase
      ? _int(_shippingController) +
          _int(_freightController) +
          _int(_otherCostController)
      : 0;

  int get _previewNet => _subtotal - _previewDiscount;

  int get _previewVat => _vatExempt
      ? 0
      : (_previewNet * _double(_vatRateController) / 100).round();

  int get _previewTotal => _previewNet + _previewCharges + _previewVat;

  int get _previewBalance => _previewTotal - _int(_paidController);

  Future<void> _loadInvoiceDefaults() async {
    try {
      final settings = await DemoStore.invoiceSettings.getSettings();
      final vat = LocalizedNumber.parseDoubleOrZero(settings['vatPercent'] ?? '0');
      final discount = LocalizedNumber.parseDoubleOrZero(settings['defaultDiscount'] ?? '0');
      if (!mounted) return;
      setState(() {
        _currency = settings['currency'] == 'ریال' ? 'ریال' : 'تومان';
        _vatRateController.text = vat.clamp(0, 100).toString();
        _defaultDiscountPercent = discount.clamp(0, 100).toDouble();
        _applyDefaultDiscount();
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خواندن تنظیمات پیش‌فرض فاکتور ناموفق بود: $error')),
        );
      }
    }
  }

  void _applyDefaultDiscount() {
    if (_discountManuallyEdited) return;
    _discountController.text = (_subtotal * _defaultDiscountPercent / 100).round().toString();
  }

  Future<void> _selectPhoneParty(PhoneContactSelection contact) async {
    final displayName = contact.name.trim();
    if (displayName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('مخاطب انتخاب‌شده نام معتبری ندارد.')),
      );
      return;
    }
    try {
      final id = await DemoStore.parties.ensureParty(
        PartyDraft(
          partyType: _isPurchase ? 'supplier' : 'customer',
          displayName: displayName,
          phone: contact.phone,
        ),
      );
      await _loadParties();
      if (!mounted) return;
      setState(() {
        _selectedPartyId = id;
        _partyController.text = displayName;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('مخاطب گوشی به دفتر اشخاص متصل و در فاکتور انتخاب شد.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ثبت مخاطب انتخاب‌شده ناموفق بود: $error')),
        );
      }
    }
  }

  Future<void> _addPartyInline() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final addressController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(_isPurchase ? 'افزودن فروشنده به دفتر مخاطبین' : 'افزودن مشتری به دفتر مخاطبین'),
          content: SizedBox(
            width: 420,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'نام و نام خانوادگی'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'نام مخاطب را وارد کنید'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  PhoneContactPickerButton(
                    onSelected: (contact) {
                      nameController.text = contact.name;
                      phoneController.text = contact.phone;
                    },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    inputFormatters: numericInputFormattersForField('شماره همراه'),
                    decoration: const InputDecoration(labelText: 'شماره همراه'),
                    validator: (value) => validateNumericField('شماره همراه', value),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: addressController,
                    decoration: const InputDecoration(labelText: 'نشانی'),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'در صورت ثبت قبلی همین شخص با شماره همراه یکسان، نقش جدید به همان پرونده افزوده می‌شود.',
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
            FilledButton.icon(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(dialogContext, true);
                }
              },
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('ذخیره و انتخاب'),
            ),
          ],
        ),
      ),
    );

    if (saved == true && mounted) {
      try {
        final role = _isPurchase ? 'supplier' : 'customer';
        final id = await DemoStore.parties.ensureParty(
          PartyDraft(
            partyType: role,
            displayName: nameController.text.trim(),
            phone: phoneController.text.trim(),
            address: addressController.text.trim(),
          ),
        );
        await _loadParties();
        if (!mounted) return;
        setState(() {
          _selectedPartyId = id;
          _partyController.text = nameController.text.trim();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('مخاطب ذخیره و در فاکتور انتخاب شد.')),
        );
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('افزودن مخاطب ناموفق بود: $error')),
          );
        }
      }
    }
    nameController.dispose();
    phoneController.dispose();
    addressController.dispose();
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
      _applyDefaultDiscount();
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
                        keyboardType: numericKeyboardTypeForField(entry.value),
                        inputFormatters: numericInputFormattersForField(entry.value),
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
                    final label = fields[entry.key]!;
                    final raw = entry.value.text.trim();
                    final error = validateNumericField(label, raw);
                    if (error != null) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text(error)));
                      return;
                    }
                    values[entry.key] = normalizeNumericField(label, raw);
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
      final currency = snapshot['currency'] == 'ریال' ? 'ریال' : 'تومان';
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
                    Text('${snapshot['documentType'] == 'purchase' ? 'فروشنده' : 'مشتری'}: ${snapshot['counterpartyName'] ?? ''}'),
                    Text('تاریخ: ${snapshot['documentDate'] ?? ''}'),
                    const SizedBox(height: 8),
                    for (final item in items)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(item['productName']?.toString() ?? ''),
                        subtitle: Text(
                          'تعداد: ${item['quantity']} × ${item['unitPrice']} $currency',
                        ),
                        trailing: Text('${item['lineTotal']} $currency'),
                      ),
                    const Divider(),
                    Text('جمع: ${snapshot['subtotal']} $currency'),
                    Text('تخفیف: ${snapshot['discountAmount']} $currency'),
                    Text('هزینه‌های جانبی: ${snapshot['chargesAmount']} $currency'),
                    Text('ارزش افزوده: ${snapshot['vatAmount']} $currency'),
                    Text('مبلغ نهایی: ${snapshot['totalAmount']} $currency'),
                    Text('پرداخت‌شده: ${snapshot['paidAmount']} $currency'),
                    Text('مانده: ${snapshot['outstandingAmount']} $currency'),
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
    final discount = _previewDiscount;
    final vatRate = _double(_vatRateController);
    final paid = _int(_paidController);
    if (discount < 0 || discount > _subtotal) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تخفیف باید بین صفر و جمع کالاها باشد')),
      );
      return;
    }
    if (!vatRate.isFinite || vatRate < 0 || vatRate > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('درصد ارزش افزوده باید بین صفر تا ۱۰۰ باشد')),
      );
      return;
    }
    if (_previewCharges < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هزینه‌های جانبی نمی‌توانند منفی باشند')),
      );
      return;
    }
    if (paid < 0 || paid > _previewTotal) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('پرداخت اولیه باید بین صفر و مبلغ نهایی فاکتور باشد')),
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
      final invoiceSettings = await DemoStore.invoiceSettings.getSettings();
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
      final configuredPrefix = invoiceSettings['invoicePrefix'];
      if (_isPurchase) {
        await DemoStore.trades.recordPurchase(
          draft,
          invoiceHeaderSnapshot: invoiceSettings,
          documentPrefix: configuredPrefix,
        );
      } else {
        await DemoStore.trades.recordSale(
          draft,
          invoiceHeaderSnapshot: invoiceSettings,
          documentPrefix: configuredPrefix,
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
        _discountManuallyEdited = false;
        _applyDefaultDiscount();
        _paidController.text = '0';
        _shippingController.text = '0';
        _freightController.text = '0';
        _otherCostController.text = '0';
        _vatExempt = false;
      });
      widget.onChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isPurchase ? 'فاکتور خرید ثبت و بایگانی شد' : 'فاکتور فروش ثبت و بایگانی شد')),
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
                        inputFormatters: const [NumericInputFormatter(allowDecimal: true)],
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
                  final quantity = LocalizedNumber.tryParseDouble(quantityController.text);
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
    String paymentMethod = 'cash';
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
                        inputFormatters: const [NumericInputFormatter()],
                  decoration: InputDecoration(
                    labelText: 'مبلغ',
                    helperText: 'مانده فاکتور: $outstanding $_currency',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: paymentMethod,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'روش دریافت / پرداخت'),
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('نقدی')),
                    DropdownMenuItem(value: 'bank_transfer', child: Text('انتقال بانکی')),
                    DropdownMenuItem(value: 'card_to_card', child: Text('کارت‌به‌کارت')),
                  ],
                  onChanged: (value) => refresh(() => paymentMethod = value ?? 'cash'),
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
                  final value = LocalizedNumber.tryParseInt(amountController.text);
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
        cashAccountCode: paymentMethod == 'cash' ? '1000' : '1010',
        paymentMethod: paymentMethod,
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
                      (party['display_name']?.toString() ?? '') +
                          ((party['phone']?.toString().trim().isNotEmpty ?? false)
                              ? ' • ${party['phone']}'
                              : ''),
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
          Align(
            alignment: Alignment.centerRight,
            child: Tooltip(
              message: 'افزودن مخاطب جدید در فاکتور',
              child: TextButton.icon(
                key: const ValueKey('inline-add-trade-party'),
                onPressed: _saving ? null : _addPartyInline,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('افزودن مخاطب جدید'),
              ),
            ),
          ),
          const SizedBox(height: 4),
          PhoneContactPickerButton(
            label: _isPurchase
                ? 'انتخاب فروشنده از مخاطبین گوشی'
                : 'انتخاب مشتری از مخاطبین گوشی',
            onSelected: _selectPhoneParty,
          ),
          const SizedBox(height: 4),
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
                        inputFormatters: const [NumericInputFormatter(allowDecimal: true)],
                  decoration: const InputDecoration(labelText: 'تعداد'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                        textInputAction: TextInputAction.next,
                  controller: _priceController,
                  keyboardType: TextInputType.number,
                        inputFormatters: const [NumericInputFormatter()],
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
                    'تعداد: ${_lines[i].quantity} × ${_lines[i].unitPrice} $_currency',
                  ),
                  trailing: IconButton(
                    tooltip: 'حذف ردیف',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() {
                      _lines.removeAt(i);
                      _applyDefaultDiscount();
                    }),
                  ),
                ),
              ),
          ],
          const Divider(height: 24),
          TextField(
                        textInputAction: TextInputAction.next,
            controller: _discountController,
            onChanged: (_) => setState(() => _discountManuallyEdited = true),
            keyboardType: TextInputType.number,
                        inputFormatters: const [NumericInputFormatter()],
            decoration: InputDecoration(labelText: 'تخفیف کل ($_currency)'),
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
                        inputFormatters: const [NumericInputFormatter(allowDecimal: true)],
              decoration: const InputDecoration(labelText: 'درصد ارزش افزوده'),
            ),
          if (_isPurchase) ...[
            const SizedBox(height: 10),
            TextField(
                        textInputAction: TextInputAction.next,
              controller: _shippingController,
              onChanged: (_) => setState(() {}),
              keyboardType: TextInputType.number,
                        inputFormatters: const [NumericInputFormatter()],
              decoration: const InputDecoration(labelText: 'هزینه پست'),
            ),
            const SizedBox(height: 10),
            TextField(
                        textInputAction: TextInputAction.next,
              controller: _freightController,
              onChanged: (_) => setState(() {}),
              keyboardType: TextInputType.number,
                        inputFormatters: const [NumericInputFormatter()],
              decoration: const InputDecoration(labelText: 'هزینه باربری / حمل'),
            ),
            const SizedBox(height: 10),
            TextField(
                        textInputAction: TextInputAction.next,
              controller: _otherCostController,
              onChanged: (_) => setState(() {}),
              keyboardType: TextInputType.number,
                        inputFormatters: const [NumericInputFormatter()],
              decoration: const InputDecoration(labelText: 'سایر هزینه‌های خرید'),
            ),
          ],
          const SizedBox(height: 10),
          TextField(
                        textInputAction: TextInputAction.next,
            controller: _paidController,
            keyboardType: TextInputType.number,
                        inputFormatters: const [NumericInputFormatter()],
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
                  Text('جمع ردیف‌ها: $_subtotal $_currency'),
                  Text('تخفیف: $_previewDiscount $_currency'),
                  if (_isPurchase)
                    Text('هزینه‌های جانبی: $_previewCharges $_currency'),
                  Text('ارزش افزوده: $_previewVat $_currency'),
                  Text('مبلغ نهایی: $_previewTotal $_currency'),
                  Text('مانده پس از پرداخت اولیه: $_previewBalance $_currency'),
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
                    Text('مبلغ: ${document['total_amount']} $_currency  •  پرداخت اولیه: ${document['paid_amount']} $_currency'),
                    Text('مانده: ${document['outstanding_amount']} $_currency'),
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
  @override
  State<AppSettingsPage> createState() => _AppSettingsPageState();
}

class _AppSettingsPageState extends State<AppSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  final _controllers = <String, TextEditingController>{
    for (final key in ['appName', 'shopName', 'ownerName', 'phone', 'postalCode', 'address', 'vatPercent', 'defaultDiscount', 'invoicePrefix'])
      key: TextEditingController(),
  };
  String _currency = 'تومان';
  String _logoBase64 = '';
  bool _loading = true;
  bool _saving = false;
  bool _pickingLogo = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final values = await DemoStore.invoiceSettings.getSettings();
      for (final entry in _controllers.entries) {
        entry.value.text = values[entry.key] ?? '';
      }
      if (mounted) {
        setState(() {
          _currency = values['currency'] ?? 'تومان';
          DemoStore.appName.value = values['appName'] ?? 'خدمات فنی حسین';
          _logoBase64 = values['appLogoBase64'] ?? '';
          DemoStore.appLogo.value = _logoBase64.isEmpty ? null : _logoBase64;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خواندن تنظیمات ناموفق بود: $error')),
        );
      }
    }
  }

  Future<bool> _confirmLogoRequirements() async {
    Timer? autoOpenTimer;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        autoOpenTimer = Timer(const Duration(seconds: 3), () {
          if (dialogContext.mounted && Navigator.of(dialogContext).canPop()) {
            Navigator.of(dialogContext).pop(true);
          }
        });
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Row(
              children: [
                const Expanded(child: Text('راهنمای انتخاب لوگو')),
                IconButton(
                  tooltip: 'بستن راهنما',
                  onPressed: () {
                    autoOpenTimer?.cancel();
                    Navigator.pop(dialogContext, false);
                  },
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            content: const SingleChildScrollView(
              child: Text(
                'لوگو فقط روی همین گوشی ذخیره می‌شود و در سربرگ برنامه و کنار نام فروشگاه نمایش داده می‌شود.\\n\\n'
                'فرمت مجاز: JPG، JPEG و PNG\\n'
                'ابعاد پیشنهادی: ۵۱۲ × ۵۱۲ پیکسل (مربع)\\n'
                'حداکثر حجم فایل: ۱ مگابایت\\n'
                'پیشنهاد: PNG با پس‌زمینه شفاف یا JPG با پس‌زمینه سفید. تصویر واضح و بدون نوشته‌های ریز انتخاب کنید.\\n\\n'
                'برای باز شدن گالری، «برو به گالری» را بزنید؛ در غیر این صورت تا سه ثانیه دیگر گالری خودکار باز می‌شود.',
              ),
            ),
            actions: [
              FilledButton.icon(
                onPressed: () {
                  autoOpenTimer?.cancel();
                  Navigator.pop(dialogContext, true);
                },
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('برو به گالری'),
              ),
            ],
          ),
        );
      },
    );
    autoOpenTimer?.cancel();
    return confirmed == true;
  }

  Future<void> _pickLogo() async {
    if (_pickingLogo) return;
    if (!await _confirmLogoRequirements() || !mounted) return;
    setState(() => _pickingLogo = true);
    try {
      // PNG is accepted and kept as PNG so transparent backgrounds remain intact.
      // JPG/JPEG inputs are resized and recompressed as JPEG to reduce storage.
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
      );
      if (picked == null) return;
      final isPng = picked.path.toLowerCase().endsWith('.png');
      final bytes = await FlutterImageCompress.compressWithFile(
        picked.path,
        minWidth: 512,
        minHeight: 512,
        quality: 65,
        format: isPng ? CompressFormat.png : CompressFormat.jpeg,
      );
      if (bytes == null || bytes.isEmpty) {
        throw StateError('فشرده‌سازی لوگو انجام نشد');
      }
      if (bytes.length > 1024 * 1024) {
        throw ArgumentError('حجم لوگو پس از فشرده‌سازی باید حداکثر ۱ مگابایت باشد');
      }
      final encoded = base64Encode(bytes);
      if (mounted) setState(() => _logoBase64 = encoded);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('انتخاب لوگو ناموفق بود: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _pickingLogo = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await DemoStore.invoiceSettings.saveSettings({
        for (final entry in _controllers.entries) entry.key: entry.value.text,
        'currency': _currency,
        'appLogoBase64': _logoBase64,
      });
      DemoStore.appLogo.value = _logoBase64.isEmpty ? null : _logoBase64;
      DemoStore.appName.value =
          _controllers['appName']!.text.trim().isEmpty
              ? 'خدمات فنی حسین'
              : _controllers['appName']!.text.trim();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تنظیمات و لوگوی فروشگاه ذخیره شد.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ذخیره ناموفق بود: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _field(String key, String label, {TextInputType? type, int lines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: _controllers[key],
        keyboardType: type ?? numericKeyboardTypeForField(label),
        inputFormatters: numericInputFormattersForField(
          label,
          forceNumeric: type == TextInputType.phone || type == TextInputType.number,
        ),
        maxLines: lines,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        validator: (value) {
          final numericError = validateNumericField(
            label,
            value,
            forceNumeric: type == TextInputType.phone || type == TextInputType.number,
          );
          if (numericError != null) return numericError;
          if ((key == 'shopName' || key == 'ownerName') &&
              (value == null || value.trim().isEmpty)) {
            return 'این فیلد الزامی است';
          }
          if (key == 'vatPercent' || key == 'defaultDiscount') {
            final number = LocalizedNumber.tryParseDouble(value ?? '');
            if (number == null || number < 0 || number > 100) {
              return 'عدد باید بین صفر تا ۱۰۰ باشد';
            }
          }
          return null;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: const Text('تنظیمات برنامه')),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      16,
                      16,
                      MediaQuery.viewPaddingOf(context).bottom + 24,
                    ),
                    children: [
                      Text('لوگوی فروشگاه', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 10),
                      Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: _logoBase64.isEmpty
                              ? Image.asset('assets/logo.jpg', width: 112, height: 112, fit: BoxFit.cover)
                              : Image.memory(base64Decode(_logoBase64), width: 112, height: 112, fit: BoxFit.cover),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _pickingLogo ? null : _pickLogo,
                            icon: _pickingLogo
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.photo_library_outlined),
                            label: Text(_logoBase64.isEmpty ? 'انتخاب لوگو از گالری' : 'تعویض لوگو'),
                          ),
                          if (_logoBase64.isNotEmpty)
                            TextButton.icon(
                              onPressed: () => setState(() => _logoBase64 = ''),
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('حذف لوگوی اختصاصی'),
                            ),
                        ],
                      ),
                      const Divider(height: 28),
                      Text('اطلاعات برنامه و فروشگاه', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      _field('appName', 'نام برنامه'),
                      _field('shopName', 'نام فروشگاه'),
                      _field('ownerName', 'نام مسئول'),
                      _field('phone', 'شماره تماس', type: TextInputType.phone),
                      _field('postalCode', 'کد پستی'),
                      _field('address', 'نشانی', lines: 2),
                      const Divider(height: 28),
                      Text('تنظیمات مالی', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _currency,
                        decoration: const InputDecoration(labelText: 'واحد پول', border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(value: 'تومان', child: Text('تومان')),
                          DropdownMenuItem(value: 'ریال', child: Text('ریال')),
                        ],
                        onChanged: (value) => setState(() => _currency = value ?? 'تومان'),
                      ),
                      const SizedBox(height: 12),
                      _field('vatPercent', 'درصد مالیات بر ارزش افزوده', type: const TextInputType.numberWithOptions(decimal: true)),
                      _field('defaultDiscount', 'درصد تخفیف پیش‌فرض', type: const TextInputType.numberWithOptions(decimal: true)),
                      _field('invoicePrefix', 'پیشوند شماره فاکتور'),
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.save_outlined),
                        label: const Text('ذخیره تنظیمات'),
                      ),
                    ],
                  ),
                ),
        ),
      );
}
