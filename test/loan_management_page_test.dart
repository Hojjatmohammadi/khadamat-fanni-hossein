import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:khadamat_fanni_hosein/app_database.dart';
import 'package:khadamat_fanni_hosein/loan_management_page.dart';
import 'package:khadamat_fanni_hosein/loan_repository.dart';

Future<void> _waitForText(WidgetTester tester, String value) async {
  final finder = find.text(value);
  for (var attempt = 0; attempt < 150; attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  throw StateError('متن مورد انتظار در صفحه قرض‌ها ظاهر نشد: $value');
}

Finder _field(String label) => find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == label,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory directory;
  late AppDatabase database;
  late LoanRepository repository;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('loan_page_widget_test_');
    database = AppDatabase(databasePath: '${directory.path}/loan-page.db');
    repository = LoanRepository(database);
    await database.database;
  });

  tearDown(() async {
    await database.close();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  testWidgets(
    'loan form uses Jalali date fields and rejects a due date before the loan date',
    (tester) async {
      tester.view.physicalSize = const Size(430, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fa'),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: LoanManagementPage(repository: repository),
        ),
      );
      await _waitForText(tester, 'ثبت قرض دریافتی و برنامه اقساط');

      final loanDate = _field('تاریخ دریافت قرض');
      final dueDate = _field('تاریخ اولین سررسید');
      expect(loanDate, findsOneWidget);
      expect(dueDate, findsOneWidget);
      expect(find.byTooltip('انتخاب تاریخ شمسی'), findsNWidgets(2));
      expect(
        parseJalaliDate(tester.widget<TextField>(loanDate).controller!.text),
        isNotNull,
      );

      await tester.enterText(_field('نام شخص قرض‌دهنده'), 'قرض‌دهنده آزمایشی');
      await tester.enterText(_field('اصل مبلغ قرض (تومان)'), '۹۰۰۰');
      await tester.enterText(loanDate, '۱۴۰۵/۰۹/۱۰');
      await tester.pump();
      await tester.enterText(dueDate, '۱۴۰۵/۰۹/۰۹');
      await tester.pump();

      await tester.tap(find.text('ثبت قرض و ایجاد اقساط'));
      await tester.pump();
      await _waitForText(
        tester,
        'نام قرض‌دهنده، مبلغ، تاریخ دریافت، سررسید و تعداد اقساط را صحیح وارد کنید',
      );

      final loans = await tester.runAsync(repository.getLoans);
      expect(loans, isEmpty,
          reason: 'A due date before the loan date must never create a loan');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'same-day Jalali due date is accepted when only the due field is edited',
    (tester) async {
      tester.view.physicalSize = const Size(430, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fa'),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: LoanManagementPage(repository: repository),
        ),
      );
      await _waitForText(tester, 'ثبت قرض دریافتی و برنامه اقساط');

      await tester.enterText(_field('نام شخص قرض‌دهنده'), 'قرض‌دهنده همان‌روز');
      await tester.enterText(_field('اصل مبلغ قرض (تومان)'), '۹۰۰۰');
      await tester.enterText(
        _field('تاریخ اولین سررسید'),
        formatJalaliDate(DateTime.now()),
      );
      await tester.pump();

      await tester.tap(find.text('ثبت قرض و ایجاد اقساط'));
      await tester.pump();
      await _waitForText(
        tester,
        'قرض ثبت شد؛ مبلغ به بدهی اضافه شد و درآمد محسوب نشد',
      );

      final loans = await tester.runAsync(repository.getLoans);
      expect(loans, hasLength(1));
      expect(loans!.single['remaining_amount'], 9000);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

 } 
