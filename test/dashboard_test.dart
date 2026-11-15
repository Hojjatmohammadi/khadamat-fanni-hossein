import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khadamat_fanni_hosein/main.dart';

void main() {
  testWidgets('dashboard keeps quick actions inside a safe scrolling area',
      (tester) async {
    final selectedTabs = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Dashboard(onSelect: selectedTabs.add),
        ),
      ),
    );

    expect(find.byType(SafeArea), findsOneWidget);
    expect(find.byType(ListView), findsOneWidget);

    // The quick actions intentionally live below the summary cards and may
    // be lazily built only after scrolling on smaller test viewports.
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();

    expect(find.text('دسترسی سریع'), findsOneWidget);
    expect(find.text('خدمات فنی حسین'), findsNothing);
    expect(find.text('ثبت کالا'), findsOneWidget);
    expect(find.text('ثبت مشتری'), findsOneWidget);

    await tester.ensureVisible(find.text('ثبت کالا'));
    await tester.tap(find.text('ثبت کالا'));
    expect(selectedTabs, contains(1));
  });

  testWidgets('home app bar shows shop branding instead of dashboard title and exposes search and add',
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

    await tester.tap(find.byTooltip('جست‌وجوی سراسری'));
    await tester.pumpAndSettle();
    expect(find.text('جست‌وجوی سراسری'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    await tester.tap(find.text('بستن'));
    await tester.pumpAndSettle();
  });

}
