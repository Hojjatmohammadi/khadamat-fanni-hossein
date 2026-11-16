import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khadamat_fanni_hosein/main.dart';

void main() {
  testWidgets('home screen shows only the requested category cards',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const HoseinApp());

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
    expect(find.text('گزارش‌ها'), findsOneWidget);
    expect(find.text('دفتر روزنامه و هزینه‌ها'), findsOneWidget);

    await tester.tap(find.text('گزارش‌ها'));
    await tester.pumpAndSettle();
    expect(find.text('گزارش‌ها'), findsOneWidget);
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
    };

    for (final entry in destinations.entries) {
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.text(entry.value), findsWidgets,
          reason: 'Home card "${entry.key}" must open "${entry.value}"');

      // Exercise the app's own back-navigation history instead of relying
      // on a drawer animation in a widget test.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
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
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.text(entry.value), findsWidgets,
          reason: 'Other operation "${entry.key}" did not open');

      // Exercise the app's own back-navigation history instead of relying
      // on a drawer animation in a widget test.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }
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

}
