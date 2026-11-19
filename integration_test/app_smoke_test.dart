import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:khadamat_fanni_hosein/app_database.dart';
import 'package:khadamat_fanni_hosein/check_repository.dart';
import 'package:khadamat_fanni_hosein/invoice_pdf_service.dart';
import 'package:khadamat_fanni_hosein/report_repository.dart';
import 'package:khadamat_fanni_hosein/trade_repository.dart';
import 'package:khadamat_fanni_hosein/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android emulator opens every primary section and global search',
      (tester) async {
    await app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('خدمات فنی حسین'), findsWidgets);
    final homeAppBar = find.byType(AppBar);
    expect(
      find.descendant(of: homeAppBar, matching: find.byTooltip('جست‌وجوی سراسری')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: homeAppBar, matching: find.byTooltip('افزودن مورد جدید')),
      findsOneWidget,
      reason: 'Global add must stay in the top app bar next to global search',
    );

    // Exercise every home card on the Android emulator and verify its destination.
    const homeCardDestinations = <String, String>{
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
    for (final entry in homeCardDestinations.entries) {
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.text(entry.value), findsWidgets,
          reason: 'Home card "${entry.key}" must open "${entry.value}"');
      await tester.tap(find.byTooltip('باز کردن فهرست'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'داشبورد'));
      await tester.pumpAndSettle();
    }

    // Exercise the three actions inside the "other operations" home card.
    const otherDestinations = <String>[
      'مدیریت چک‌ها',
      'گزارش‌ها',
      'دفتر روزنامه و هزینه‌ها',
    ];
    for (final destination in otherDestinations) {
      await tester.tap(find.text('عملیات‌های دیگر'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(destination));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.text(destination), findsWidgets,
          reason: 'Other operation did not open: $destination');
      await tester.tap(find.byTooltip('باز کردن فهرست'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'داشبورد'));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.byTooltip('افزودن مورد جدید'));
    await tester.pumpAndSettle();
    expect(find.text('ثبت کالا'), findsOneWidget);
    await tester.tap(find.text('ثبت کالا'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('انبار کالا'), findsWidgets);

    final inventoryAppBar = find.byType(AppBar);
    expect(
      find.descendant(of: inventoryAppBar, matching: find.byTooltip('ثبت کالا')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: inventoryAppBar, matching: find.byTooltip('تنظیم نمایش عکس کالا')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('تنظیم نمایش عکس کالا'));
    await tester.pumpAndSettle();
    for (final option in const [
      'عدم نمایش عکس کالا',
      'پیش‌فرض عکس کالا',
      'کوچک کردن عکس کالا',
    ]) {
      expect(find.text(option), findsOneWidget);
    }
    await tester.tap(find.text('پیش‌فرض عکس کالا'));
    await tester.pumpAndSettle();

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
    await app.main();
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

    Future<void> fillFormField(String label, String value) async {
      final field = find.ancestor(
        of: find.text(label),
        matching: find.byType(TextFormField),
      );
      expect(field, findsOneWidget, reason: 'Missing form field: $label');
      await tester.enterText(field, value);
      await tester.pump();
    }

    // Create one customer and reuse the same customer in repair and sales.
    await openSection('مشتریان');
    await tester.tap(find.byTooltip('ثبت مشتری'));
    await tester.pumpAndSettle();
    await fillField('نام مشتری', 'مشتری آزمایشی شبیه‌ساز');
    await fillField('شماره تماس', '09120000001');
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('مشتری آزمایشی شبیه‌ساز'), findsWidgets);

    // A same-name customer with a different phone must remain independently selectable.
    await tester.tap(find.byTooltip('ثبت مشتری'));
    await tester.pumpAndSettle();
    await fillField('نام مشتری', 'مشتری آزمایشی شبیه‌ساز');
    await fillField('شماره تماس', '09130000002');
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.textContaining('09130000002'), findsWidgets);

    // Create a product in inventory.
    await openSection('انبار کالا');
    await tester.tap(find.byTooltip('ثبت کالا'));
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
    await tester.tap(find.byTooltip('ثبت پذیرش تعمیر'));
    await tester.pumpAndSettle();
    final customerDropdown = find.byKey(
      const ValueKey('repair-existing-customer-selector'),
    );
    expect(customerDropdown, findsOneWidget,
        reason: 'Repair intake must offer previously saved customers');
    await tester.tap(customerDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('09130000002').last);
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
    expect(app.DemoStore.repairs.single['شناسه طرف حساب'],
        'customer:${app.DemoStore.customers.last['__database_id']}');

    // Consume one unit from inventory against the registered repair.
    await tester.tap(find.text('ثبت مصرف قطعه در تعمیر'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ثبت مصرف قطعه'));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text('مصرف قطعه و سند حسابداری ثبت شد'), findsOneWidget);

    // Post labor income and collect the outstanding amount to the exact same customer.
    await tester.tap(find.text('ثبت درآمد اجرت تعمیر'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('دریل آزمایشی').last);
    await tester.pumpAndSettle();
    await fillField('مبلغ دریافت‌شده (تومان)', '۱۰۰۰');
    await tester.tap(find.text('ثبت'));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text('درآمد اجرت ثبت شد؛ مانده دریافت‌نشده در حساب مشتری باقی ماند'),
        findsOneWidget);

    await tester.tap(find.text('دریافت مانده اجرت تعمیر'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('دریل آزمایشی').last);
    await tester.pumpAndSettle();
    await fillField('مبلغ دریافتی (تومان)', '۲۰۰۰');
    await tester.tap(find.text('ثبت دریافت'));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text('دریافت مانده اجرت ثبت شد'), findsOneWidget);
    final linkedRepairPartyId = app.DemoStore.repairs.single['شناسه طرف حساب']!;
    final repairStatement = await app.DemoStore.parties.getPartyStatement(linkedRepairPartyId);
    expect(repairStatement['closing_balance'], 0);

    // Sell one unit to the same saved customer and verify the invoice is archived.
    await openSection('فروش و فاکتور');
    final partyDropdown = find.byWidgetPredicate(
      (widget) => widget is DropdownButtonFormField<String> &&
          widget.decoration.labelText?.startsWith('انتخاب از اشخاص ثبت‌شده') == true,
    );
    expect(partyDropdown, findsOneWidget);
    await tester.tap(partyDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('09130000002').last);
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
    await tester.tap(find.byTooltip('تازه‌سازی'));
    await tester.pumpAndSettle();

    // Register an incoming check using Persian digits for the amount.
    await openSection('مدیریت چک‌ها');
    final checkPartyDropdown = find.byWidgetPredicate(
      (widget) => widget is DropdownButtonFormField<String> &&
          widget.decoration.labelText?.startsWith('انتخاب از اشخاص ثبت‌شده') == true,
    );
    expect(checkPartyDropdown, findsOneWidget);
    await tester.tap(checkPartyDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('09130000002').last);
    await tester.pumpAndSettle();
    await fillField('شماره چک', 'EMU-CHECK-01');
    await fillField('نام بانک', 'بانک آزمایشی');
    await fillField('نام صاحب حساب / صادرکننده', 'مشتری آزمایشی');
    await fillField('مبلغ چک (تومان)', '۵۰۰');
    await tester.tap(find.text('ثبت چک'));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text('چک و سند حسابداری آن ثبت شد'), findsOneWidget);

    // Record an expense with Persian digits and open the journal/trial balance tabs.
    await openSection('دفتر روزنامه و هزینه‌ها');
    await fillField('شرح هزینه', 'هزینه آزمایشی شبیه‌ساز');
    await fillField('مبلغ (تومان)', '۲۵۰۰');
    await tester.tap(find.text('ثبت هزینه و سند حسابداری'));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text('هزینه ثبت شد و سند حسابداری متوازن ایجاد شد'), findsOneWidget);
    await tester.tap(find.text('دفتر روزنامه'));
    await tester.pumpAndSettle();
    expect(find.text('دفتر روزنامه'), findsWidgets);
    await tester.tap(find.text('تراز آزمایشی'));
    await tester.pumpAndSettle();
    expect(find.text('تراز آزمایشی'), findsWidgets);

    // Load a real inventory movement report from the transactions above.
    await openSection('گزارش‌ها');
    final reportType = find.byWidgetPredicate(
      (widget) => widget is DropdownButtonFormField<String> &&
          widget.decoration.labelText == 'نوع گزارش',
    );
    expect(reportType, findsOneWidget);
    await tester.tap(reportType);
    await tester.pumpAndSettle();
    await tester.tap(find.text('کاردکس و گردش انبار'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('گزارش‌های عملیاتی'), findsOneWidget);
    expect(find.text('قطعه آزمایشی شبیه‌ساز'), findsWidgets);

    // Save settings with Persian numeric percentages.
    await tester.tap(find.byTooltip('باز کردن فهرست'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('drawer-settings-button')));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await fillFormField('نام فروشگاه', 'خدمات فنی آزمایشی');
    await fillFormField('نام مسئول', 'کاربر آزمایشی');
    await fillFormField('درصد مالیات بر ارزش افزوده', '۱۲٫۵');
    await fillFormField('درصد تخفیف پیش‌فرض', '۵');
    await fillFormField('پیشوند شماره فاکتور', 'EMU');
    await tester.tap(find.text('ذخیره تنظیمات'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('تنظیمات و لوگوی فروشگاه ذخیره شد.'), findsOneWidget);

    
    // A new invoice must load VAT, discount and numbering defaults from Settings.
    await tester.pageBack();
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await openSection('فروش و فاکتور');
    final configuredPartyDropdown = find.byWidgetPredicate(
      (widget) => widget is DropdownButtonFormField<String> &&
          widget.decoration.labelText?.startsWith('انتخاب از اشخاص ثبت‌شده') == true,
    );
    expect(configuredPartyDropdown, findsOneWidget);
    await tester.tap(configuredPartyDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('09130000002').last);
    await tester.pumpAndSettle();
    await fillField('تعداد', '1');
    await fillField('قیمت فروش واحد', '2000');
    await tester.tap(find.text('افزودن کالا به فاکتور'));
    await tester.pumpAndSettle();

    final discountField = find.byWidgetPredicate(
      (widget) => widget is TextField &&
          widget.decoration?.labelText == 'تخفیف کل (تومان)',
    );
    final vatField = find.byWidgetPredicate(
      (widget) => widget is TextField &&
          widget.decoration?.labelText == 'درصد ارزش افزوده',
    );
    expect(tester.widget<TextField>(discountField).controller?.text, '100');
    expect(tester.widget<TextField>(vatField).controller?.text, '12.5');
    expect(find.text('مبلغ تقریبی فاکتور: 2138 تومان'), findsOneWidget);

    await tester.ensureVisible(find.text('ثبت قطعی فاکتور'));
    await tester.tap(find.text('ثبت قطعی فاکتور'));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text('فاکتور فروش ثبت و بایگانی شد'), findsOneWidget);

    final saleDocuments = await app.DemoStore.trades.getDocuments(type: 'sale');
    final configuredSale = saleDocuments.firstWhere(
      (document) => document['document_number'].toString().startsWith('EMU-'),
    );
    final configuredSaleId = (configuredSale['id'] as num).toInt();
    expect(configuredSale['subtotal'], 2000);
    expect(configuredSale['discount_amount'], 100);
    expect(configuredSale['vat_amount'], 238);
    expect(configuredSale['total_amount'], 2138);

    // The archived invoice is immutable and must contain the saved shop header.
    final archive = await app.DemoStore.invoiceArchives.getArchive(configuredSaleId);
    expect(archive, isNotNull);
    final snapshot = archive!['snapshot'] as Map<String, dynamic>;
    expect(snapshot['shopName'], 'خدمات فنی آزمایشی');
    expect(snapshot['documentNumber'].toString().startsWith('EMU-'), isTrue);

    // Verify actual invoice rendering output, not just the presence of buttons.
    final invoiceService = InvoicePdfService();
    final invoicePng = await invoiceService.buildImage(snapshot);
    expect(invoicePng.sublist(0, 8), <int>[137, 80, 78, 71, 13, 10, 26, 10]);
    final invoicePdf = await invoiceService.build(snapshot);
    expect(String.fromCharCodes(invoicePdf.take(4)), '%PDF');

    // Return a sold unit and a purchased unit; both must post stock and ledger entries.
    final initialSale = saleDocuments.firstWhere(
      (document) =>
          document['document_number'].toString().startsWith('SAL-') &&
          (document['total_amount'] as num).toInt() == 2000,
    );
    final initialSaleId = (initialSale['id'] as num).toInt();
    final initialSaleLines = await app.DemoStore.trades.getDocumentLines(initialSaleId);
    await app.DemoStore.trades.recordCustomerReturn(
      ReturnDocumentDraft(
        documentDate: DateTime.now().toIso8601String().substring(0, 10),
        sourceDocumentId: initialSaleId,
        counterpartyName: initialSale['counterparty_name'].toString(),
        counterpartyId: initialSale['counterparty_id'].toString(),
        idempotencyKey: 'emu-customer-return-' + DateTime.now().microsecondsSinceEpoch.toString(),
        lines: [
          ReturnLineDraft(
            sourceLineId: (initialSaleLines.single['id'] as num).toInt(),
            quantity: 1,
          ),
        ],
      ),
    );

    final purchaseDocuments = await app.DemoStore.trades.getDocuments(type: 'purchase');
    final purchase = purchaseDocuments.firstWhere(
      (document) => document['counterparty_name'] == 'فروشنده آزمایشی شبیه‌ساز',
    );
    final purchaseId = (purchase['id'] as num).toInt();
    final purchaseLines = await app.DemoStore.trades.getDocumentLines(purchaseId);
    await app.DemoStore.trades.recordSupplierReturn(
      ReturnDocumentDraft(
        documentDate: DateTime.now().toIso8601String().substring(0, 10),
        sourceDocumentId: purchaseId,
        counterpartyName: purchase['counterparty_name'].toString(),
        counterpartyId: purchase['counterparty_id'].toString(),
        idempotencyKey: 'emu-supplier-return-' + DateTime.now().microsecondsSinceEpoch.toString(),
        lines: [
          ReturnLineDraft(
            sourceLineId: (purchaseLines.single['id'] as num).toInt(),
            quantity: 1,
          ),
        ],
      ),
    );
    await app.DemoStore.trades.recordSupplierPayment(
      PartyPaymentDraft(
        documentDate: DateTime.now().toIso8601String().substring(0, 10),
        counterpartyName: purchase['counterparty_name'].toString(),
        counterpartyId: purchase['counterparty_id'].toString(),
        amount: 1000,
        idempotencyKey: 'emu-supplier-payment-' + DateTime.now().microsecondsSinceEpoch.toString(),
        referenceId: purchaseId.toString(),
        cashAccountCode: '1010',
      ),
    );
    expect(await app.DemoStore.trades.getOutstandingAmount(purchaseId), 3000);
    final supplierStatement = await app.DemoStore.parties.getPartyStatement(
      purchase['counterparty_id'].toString(),
    );
    expect(supplierStatement['closing_balance'], 3000);

    await expectLater(
      app.DemoStore.trades.recordSupplierPayment(
        PartyPaymentDraft(
          documentDate: DateTime.now().toIso8601String().substring(0, 10),
          counterpartyName: purchase['counterparty_name'].toString(),
          counterpartyId: purchase['counterparty_id'].toString(),
          amount: 3001,
          idempotencyKey: 'emu-supplier-overpay-' + DateTime.now().microsecondsSinceEpoch.toString(),
          referenceId: purchaseId.toString(),
        ),
      ),
      throwsA(isA<StateError>()),
    );

    // A cheque linked to the new invoice must lower the invoice balance;
    // then a cash receipt lowers it again without double-counting the cheque.
    final customerId = configuredSale['counterparty_id'].toString();
    final linkedCheckId = await app.DemoStore.checks.createCheck(
      CheckDraft(
        direction: 'incoming',
        checkNumber: 'EMU-LINKED-02',
        bankName: 'بانک آزمایشی',
        drawerName: 'مشتری آزمایشی',
        partyName: configuredSale['counterparty_name'].toString(),
        partyId: customerId,
        amount: 500,
        issueDate: DateTime.now().toIso8601String().substring(0, 10),
        dueDate: DateTime.now().add(const Duration(days: 7)).toIso8601String().substring(0, 10),
        idempotencyKey: 'emu-linked-check-' + DateTime.now().microsecondsSinceEpoch.toString(),
        sourceDocumentId: configuredSaleId,
      ),
    );
    expect(await app.DemoStore.trades.getOutstandingAmount(configuredSaleId), 1638);
    await app.DemoStore.trades.recordCustomerReceipt(
      PartyPaymentDraft(
        documentDate: DateTime.now().toIso8601String().substring(0, 10),
        counterpartyName: configuredSale['counterparty_name'].toString(),
        counterpartyId: customerId,
        amount: 500,
        idempotencyKey: 'emu-customer-receipt-' + DateTime.now().microsecondsSinceEpoch.toString(),
        referenceId: configuredSaleId.toString(),
        cashAccountCode: '1000',
      ),
    );
    expect(await app.DemoStore.trades.getOutstandingAmount(configuredSaleId), 1138);

    final incomingChecks = await app.DemoStore.checks.getChecks(direction: 'incoming');
    final uiCheck = incomingChecks.firstWhere(
      (check) => check['check_number'] == 'EMU-CHECK-01',
    );
    final uiCheckId = (uiCheck['id'] as num).toInt();
    await app.DemoStore.checks.updateCheckStatus(
      checkId: uiCheckId,
      newStatus: 'deposited',
      reason: 'تحویل بانک در آزمون شبیه‌ساز',
    );
    await app.DemoStore.checks.updateCheckStatus(
      checkId: uiCheckId,
      newStatus: 'cleared',
      reason: 'وصول در آزمون شبیه‌ساز',
    );
    expect((await app.DemoStore.checks.getCheck(uiCheckId))['status'], 'cleared');
    expect(await app.DemoStore.checks.getCheckEvents(uiCheckId), hasLength(3));
    expect((await app.DemoStore.checks.getCheck(linkedCheckId))['status'], 'received');
    expect(await app.DemoStore.checks.getDueChecks(
      asOfDate: DateTime(2100, 1, 1),
    ), isNotEmpty);

    await app.DemoStore.refreshProducts();
    final product = app.DemoStore.products.singleWhere(
      (item) => item['کد کالا'] == 'EMU-001',
    );
    expect(double.parse(product['موجودی']!), 2);

    // All six report repositories must read real records from this test data.
    final reportRepository = ReportRepository(AppDatabase());
    final from = DateTime(2020, 1, 1);
    final to = DateTime(2099, 12, 31);
    final documentReport = await reportRepository.getTradeDocuments(from: from, to: to);
    final stockReport = await reportRepository.getInventoryMovements(from: from, to: to);
    final profitReport = await reportRepository.getProfitAndLoss(from: from, to: to);
    final itemProfitReport = await reportRepository.getItemProfit(from: from, to: to);
    final expenseReport = await reportRepository.getExpenses(from: from, to: to);
    final repairIncomeReport = await reportRepository.getRepairServiceRevenue(from: from, to: to);
    expect(documentReport.any((row) => row['document_type'] == 'customer_return'), isTrue);
    expect(documentReport.any((row) => row['document_type'] == 'supplier_return'), isTrue);
    expect(stockReport.any((row) => row['product_name'] == 'قطعه آزمایشی شبیه‌ساز'), isTrue);
    expect(profitReport, isNotEmpty);
    expect(itemProfitReport.any((row) => row['product_name'] == 'قطعه آزمایشی شبیه‌ساز'), isTrue);
    expect(expenseReport.any((row) => row['description'] == 'هزینه آزمایشی شبیه‌ساز'), isTrue);
    expect(repairIncomeReport, isNotEmpty);

    // Global search must return a real saved item, not only display its dialog.
    await tester.tap(find.byTooltip('جست‌وجوی سراسری'));
    await tester.pumpAndSettle();
    final globalSearchField = find.byWidgetPredicate(
      (widget) => widget is TextField &&
          widget.decoration?.hintText == 'کالا، خرید، فروش، اشخاص، چک و حسابداری',
    );
    expect(globalSearchField, findsOneWidget);
    await tester.enterText(globalSearchField, 'قطعه آزمایشی شبیه‌ساز');
    await tester.pumpAndSettle();
    expect(find.textContaining('قطعه آزمایشی شبیه‌ساز'), findsWidgets);
    await tester.tap(find.text('بستن'));
    await tester.pumpAndSettle();

    // Reports expose their export controls for populated data.
    await openSection('گزارش‌ها');
    expect(find.text('Excel'), findsOneWidget);
    expect(find.text('PDF'), findsOneWidget);
    for (final reportName in const [
      'فاکتورهای خرید، فروش و برگشت',
      'سود و زیان حسابداری',
      'سود هر کالا',
      'هزینه‌های ثبت‌شده',
      'درآمد خدمات تعمیر',
      'کاردکس و گردش انبار',
    ]) {
      final dropdown = find.byWidgetPredicate(
        (widget) => widget is DropdownButtonFormField<String> &&
            widget.decoration.labelText == 'نوع گزارش',
      );
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text(reportName).last);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.text('گزارش‌های عملیاتی'), findsOneWidget);
      expect(find.textContaining('تعداد ردیف‌ها:'), findsOneWidget);
    }

    // Create a real database backup, add a record after it, and restore it.
    final manualBackup = await app.DemoStore.backups.createBackup();
    await app.DemoStore.add('customers', {
      'نام مشتری': 'رکورد موقت پس از پشتیبان',
      'شماره تماس': '09129999999',
    });
    expect(
      app.DemoStore.customers.any((item) => item['نام مشتری'] == 'رکورد موقت پس از پشتیبان'),
      isTrue,
    );
    await app.DemoStore.backups.restoreFromPath(manualBackup.path);
    await app.DemoStore.init();
    expect(
      app.DemoStore.customers.any((item) => item['نام مشتری'] == 'رکورد موقت پس از پشتیبان'),
      isFalse,
    );
    expect(
      app.DemoStore.products.any((item) => item['کد کالا'] == 'EMU-001'),
      isTrue,
    );
    expect(
      (await app.DemoStore.invoiceSettings.getSettings())['shopName'],
      'خدمات فنی آزمایشی',
    );
    final backupHistory = await app.DemoStore.backups.listBackups();
    expect(
      backupHistory.any((file) => file.path.contains('khadamat-backup-emergency-')),
      isTrue,
    );
    expect(
      (await app.DemoStore.trades.getDocuments(type: 'sale')),
      isNotEmpty,
    );
  });

}
