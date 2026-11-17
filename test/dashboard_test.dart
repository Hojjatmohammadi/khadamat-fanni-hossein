import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:khadamat_fanni_hosein/main.dart';
import 'package:khadamat_fanni_hosein/contacts_page.dart';
import 'package:khadamat_fanni_hosein/app_database.dart';
import 'package:khadamat_fanni_hosein/party_repository.dart';

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

  testWidgets('home app bar shows shop branding and exposes search and add',
      (tester) async {
    await tester.pumpWidget(const HoseinApp());

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-brand-title')),
        matching: find.text('خدمات فنی حسین'),
      ),
      findsOneWidget,
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


  testWidgets('central contacts page creates a multi-role contact and opens its profile',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Keep this widget test independent from DemoStore.init(), which also
    // performs startup backup work and shares a process-wide database with
    // other widget tests.
    final tempDir = await Directory.systemTemp.createTemp(
      'khadamat_contacts_widget_test_',
    );
    final database = AppDatabase(
      databasePath: '${tempDir.path}/contacts-widget.db',
    );
    final repository = PartyRepository(database);
    addTearDown(() async {
      await database.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    await database.database;

    await tester.pumpWidget(
      MaterialApp(home: ContactsPage(repository: repository)),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byTooltip('افزودن مخاطب'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(
      find.byType(TextFormField).first,
      'آزمون دفتر مرکزی مخاطبین',
    );
    await tester.enterText(
      find.byType(TextFormField).at(1),
      '09123334455',
    );
    await tester.tap(find.text('فروشنده'));
    await tester.pump();
    await tester.tap(find.text('ذخیره مخاطب'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('آزمون دفتر مرکزی مخاطبین'), findsOneWidget);
    final party = (await repository.getParties()).singleWhere(
      (item) => item['display_name'] == 'آزمون دفتر مرکزی مخاطبین',
    );
    final roles = await repository.getPartyRoles(party['id'] as String);
    expect(roles, containsAll(['customer', 'supplier']));

    await tester.tap(find.byTooltip('پرونده و گردش حساب'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('دفتر گردش حساب اشخاص'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('حذف مخاطب'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.widgetWithText(FilledButton, 'حذف مخاطب'));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('آزمون دفتر مرکزی مخاطبین'), findsNothing);
    expect(await repository.getParties(), isEmpty);
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

    await DemoStore.init();
    await tester.pumpWidget(const MaterialApp(home: AppSettingsPage()));
    await tester.pump(const Duration(seconds: 1));

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

  testWidgets('inventory, contacts, and repair cards each expose one direct add action',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
    await tester.pumpAndSettle();
    expect(find.text('ثبت پذیرش تعمیر جدید'), findsOneWidget);
    expect(find.text('ثبت مصرف قطعه در تعمیر'), findsOneWidget);
    expect(find.text('ثبت درآمد اجرت تعمیر'), findsOneWidget);
    expect(find.text('دریافت مانده اجرت تعمیر'), findsOneWidget);
  });

}
