import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:khadamat_fanni_hosein/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android emulator opens every primary section and global search',
      (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('خدمات فنی حسین'), findsWidgets);

    const sections = <String>[
      'انبار کالا',
      'خرید و برگشت',
      'مشتریان',
      'تعمیرات',
      'فروش و فاکتور',
      'دفتر گردش اشخاص',
      'مدیریت چک‌ها',
      'گزارش‌ها',
      'دفتر روزنامه و هزینه‌ها',
      'پشتیبان‌گیری و بازیابی',
    ];

    for (final section in sections) {
      await tester.tap(find.byTooltip('باز کردن فهرست'));
      await tester.pumpAndSettle();
      final drawerItem = find.widgetWithText(ListTile, section);
      expect(drawerItem, findsOneWidget, reason: 'Drawer item missing: $section');
      await tester.tap(drawerItem);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.text(section), findsWidgets,
          reason: 'Section did not render: $section');
    }

    await tester.tap(find.byTooltip('جست‌وجوی سراسری'));
    await tester.pumpAndSettle();
    expect(find.text('کالا، خرید، فروش، اشخاص، چک و حسابداری'), findsOneWidget);
    expect(find.text('بستن'), findsOneWidget);
  });
  testWidgets('Android emulator completes customer, stock, purchase, repair and sale workflows',
      (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    Future<void> openSection(String section) async {
      await tester.tap(find.byTooltip('باز کردن فهرست'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, section));
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    Future<void> fillField(String label, String value) async {
      final field = find.byWidgetPredicate(
        (widget) => widget is TextField && widget.decoration?.labelText == label,
      );
      expect(field, findsOneWidget, reason: 'Missing field: $label');
      await tester.enterText(field, value);
      await tester.pump();
    }

    // Create one customer and reuse the same customer in repair and sales.
    await openSection('مشتریان');
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await fillField('نام مشتری', 'مشتری آزمایشی شبیه‌ساز');
    await fillField('شماره تماس', '09120000001');
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('مشتری آزمایشی شبیه‌ساز'), findsWidgets);

    // Create a product in inventory.
    await openSection('انبار کالا');
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await fillField('نام کالا', 'قطعه آزمایشی شبیه‌ساز');
    await fillField('گروه اصلی', 'قطعات');
    await fillField('زیرگروه', 'آزمایشی');
    await fillField('کد کالا', 'EMU-001');
    await fillField('موجودی', '0');
    await fillField('قیمت خرید هر واحد', '1000');
    await fillField('قیمت فروش', '2000');
    await tester.tap(find.text('ذخیره کالا'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('قطعه آزمایشی شبیه‌ساز'), findsWidgets);

    // Buy stock so the later sale and repair consumption have real inventory.
    await openSection('خرید و برگشت');
    await fillField('نام فروشنده', 'فروشنده آزمایشی شبیه‌ساز');
    await fillField('تعداد', '5');
    await fillField('قیمت خرید واحد', '1000');
    await tester.tap(find.text('افزودن کالا به فاکتور'));
    await tester.pumpAndSettle();
    expect(find.text('قطعه آزمایشی شبیه‌ساز'), findsWidgets);
    await tester.ensureVisible(find.text('ثبت قطعی فاکتور'));
    await tester.tap(find.text('ثبت قطعی فاکتور'));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text('فاکتور خرید ثبت شد'), findsOneWidget);

    // Register a repair using the already-saved customer from the dropdown.
    await openSection('تعمیرات');
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    final customerDropdown = find.byKey(
      const ValueKey('repair-existing-customer-selector'),
    );
    expect(customerDropdown, findsOneWidget,
        reason: 'Repair intake must offer previously saved customers');
    await tester.tap(customerDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('مشتری آزمایشی شبیه‌ساز').last);
    await tester.pumpAndSettle();
    await fillField('نوع دستگاه', 'دریل آزمایشی');
    await fillField('شرح عیب', 'روشن نمی‌شود');
    await fillField('اجرت', '3000');
    await fillField('وضعیت تعمیر', 'در انتظار');
    final repairCustomerField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == 'نام مشتری',
    );
    expect(tester.widget<TextField>(repairCustomerField).controller?.text,
        'مشتری آزمایشی شبیه‌ساز');
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('دریل آزمایشی'), findsWidgets);

    // Consume one unit from inventory against the registered repair.
    await tester.tap(find.text('ثبت مصرف قطعه در تعمیر'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ثبت مصرف قطعه'));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text('مصرف قطعه و سند حسابداری ثبت شد'), findsOneWidget);

    // Sell one unit to the same saved customer and verify the invoice is archived.
    await openSection('فروش و فاکتور');
    final partyDropdown = find.byWidgetPredicate(
      (widget) => widget is DropdownButtonFormField<String> &&
          widget.decoration?.labelText?.startsWith('انتخاب از اشخاص ثبت‌شده') == true,
    );
    expect(partyDropdown, findsOneWidget);
    await tester.tap(partyDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('مشتری آزمایشی شبیه‌ساز').last);
    await tester.pumpAndSettle();
    await fillField('تعداد', '1');
    await fillField('قیمت فروش واحد', '2000');
    await tester.tap(find.text('افزودن کالا به فاکتور'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('ثبت قطعی فاکتور'));
    await tester.tap(find.text('ثبت قطعی فاکتور'));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text('فاکتور فروش ثبت و بایگانی شد'), findsOneWidget);

    // Confirm that the backup page loads and displays local backup controls.
    await openSection('پشتیبان‌گیری و بازیابی');
    expect(find.text('تهیه و ارسال نسخه پشتیبان'), findsOneWidget);
    expect(find.text('نسخه‌های ذخیره‌شده'), findsOneWidget);
  });

}
