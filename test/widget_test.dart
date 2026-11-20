import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khadamat_fanni_hosein/main.dart';

void main() {
  testWidgets('startup failure shows an actionable recovery screen', (tester) async {
    await tester.pumpWidget(
      const StartupFailureApp(error: 'database initialization failed'),
    );

    expect(find.text('راه‌اندازی برنامه کامل نشد'), findsOneWidget);
    expect(find.text('database initialization failed'), findsOneWidget);
    expect(find.text('تلاش مجدد'), findsOneWidget);
  });

  testWidgets('Persian date formatter works inside a Flutter text field',
      (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextField(
            controller: controller,
            inputFormatters: [PersianDateInputFormatter()],
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '14050823');
    await tester.pump();

    expect(controller.text, '۱۴۰۵/۰۸/۲۳');
    controller.dispose();
  });
}
