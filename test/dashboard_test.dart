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
    expect(find.text('دسترسی سریع'), findsOneWidget);
    expect(find.text('ثبت کالا'), findsOneWidget);
    expect(find.text('ثبت مشتری'), findsOneWidget);

    await tester.ensureVisible(find.text('ثبت کالا'));
    await tester.tap(find.text('ثبت کالا'));
    expect(selectedTabs, contains(1));
  });
}
