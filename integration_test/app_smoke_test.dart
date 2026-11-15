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
}
