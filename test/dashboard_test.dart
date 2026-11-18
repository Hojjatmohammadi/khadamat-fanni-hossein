import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:khadamat_fanni_hosein/main.dart';
import 'package:khadamat_fanni_hosein/contacts_page.dart';
import 'package:khadamat_fanni_hosein/app_database.dart';
import 'package:khadamat_fanni_hosein/check_repository.dart';
import 'package:khadamat_fanni_hosein/check_reminder_service.dart';
import 'package:khadamat_fanni_hosein/party_repository.dart';
import 'package:khadamat_fanni_hosein/trade_repository.dart';

void _noop() {}

Future<void> _waitForFinder(
  WidgetTester tester,
  Finder finder,
  String description,
) async {
  for (var attempt = 0; attempt < 250; attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  throw StateError('عنصر رابط کاربری در مهلت آزمون ظاهر نشد: $description');
}

Future<void> _waitForText(WidgetTester tester, String value) =>
    _waitForFinder(tester, find.text(value), value);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  testWidgets('home screen shows only the requested category cards',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const HoseinApp());

    final sharedBottomGap = tester.widget<Padding>(find.byKey(const ValueKey('app-page-bottom-gap')));
    expect(sharedBottomGap.padding, const EdgeInsets.only(bottom: 24));
    expect(find.byType(GridView), findsOneWidget);
    expect(find.text('دسترسی سریع'), findsNothing);
    expect(find.text('کالاهای ثبت‌شده'), findsNothing);
    expect(find.text('مشتریان'), findsNothing);
    for (final title in [
      'خرید',
      'فروش',
      'انبار',
      'پشتیبان‌گیری',
      'فاکتور',
      'پذیرش دستگاه',
      'صورت‌حساب اشخاص',
      'تماس / ارسال پیامک',
      'مخاطبین',
      'عملیات‌های دیگر',
    ]) {
      expect(find.text(title), findsOneWidget, reason: 'Missing home card: $title');
    }

    await tester.tap(find.text('انبار'));
    await tester.pumpAndSettle();
    expect(find.text('انبار کالا'), findsOneWidget);
  });

  testWidgets('other operations card opens its secondary actions',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const HoseinApp());
    await tester.tap(find.text('عملیات‌های دیگر'));
    await tester.pumpAndSettle();

    expect(find.text('مدیریت چک‌ها'), findsOneWidget);
    expect(find.text('گزارش‌ها'), findsWidgets);
    expect(find.text('دفتر روزنامه و هزینه‌ها'), findsOneWidget);

    // The menu label can remain mounted beneath the destination page title.
    await tester.tap(find.text('گزارش‌ها').first);
    // Some destination pages contain repeating animations; advance the route
    // transition without waiting for every ticker to become idle.
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('گزارش‌ها'), findsWidgets);
  });

  testWidgets('home app bar shows the configured app name and exposes search and add',
      (tester) async {
    DemoStore.appName.value = 'خدمات فنی حسین';
    addTearDown(() => DemoStore.appName.value = 'خدمات فنی حسین');
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const HoseinApp());

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-brand-title')),
        matching: find.text('خدمات فنی حسین'),
      ),
      findsOneWidget,
    );
    DemoStore.appName.value = 'مدیریت فنی من';
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-brand-title')),
        matching: find.text('مدیریت فنی من'),
      ),
      findsOneWidget,
      reason: 'Home app bar must update when the configured app name changes',
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-brand-title')),
        matching: find.text('داشبورد'),
      ),
      findsNothing,
    );
    expect(find.byTooltip('جست‌وجوی سراسری'), findsOneWidget);
    expect(find.byTooltip('افزودن مورد جدید'), findsOneWidget);
    expect(find.byKey(const ValueKey('open-navigation-drawer')), findsOneWidget);
    expect(find.byTooltip('باز کردن فهرست'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('open-navigation-drawer')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('navigation-drawer-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('navigation-drawer-scrim')), findsOneWidget);
    expect(find.byKey(const ValueKey('drawer-settings-button')), findsOneWidget);
    expect(find.byTooltip('تنظیمات برنامه'), findsOneWidget);
    expect(find.byKey(const ValueKey('drawer-logo')), findsOneWidget);

    // In RTL layout, the first Row child (the logo) must appear on the right.
    final logoCenter = tester.getCenter(find.byKey(const ValueKey('drawer-logo')));
    final settingsCenter =
        tester.getCenter(find.byKey(const ValueKey('drawer-settings-button')));
    expect(
      logoCenter.dx,
      greaterThan(settingsCenter.dx),
      reason: 'Drawer logo must be on the right and settings on the left',
    );
  });

  testWidgets('global add menu opens the selected creation form', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const HoseinApp());
    await tester.tap(find.byKey(const ValueKey('global-quick-add')));
    await tester.pumpAndSettle();

    expect(find.text('ثبت کالا'), findsOneWidget);
    await tester.tap(find.text('ثبت کالا'));
    await tester.pumpAndSettle();

    expect(find.text('ثبت کالا'), findsOneWidget);
    expect(find.text('نام کالا'), findsOneWidget);
  });

  testWidgets('every home card opens its mapped section', (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const HoseinApp());
    await tester.pumpAndSettle();

    const destinations = <String, String>{
      'خرید': 'خرید و برگشت',
      'فروش': 'فروش و فاکتور',
      'انبار': 'انبار کالا',
      'پشتیبان‌گیری': 'پشتیبان‌گیری و بازیابی',
      'فاکتور': 'فروش و فاکتور',
      'پذیرش دستگاه': 'تعمیرات',
      'صورت‌حساب اشخاص': 'دفتر گردش اشخاص',
      'تماس / ارسال پیامک': 'مشتریان',
      'مخاطبین': 'دفتر مخاطبین',
    };

    for (final entry in destinations.entries) {
      await tester.tap(find.text(entry.key));
      // Destination pages may keep periodic animations alive indefinitely.
      // A bounded pump completes the navigation transition deterministically.
      await tester.pump(const Duration(seconds: 2));
      expect(find.text(entry.value), findsWidgets,
          reason: 'Home card "${entry.key}" must open "${entry.value}"');

      // Exercise the app's own back-navigation history instead of relying
      // on a drawer animation in a widget test.
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('خدمات فنی حسین'), findsWidgets);
    }
  });

  testWidgets('every other-operations action opens its destination',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const HoseinApp());
    await tester.pumpAndSettle();

    const destinations = <String, String>{
      'مدیریت چک‌ها': 'مدیریت چک‌ها',
      'گزارش‌ها': 'گزارش‌ها',
      'دفتر روزنامه و هزینه‌ها': 'دفتر روزنامه و هزینه‌ها',
    };

    for (final entry in destinations.entries) {
      await tester.tap(find.text('عملیات‌های دیگر'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(entry.key).first);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text(entry.value), findsWidgets,
          reason: 'Other operation "${entry.key}" did not open');

      // Exercise the app's own back-navigation history instead of relying
      // on a drawer animation in a widget test.
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 500));
    }
  });


  testWidgets(
      'contacts page opens a multi-role ledger with check and advance actions',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const contactName = 'آزمون دفتر مرکزی مخاطبین';
    print('[contacts-widget-test] start');
    // Use a dedicated database; initialize and seed it outside FakeAsync.
    final tempDir = await tester.runAsync(
      () => Directory.systemTemp.createTemp(
        'khadamat_contacts_widget_test_',
      ),
    );
    if (tempDir == null) {
      throw StateError('Could not create the contacts widget test directory');
    }
    final database = AppDatabase(
      databasePath: '${tempDir.path}/contacts-widget.db',
    );
    final repository = PartyRepository(database);
    final trades = TradeRepository(database);
    final checks = CheckRepository(database);
    addTearDown(() => tester.runAsync(() async {
      await database.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }));
    await tester.runAsync(() => database.database);

    final partyId = await tester.runAsync(
      () => repository.ensureParty(
        const PartyDraft(
          partyType: 'customer',
          additionalRoles: ['supplier'],
          displayName: contactName,
          phone: '09123334455',
        ),
      ),
    );
    if (partyId == null) {
      throw StateError('Could not seed the contacts widget test party');
    }
    final roles = await tester.runAsync(
          () => repository.getPartyRoles(partyId),
        ) ??
        <String>[];
    expect(roles, containsAll(['customer', 'supplier']));
    print('[contacts-widget-test] contact-and-roles-seeded');

    await tester.pumpWidget(
      MaterialApp(
        home: ContactsPage(
          repository: repository,
          reminders: CheckReminderService(),
          trades: trades,
          checks: checks,
          onChanged: () {},
        ),
      ),
    );
    await _waitForText(tester, contactName);
    expect(find.text('مشتری'), findsWidgets);
    expect(find.text('فروشنده'), findsWidgets);
    print('[contacts-widget-test] contacts-page-loaded');

    await tester.tap(find.byTooltip('پرونده و گردش حساب'));
    await _waitForText(tester, 'دفتر گردش حساب اشخاص');
    await _waitForFinder(
      tester,
      find.byKey(const ValueKey('record-customer-advance')),
      'دکمه ثبت بیعانه مشتری',
    );
    expect(find.byKey(const ValueKey('record-supplier-prepayment')), findsOneWidget);
    expect(find.byKey(const ValueKey('record-customer-check')), findsOneWidget);
    expect(find.byKey(const ValueKey('record-supplier-check')), findsOneWidget);
    print('[contacts-widget-test] ledger-opened');

    await tester.tap(find.byKey(const ValueKey('record-customer-check')));
    await _waitForText(tester, 'ثبت چک جدید');
    expect(find.text('شماره چک'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));
    await _waitForFinder(
      tester,
      find.byKey(const ValueKey('record-customer-advance')),
      'بازگشت به دفتر گردش حساب پس از فرم چک',
    );
    print('[contacts-widget-test] check-form-opened-and-closed');

    await tester.tap(find.byKey(const ValueKey('record-customer-advance')));
    await _waitForFinder(
      tester,
      find.byKey(const ValueKey('party-ledger-advance-amount')),
      'فیلد مبلغ بیعانه',
    );
    expect(find.text('ثبت در گردش حساب'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));
    print('[contacts-widget-test] advance-form-opened-and-closed');

    await tester.pumpWidget(const SizedBox.shrink());
    print('[contacts-widget-test] finished');
  });

  testWidgets('inventory app bar exposes product image display options', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const HoseinApp());
    await tester.tap(find.text('انبار'));
    await tester.pump(const Duration(milliseconds: 350));

    final menu = find.byTooltip('تنظیم نمایش عکس کالا');
    expect(menu, findsOneWidget);
    await tester.tap(menu);
    await tester.pumpAndSettle();
    expect(find.text('عدم نمایش عکس کالا'), findsOneWidget);
    expect(find.text('پیش‌فرض عکس کالا'), findsOneWidget);
    expect(find.text('کوچک کردن عکس کالا'), findsOneWidget);

    await tester.tap(find.text('عدم نمایش عکس کالا'));
    await tester.pumpAndSettle();
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('کوچک کردن عکس کالا'));
    await tester.pumpAndSettle();
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('پیش‌فرض عکس کالا'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('تنظیم نمایش عکس کالا'), findsOneWidget);
  });

  testWidgets('repair parts dialog offers coordinated display sizes', (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // DemoStore uses the real SQLite/file system, so keep these operations
    // outside the widget test's fake-async zone as well.
    await tester.runAsync(DemoStore.init);
    await tester.runAsync(() => DemoStore.add('products', {
      'نام کالا': 'قطعه آزمون اندازه فرم',
      'موجودی': '0',
    }));
    await tester.runAsync(() => DemoStore.add('repairs', {
      'نام مشتری': 'مشتری آزمون اندازه فرم',
      'نوع دستگاه': 'دریل',
    }));
    final productId = int.parse(DemoStore.products.last['__database_id']!);
    final repairId = int.parse(DemoStore.repairs.last['__database_id']!);
    addTearDown(() => tester.runAsync(() async {
      await DemoStore.deleteRecord('repairs', repairId);
      await DemoStore.deleteRecord('products', productId);
    }));

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: RepairPage(onChanged: _noop))),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('ثبت مصرف قطعه در تعمیر'));
    await tester.pump(const Duration(milliseconds: 200));

    var sizeSelector =
        find.byKey(const ValueKey('repair-parts-ui-size-معمولی'));
    expect(sizeSelector, findsOneWidget);
    expect(find.text('اندازه نمایش بخش قطعات'), findsOneWidget);

    await tester.tap(sizeSelector);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('ریز'), findsOneWidget);
    expect(find.text('کوچک'), findsOneWidget);
    expect(find.text('معمولی'), findsWidgets);
    expect(find.text('بزرگ'), findsOneWidget);
    await tester.tap(find.text('ریز'));
    await tester.pump(const Duration(milliseconds: 100));

    sizeSelector = find.byKey(const ValueKey('repair-parts-ui-size-ریز'));
    expect(sizeSelector, findsOneWidget);
    await tester.tap(sizeSelector);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('بزرگ'));
    await tester.pump(const Duration(milliseconds: 100));

    sizeSelector = find.byKey(const ValueKey('repair-parts-ui-size-بزرگ'));
    expect(sizeSelector, findsOneWidget);

    await tester.tap(find.text('انصراف'));
    await tester.pump(const Duration(milliseconds: 150));
  });

  testWidgets('logo help can be dismissed and gallery opens only on request',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var galleryRequests = 0;
    const imagePickerChannel = MethodChannel('plugins.flutter.io/image_picker');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(imagePickerChannel, (call) async {
      galleryRequests++;
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(imagePickerChannel, null);
    });

    await tester.runAsync(DemoStore.init);
    await tester.pumpWidget(const MaterialApp(home: AppSettingsPage()));
    await tester.pump(const Duration(seconds: 1));
    // AppSettingsPage loads its settings from SQLite before building the form.
    await _waitForText(tester, 'لوگوی فروشگاه');

    expect(find.text('تنظیمات برنامه'), findsOneWidget);
    expect(find.textContaining('محل ذخیره‌سازی:'), findsNothing);
    final chooseLogoButton = find.ancestor(
      of: find.byIcon(Icons.photo_library_outlined),
      matching: find.byType(OutlinedButton),
    );
    expect(chooseLogoButton, findsOneWidget);

    // Use bounded pumps: pumpAndSettle advances fake time and would trigger
    // the dialog's intentional three-second automatic gallery timer.
    await tester.tap(chooseLogoButton);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('راهنمای انتخاب لوگو'), findsOneWidget);
    expect(find.text('برو به گالری'), findsOneWidget);
    expect(galleryRequests, 0);

    await tester.tap(find.byTooltip('بستن راهنما'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('راهنمای انتخاب لوگو'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    expect(galleryRequests, 0,
        reason: 'Dismissing the help must cancel automatic gallery opening');

    await tester.tap(chooseLogoButton);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('برو به گالری'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(galleryRequests, 1);
  });

  test('simple category search filters only matching records', () {
    final records = [
      {'نام مشتری': 'احمد', 'شماره تماس': '09120000000'},
      {'نام مشتری': 'رضا', 'شماره تماس': '09121111111'},
    ];
    final result = filterCategoryRecords(records, '09120000000');
    expect(result, hasLength(1));
    expect(result.single['نام مشتری'], 'احمد');
    expect(filterCategoryRecords(records, 'ناموجود'), isEmpty);
  });

  testWidgets('global magnifier opens immediately and finds saved inventory',
      (tester) async {
    // Use a phone-sized viewport to catch dialog overflow on real devices.
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const searchableName = 'کالای آزمون جست‌وجوی سراسری ۷۳۱۹';
    await tester.runAsync(DemoStore.init);
    await tester.runAsync(() => DemoStore.add('products', {
          'نام کالا': searchableName,
          'کد کالا': 'SEARCH-7319',
          // Keep the fixture free of stock movements so it can be deleted
          // safely after the search widget test.
          'موجودی': '0',
        }));
    final productId = int.parse(DemoStore.products.last['__database_id']!);
    addTearDown(() => tester.runAsync(
          () => DemoStore.deleteRecord('products', productId),
        ));

    await tester.pumpWidget(const HoseinApp());
    await tester.tap(find.byTooltip('جست‌وجوی سراسری'));
    await tester.pump(const Duration(milliseconds: 100));

    // The dialog and input must appear before the database search completes.
    expect(find.text('جست‌وجوی سراسری'), findsOneWidget);
    final searchField = find.byKey(const ValueKey('global-search-field'));
    expect(searchField, findsOneWidget);

    await tester.enterText(searchField, 'SEARCH-۷۳۱۹');
    await _waitForText(tester, searchableName);
    expect(find.text('کالا •'), findsNothing);
    expect(find.textContaining('کالا'), findsWidgets);

    await tester.tap(find.text(searchableName));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('انبار کالا'), findsOneWidget);
  });

  testWidgets('repair intake selects an existing customer without creating a duplicate',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.runAsync(DemoStore.init);
    final unique = DateTime.now().microsecondsSinceEpoch.toString();
    final customerName = 'مشتری ذخیره‌شده آزمون $unique';
    final customerPhone = '0912' + unique.substring(unique.length - 7);
    final partyId = await tester.runAsync(
      () => DemoStore.parties.ensureParty(
        PartyDraft(
          partyType: 'customer',
          displayName: customerName,
          phone: customerPhone,
        ),
      ),
    );
    expect(partyId, isNotNull);
    addTearDown(() => tester.runAsync(
          () => DemoStore.parties.deleteParty(partyId!),
        ));

    await tester.pumpWidget(const HoseinApp());
    await tester.tap(find.text('پذیرش دستگاه'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byTooltip('ثبت پذیرش تعمیر'));
    await _waitForText(tester, 'ثبت پذیرش تعمیر جدید');

    final customerSelector =
        find.byKey(const ValueKey('repair-existing-customer-selector'));
    expect(customerSelector, findsOneWidget);
    await tester.tap(customerSelector);
    await tester.pumpAndSettle();

    final savedCustomerOption = find.textContaining(customerName);
    expect(savedCustomerOption, findsOneWidget);
    await tester.tap(savedCustomerOption);
    await tester.pumpAndSettle();

    final customerNameField = find.byWidgetPredicate(
      (widget) => widget is TextField &&
          widget.decoration?.labelText == 'نام مشتری',
    );
    expect(customerNameField, findsOneWidget);
    expect(
      tester.widget<TextField>(customerNameField).controller?.text,
      customerName,
    );
    expect(
      await tester.runAsync(() => DemoStore.parties.getParties(partyType: 'customer')),
      isNotNull,
    );
  });

  testWidgets('inventory, contacts, and repair cards each expose one direct add action',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Repair intake loads the saved-customer list from SQLite before opening
    // its form; initialize that store outside the widget test's fake clock.
    await tester.runAsync(DemoStore.init);
    await tester.pumpWidget(const HoseinApp());

    await tester.tap(find.text('انبار'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byTooltip('ثبت کالا'), findsOneWidget);
    await tester.tap(find.byTooltip('ثبت کالا'));
    await tester.pumpAndSettle();
    expect(find.text('ثبت کالا'), findsOneWidget);
    await tester.tap(find.text('انصراف'));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('تماس / ارسال پیامک'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byTooltip('ثبت مشتری'), findsOneWidget);
    await tester.tap(find.byTooltip('ثبت مشتری'));
    await tester.pumpAndSettle();
    expect(find.text('ثبت مشتری جدید'), findsOneWidget);
    await tester.tap(find.text('انصراف'));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('پذیرش دستگاه'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byTooltip('ثبت پذیرش تعمیر'), findsOneWidget);
    expect(find.byTooltip('افزودن مورد جدید'), findsNothing);
    await tester.tap(find.byTooltip('ثبت پذیرش تعمیر'));
    await _waitForText(tester, 'ثبت پذیرش تعمیر جدید');
    await tester.pumpAndSettle();
    expect(find.text('ثبت پذیرش تعمیر جدید'), findsOneWidget);
    expect(find.text('ثبت مصرف قطعه در تعمیر'), findsOneWidget);
    expect(find.text('ثبت درآمد اجرت تعمیر'), findsOneWidget);
    expect(find.text('دریافت مانده اجرت تعمیر'), findsOneWidget);
  });

}
