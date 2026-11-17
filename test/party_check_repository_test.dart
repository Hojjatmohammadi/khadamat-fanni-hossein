import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:khadamat_fanni_hosein/accounting_repository.dart';
import 'package:khadamat_fanni_hosein/app_database.dart';
import 'package:khadamat_fanni_hosein/check_repository.dart';
import 'package:khadamat_fanni_hosein/jalali_date_field.dart';
import 'package:khadamat_fanni_hosein/party_repository.dart';
import 'package:khadamat_fanni_hosein/trade_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late AppDatabase store;
  late PartyRepository parties;
  late TradeRepository trades;
  late CheckRepository checks;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('khadamat_party_check_test_');
    store = AppDatabase(databasePath: '${tempDir.path}/party-check.db');
    parties = PartyRepository(store);
    trades = TradeRepository(store);
    checks = CheckRepository(store);
    await store.database;
  });

  tearDown(() async {
    await store.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<int> addProduct() => store.insert('products', {
        'نام کالا': 'قطعه دفتر اشخاص',
        'موجودی': '1',
        'بهای تمام‌شده هر واحد': '0',
      });

  Future<int> recordSale(int productId, String partyId) {
    return trades.recordSale(
      TradeDocumentDraft(
        documentDate: '2026-11-14',
        counterpartyName: 'مشتری آزمون',
        counterpartyId: partyId,
        idempotencyKey: 'sale-party-check-test',
        lines: [
          TradeLineDraft(productId: productId, quantity: 1, unitPrice: 2000),
        ],
      ),
    );
  }

  Future<int> recordPurchase(int productId, String partyId) {
    return trades.recordPurchase(
      TradeDocumentDraft(
        documentDate: '2026-11-14',
        counterpartyName: 'فروشنده آزمون',
        counterpartyId: partyId,
        idempotencyKey: 'purchase-party-check-test',
        lines: [
          TradeLineDraft(productId: productId, quantity: 1, unitPrice: 2000),
        ],
      ),
    );
  }

  test('rejects 10-digit mobile numbers without the leading zero', () async {
    await expectLater(
      parties.ensureParty(
        const PartyDraft(
          partyType: 'customer',
          displayName: 'مخاطب با شماره ناقص',
          phone: '9123456789',
        ),
      ),
      throwsArgumentError,
    );
  });

  test('Jalali parsing supports Persian digits and rejects invalid dates', () {
    final parsed = parseJalaliDate('۱۴۰۵/۰۸/۲۳');
    expect(parsed, isNotNull);
    expect(parsed!.year, 2026);
    expect(parsed.month, 11);
    expect(parsed.day, 14);

    expect(parseJalaliDate('1405/13/01'), isNull);
    expect(parseJalaliDate('1405/12/30'), isNull);
    expect(parseJalaliDate('۱۴۰۵-۰۸-۲۳'), isNull);

    expect(
      formatJalaliDate(DateTime(2026, 11, 14)),
      '۱۴۰۵/۰۸/۲۳',
    );
  });

  test('deleting an unreferenced legacy customer contact removes both records', () async {
    final legacyCustomerId = await store.insert('customers', {
      'نام مشتری': 'مخاطب قابل حذف',
    });
    final partyId = await parties.ensureParty(
      PartyDraft(
        partyType: 'customer',
        displayName: 'مخاطب قابل حذف',
        sourceCategory: 'customers',
        sourceId: legacyCustomerId.toString(),
      ),
    );

    await parties.deleteParty(partyId);

    expect(await parties.getParties(), isEmpty);
    expect(await store.getAll('customers'), isEmpty);
  });

  test('a contact linked to financial activity cannot be deleted', () async {
    final legacyCustomerId = await store.insert('customers', {
      'نام مشتری': 'مشتری دارای سابقه',
    });
    final partyId = await parties.ensureParty(
      PartyDraft(
        partyType: 'customer',
        displayName: 'مشتری دارای سابقه',
        sourceCategory: 'customers',
        sourceId: legacyCustomerId.toString(),
      ),
    );
    final productId = await addProduct();
    await recordSale(productId, partyId);

    await expectLater(parties.deleteParty(partyId), throwsStateError);
    expect(await parties.getParties(), hasLength(1));
    expect(await store.getAll('customers'), hasLength(1));
  });

  test('same-name customers can remain separate registered parties', () async {
    final first = await parties.ensureParty(
      const PartyDraft(
        partyType: 'customer',
        preferredId: 'customer:101',
        displayName: 'محمد رضایی',
      ),
    );
    final second = await parties.ensureParty(
      const PartyDraft(
        partyType: 'customer',
        preferredId: 'customer:102',
        displayName: 'محمد رضایی',
      ),
    );
    expect(first, 'customer:101');
    expect(second, 'customer:102');
    expect((await parties.getParties(partyType: 'customer')).length, 2);
  });

  test('party registration is idempotent and party statement calculates customer balance', () async {
    final partyId = await parties.ensureParty(
      const PartyDraft(
        partyType: 'customer',
        displayName: '  علی   محمدی ',
        phone: '09120000000',
      ),
    );
    final repeatedId = await parties.ensureParty(
      const PartyDraft(
        partyType: 'customer',
        displayName: 'علی محمدی',
      ),
    );
    expect(repeatedId, partyId);

    final productId = await addProduct();
    await recordSale(productId, partyId);
    await trades.recordCustomerReceipt(
      PartyPaymentDraft(
        documentDate: '2026-11-14',
        counterpartyName: 'علی محمدی',
        counterpartyId: partyId,
        amount: 500,
        idempotencyKey: 'party-statement-receipt',
      ),
    );

    final statement = await parties.getPartyStatement(partyId);
    expect(statement['total_debit'], 2000);
    expect(statement['total_credit'], 500);
    expect(statement['closing_balance'], 1500);
    expect(statement['closing_label'], 'بدهی مشتری');
    expect(statement['lines'], hasLength(2));
  });

  test('standalone customer advance is recorded in the party ledger with its payment method', () async {
    final partyId = await parties.ensureParty(
      const PartyDraft(
        partyType: 'customer',
        displayName: 'مشتری بیعانه',
      ),
    );
    final payment = PartyPaymentDraft(
      documentDate: '2026-11-17',
      counterpartyName: 'مشتری بیعانه',
      counterpartyId: partyId,
      amount: 750,
      idempotencyKey: 'customer-advance-card-to-card',
      cashAccountCode: '1010',
      paymentMethod: 'card_to_card',
    );

    final documentId = await trades.recordCustomerReceipt(payment);
    expect(await trades.recordCustomerReceipt(payment), documentId);

    final statement = await parties.getPartyStatement(partyId);
    expect(statement['closing_balance'], -750);
    expect(statement['closing_label'], 'طلب مشتری');

    final db = await store.database;
    final documents = await db.query(
      'business_documents',
      where: 'id = ?',
      whereArgs: [documentId],
    );
    expect(documents.single['source_document_id'], isNull);
    final payload = jsonDecode(documents.single['payload_json'] as String)
        as Map<String, dynamic>;
    expect(payload['paymentMethod'], 'card_to_card');

    final journal = await db.query(
      'journal_entries',
      where: 'id = ?',
      whereArgs: [documents.single['journal_entry_id']],
    );
    expect(journal.single['description'], contains('کارت‌به‌کارت'));

    await expectLater(
      trades.recordCustomerReceipt(
        PartyPaymentDraft(
          documentDate: '2026-11-17',
          counterpartyName: 'مشتری بیعانه',
          counterpartyId: partyId,
          amount: 750,
          idempotencyKey: 'invalid-advance-method',
          cashAccountCode: '1000',
          paymentMethod: 'card_to_card',
        ),
      ),
      throwsArgumentError,
    );
  });


  test('unlinked customer advances are allocated once across later invoices and settlements', () async {
    final partyId = await parties.ensureParty(
      const PartyDraft(
        partyType: 'customer',
        displayName: 'مشتری با بیعانه چندفاکتوری',
      ),
    );
    final productId = await addProduct();
    await trades.recordPurchase(
      TradeDocumentDraft(
        documentDate: '2026-11-10',
        counterpartyName: 'فروشنده موجودی',
        idempotencyKey: 'customer-advance-stock-purchase',
        lines: [
          TradeLineDraft(productId: productId, quantity: 10, unitPrice: 100),
        ],
      ),
    );

    await trades.recordCustomerReceipt(
      PartyPaymentDraft(
        documentDate: '2026-11-10',
        counterpartyName: 'مشتری با بیعانه چندفاکتوری',
        counterpartyId: partyId,
        amount: 900,
        idempotencyKey: 'customer-advance-for-future-invoices',
        cashAccountCode: '1010',
        paymentMethod: 'card_to_card',
      ),
    );

    final firstSale = await trades.recordSale(
      TradeDocumentDraft(
        documentDate: '2026-11-11',
        counterpartyName: 'مشتری با بیعانه چندفاکتوری',
        counterpartyId: partyId,
        idempotencyKey: 'customer-advance-first-invoice',
        lines: [
          TradeLineDraft(productId: productId, quantity: 1, unitPrice: 600),
        ],
      ),
    );
    expect(await trades.getOutstandingAmount(firstSale), 0);

    final secondSale = await trades.recordSale(
      TradeDocumentDraft(
        documentDate: '2026-11-12',
        counterpartyName: 'مشتری با بیعانه چندفاکتوری',
        counterpartyId: partyId,
        idempotencyKey: 'customer-advance-second-invoice',
        lines: [
          TradeLineDraft(productId: productId, quantity: 1, unitPrice: 800),
        ],
        paidAmount: 100,
      ),
    );
    expect(await trades.getOutstandingAmount(secondSale), 400);

    await trades.recordCustomerReceipt(
      PartyPaymentDraft(
        documentDate: '2026-11-13',
        counterpartyName: 'مشتری با بیعانه چندفاکتوری',
        counterpartyId: partyId,
        amount: 200,
        idempotencyKey: 'customer-advance-second-invoice-linked-receipt',
        referenceId: secondSale.toString(),
      ),
    );
    expect(await trades.getOutstandingAmount(secondSale), 200);

    final checkId = await checks.createCheck(
      CheckDraft(
        direction: 'incoming',
        checkNumber: 'ADV-100',
        bankName: 'بانک آزمایشی',
        drawerName: 'مشتری',
        partyName: 'مشتری با بیعانه چندفاکتوری',
        partyId: partyId,
        amount: 50,
        issueDate: '2026-11-14',
        dueDate: '2026-11-20',
        idempotencyKey: 'customer-advance-second-invoice-check',
        sourceDocumentId: secondSale,
      ),
    );
    expect(checkId, greaterThan(0));
    expect(await trades.getOutstandingAmount(secondSale), 150);

    await expectLater(
      checks.createCheck(
        CheckDraft(
          direction: 'incoming',
          checkNumber: 'ADV-101',
          bankName: 'بانک آزمایشی',
          drawerName: 'مشتری',
          partyName: 'مشتری با بیعانه چندفاکتوری',
          partyId: partyId,
          amount: 151,
          issueDate: '2026-11-14',
          dueDate: '2026-11-21',
          idempotencyKey: 'customer-advance-second-invoice-over-check',
          sourceDocumentId: secondSale,
        ),
      ),
      throwsStateError,
    );

    final db = await store.database;
    final allocations = await db.query(
      'invoice_payment_allocations',
      where: 'invoice_document_id IN (?, ?)',
      whereArgs: [firstSale, secondSale],
      orderBy: 'invoice_document_id ASC',
    );
    expect(allocations.map((row) => row['amount']), [600, 300]);
    expect(
      allocations.fold<int>(
        0,
        (sum, row) => sum + (row['amount'] as num).toInt(),
      ),
      900,
    );
    final statement = await parties.getPartyStatement(partyId);
    expect(statement['closing_balance'], 150);
  });

  test('unlinked supplier prepayments are allocated once across later purchases', () async {
    final partyId = await parties.ensureParty(
      const PartyDraft(
        partyType: 'supplier',
        displayName: 'فروشنده با پیش‌پرداخت چندفاکتوری',
      ),
    );
    final productId = await addProduct();
    await trades.recordSupplierPayment(
      PartyPaymentDraft(
        documentDate: '2026-11-10',
        counterpartyName: 'فروشنده با پیش‌پرداخت چندفاکتوری',
        counterpartyId: partyId,
        amount: 700,
        idempotencyKey: 'supplier-prepayment-for-future-invoices',
      ),
    );

    final firstPurchase = await trades.recordPurchase(
      TradeDocumentDraft(
        documentDate: '2026-11-11',
        counterpartyName: 'فروشنده با پیش‌پرداخت چندفاکتوری',
        counterpartyId: partyId,
        idempotencyKey: 'supplier-prepayment-first-invoice',
        lines: [
          TradeLineDraft(productId: productId, quantity: 1, unitPrice: 400),
        ],
      ),
    );
    expect(await trades.getOutstandingAmount(firstPurchase), 0);

    final secondPurchase = await trades.recordPurchase(
      TradeDocumentDraft(
        documentDate: '2026-11-12',
        counterpartyName: 'فروشنده با پیش‌پرداخت چندفاکتوری',
        counterpartyId: partyId,
        idempotencyKey: 'supplier-prepayment-second-invoice',
        lines: [
          TradeLineDraft(productId: productId, quantity: 1, unitPrice: 800),
        ],
        paidAmount: 100,
      ),
    );
    expect(await trades.getOutstandingAmount(secondPurchase), 400);

    await trades.recordSupplierPayment(
      PartyPaymentDraft(
        documentDate: '2026-11-13',
        counterpartyName: 'فروشنده با پیش‌پرداخت چندفاکتوری',
        counterpartyId: partyId,
        amount: 200,
        idempotencyKey: 'supplier-prepayment-second-invoice-linked-payment',
        referenceId: secondPurchase.toString(),
      ),
    );
    expect(await trades.getOutstandingAmount(secondPurchase), 200);

    final checkId = await checks.createCheck(
      CheckDraft(
        direction: 'outgoing',
        checkNumber: 'SUP-100',
        bankName: 'بانک آزمایشی',
        drawerName: 'خدمات فنی حسین',
        partyName: 'فروشنده با پیش‌پرداخت چندفاکتوری',
        partyId: partyId,
        amount: 50,
        issueDate: '2026-11-14',
        dueDate: '2026-11-20',
        idempotencyKey: 'supplier-prepayment-second-invoice-check',
        sourceDocumentId: secondPurchase,
      ),
    );
    expect(checkId, greaterThan(0));
    expect(await trades.getOutstandingAmount(secondPurchase), 150);

    final statement = await parties.getPartyStatement(partyId);
    expect(statement['closing_balance'], 150);
    final db = await store.database;
    final allocations = await db.query(
      'invoice_payment_allocations',
      where: 'invoice_document_id IN (?, ?)',
      whereArgs: [firstPurchase, secondPurchase],
    );
    expect(
      allocations.fold<int>(
        0,
        (sum, row) => sum + (row['amount'] as num).toInt(),
      ),
      700,
    );
  });


  test('repair labour income is posted once and later receipts do not credit income again', () async {
    final partyId = await parties.ensureParty(
      const PartyDraft(
        partyType: 'customer',
        displayName: 'مشتری اجرت تعمیر',
      ),
    );
    final accounting = AccountingRepository(store);

    Future<int> postIncome({String key = 'repair-service-income-once'}) {
      return accounting.recordRepairServiceIncome(
        serviceDate: '2026-11-14',
        description: 'اجرت تعمیر دریل',
        amount: 1000,
        paidAmount: 400,
        cashAccountCode: '1000',
        customerId: partyId,
        repairId: 'repair-labour-once',
        idempotencyKey: key,
      );
    }

    final firstEntry = await postIncome();
    expect(await postIncome(), firstEntry);
    await expectLater(
      postIncome(key: 'repair-service-income-second-key'),
      throwsStateError,
    );

    await accounting.recordRepairServiceReceipt(
      receiptDate: '2026-11-15',
      repairId: 'repair-labour-once',
      customerId: partyId,
      description: 'اجرت تعمیر دریل',
      amount: 250,
      cashAccountCode: '1000',
      idempotencyKey: 'repair-service-receipt-part-one',
    );
    await accounting.recordRepairServiceReceipt(
      receiptDate: '2026-11-16',
      repairId: 'repair-labour-once',
      customerId: partyId,
      description: 'اجرت تعمیر دریل',
      amount: 350,
      cashAccountCode: '1010',
      idempotencyKey: 'repair-service-receipt-part-two',
    );

    await expectLater(
      accounting.recordRepairServiceReceipt(
        receiptDate: '2026-11-17',
        repairId: 'repair-labour-once',
        customerId: partyId,
        description: 'اجرت تعمیر دریل',
        amount: 1,
        cashAccountCode: '1000',
        idempotencyKey: 'repair-service-receipt-overpay',
      ),
      throwsStateError,
    );

    final trialBalance = await accounting.getTrialBalance();
    final serviceIncome = trialBalance.singleWhere(
      (row) => row['account_code'] == '4100',
    );
    expect(serviceIncome['total_credit'], 1000);
    expect(serviceIncome['total_debit'], 0);

    final statement = await parties.getPartyStatement(partyId);
    expect(statement['closing_balance'], 0);
  });

  test('incoming check reduces customer debt, clears to bank, and keeps an audit trail', () async {
    final partyId = await parties.ensureParty(
      const PartyDraft(
        partyType: 'customer',
        displayName: 'مشتری چک دریافتی',
      ),
    );
    final productId = await addProduct();
    final saleId = await recordSale(productId, partyId);

    final checkId = await checks.createCheck(
      CheckDraft(
        direction: 'incoming',
        checkNumber: '123456',
        bankName: 'بانک آزمایشی',
        drawerName: 'مشتری چک دریافتی',
        partyName: 'مشتری چک دریافتی',
        partyId: partyId,
        amount: 700,
        issueDate: '2026-11-14',
        dueDate: '2026-11-15',
        idempotencyKey: 'incoming-check-test',
        sourceDocumentId: saleId,
      ),
    );
    expect(await checks.createCheck(
      CheckDraft(
        direction: 'incoming',
        checkNumber: '123456',
        bankName: 'بانک آزمایشی',
        drawerName: 'مشتری چک دریافتی',
        partyName: 'مشتری چک دریافتی',
        partyId: partyId,
        amount: 700,
        issueDate: '2026-11-14',
        dueDate: '2026-11-15',
        idempotencyKey: 'incoming-check-test',
        sourceDocumentId: saleId,
      ),
    ), checkId);

    expect(await trades.getOutstandingAmount(saleId), 1300);
    await checks.updateCheckStatus(
      checkId: checkId,
      newStatus: 'deposited',
      reason: 'تحویل بانک شد',
      eventDate: '2026-11-14',
    );
    await checks.updateCheckStatus(
      checkId: checkId,
      newStatus: 'cleared',
      reason: 'وصول شد',
      eventDate: '2026-11-15',
    );
    expect(await trades.getOutstandingAmount(saleId), 1300);

    final statement = await parties.getPartyStatement(partyId);
    expect(statement['closing_balance'], 1300);
    final check = await checks.getCheck(checkId);
    expect(check['status'], 'cleared');
    expect(check['settlement_journal_id'], isNotNull);
    expect(await checks.getCheckEvents(checkId), hasLength(3));

    final db = await store.database;
    await expectLater(
      db.update(
        'check_records',
        {'bank_name': 'بانک تغییرکرده'},
        where: 'id = ?',
        whereArgs: [checkId],
      ),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      db.delete(
        'check_records',
        where: 'id = ?',
        whereArgs: [checkId],
      ),
      throwsA(isA<DatabaseException>()),
    );
    final event = (await checks.getCheckEvents(checkId)).first;
    await expectLater(
      db.update(
        'check_events',
        {'description': 'ویرایش سابقه'},
        where: 'id = ?',
        whereArgs: [event['id']],
      ),
      throwsA(isA<DatabaseException>()),
    );
    final checkAsset = await db.rawQuery(
      "SELECT COALESCE(SUM(debit-credit), 0) AS balance FROM journal_lines WHERE account_code = '1020'",
    );
    expect(checkAsset.single['balance'], 0);
  });

  test('bounced incoming check restores receivable and reopens invoice balance', () async {
    final partyId = await parties.ensureParty(
      const PartyDraft(
        partyType: 'customer',
        displayName: 'مشتری چک برگشتی',
      ),
    );
    final productId = await addProduct();
    final saleId = await recordSale(productId, partyId);
    final checkId = await checks.createCheck(
      CheckDraft(
        direction: 'incoming',
        checkNumber: '778899',
        bankName: 'بانک',
        drawerName: 'صادرکننده',
        partyName: 'مشتری چک برگشتی',
        partyId: partyId,
        amount: 600,
        issueDate: '2026-11-14',
        dueDate: '2026-11-16',
        idempotencyKey: 'incoming-check-bounced',
        sourceDocumentId: saleId,
      ),
    );
    expect(await trades.getOutstandingAmount(saleId), 1400);

    await checks.updateCheckStatus(
      checkId: checkId,
      newStatus: 'bounced',
      reason: 'عدم موجودی',
      eventDate: '2026-11-16',
    );
    expect(await trades.getOutstandingAmount(saleId), 2000);
    final check = await checks.getCheck(checkId);
    expect(check['status'], 'bounced');
    expect(check['reversal_journal_id'], isNotNull);
    final statement = await parties.getPartyStatement(partyId);
    expect(statement['closing_balance'], 2000);

    await expectLater(
      checks.updateCheckStatus(
        checkId: checkId,
        newStatus: 'cleared',
        reason: 'تلاش نامعتبر',
        eventDate: '2026-11-17',
      ),
      throwsStateError,
    );
  });

  test('outgoing check reduces supplier payable and records clearance separately', () async {
    final partyId = await parties.ensureParty(
      const PartyDraft(
        partyType: 'supplier',
        displayName: 'فروشنده چک پرداختی',
      ),
    );
    final productId = await addProduct();
    final purchaseId = await recordPurchase(productId, partyId);
    final checkId = await checks.createCheck(
      CheckDraft(
        direction: 'outgoing',
        checkNumber: '554433',
        bankName: 'بانک صادرکننده',
        drawerName: 'خدمات فنی حسین',
        partyName: 'فروشنده چک پرداختی',
        partyId: partyId,
        amount: 800,
        issueDate: '2026-11-14',
        dueDate: '2026-11-20',
        idempotencyKey: 'outgoing-check-test',
        sourceDocumentId: purchaseId,
      ),
    );
    expect(await trades.getOutstandingAmount(purchaseId), 1200);
    final statement = await parties.getPartyStatement(partyId);
    expect(statement['closing_balance'], 1200);
    expect(statement['closing_label'], 'طلب فروشنده');

    await checks.updateCheckStatus(
      checkId: checkId,
      newStatus: 'cleared',
      reason: 'چک پاس شد',
      eventDate: '2026-11-20',
    );
    final db = await store.database;
    final checksPayable = await db.rawQuery(
      "SELECT COALESCE(SUM(debit-credit), 0) AS balance FROM journal_lines WHERE account_code = '2020'",
    );
    expect(checksPayable.single['balance'], 0);
  });

  test('check reminders include overdue, today and tomorrow but exclude cleared checks', () async {
    final partyId = await parties.ensureParty(
      const PartyDraft(
        partyType: 'customer',
        displayName: 'شخص سررسید',
      ),
    );
    final items = [
      ('due-yesterday', '2026-11-13'),
      ('due-today', '2026-11-14'),
      ('due-tomorrow', '2026-11-15'),
      ('due-later', '2026-11-16'),
    ];
    for (final item in items) {
      await checks.createCheck(
        CheckDraft(
          direction: 'incoming',
          checkNumber: item.$1,
          bankName: 'بانک',
          drawerName: 'صادرکننده',
          partyName: 'شخص سررسید',
          partyId: partyId,
          amount: 100,
          issueDate: '2026-11-12',
          dueDate: item.$2,
          idempotencyKey: item.$1,
        ),
      );
    }
    final results = await checks.getDueChecks(asOfDate: DateTime(2026, 11, 14));
    expect(results.map((row) => row['check_number']).toSet(), {
      'due-yesterday',
      'due-today',
      'due-tomorrow',
    });

    final todayCheck = results.firstWhere((row) => row['check_number'] == 'due-today');
    await checks.updateCheckStatus(
      checkId: todayCheck['id'] as int,
      newStatus: 'cleared',
      reason: 'وصول شد',
      eventDate: '2026-11-14',
    );
    final refreshed = await checks.getDueChecks(asOfDate: DateTime(2026, 11, 14));
    expect(refreshed.any((row) => row['check_number'] == 'due-today'), isFalse);
  });

  test('rejects checks with invalid dates or amounts above invoice balance', () async {
    final partyId = await parties.ensureParty(
      const PartyDraft(
        partyType: 'customer',
        displayName: 'مشتری کنترل مبلغ چک',
      ),
    );
    await expectLater(
      checks.createCheck(
        CheckDraft(
          direction: 'incoming',
          checkNumber: '1',
          bankName: 'بانک',
          drawerName: 'صادرکننده',
          partyName: 'مشتری کنترل مبلغ چک',
          partyId: partyId,
          amount: 100,
          issueDate: '2026-11-15',
          dueDate: '2026-11-14',
          idempotencyKey: 'check-invalid-date',
        ),
      ),
      throwsArgumentError,
    );

    final productId = await addProduct();
    final saleId = await recordSale(productId, partyId);
    await expectLater(
      checks.createCheck(
        CheckDraft(
          direction: 'incoming',
          checkNumber: '2',
          bankName: 'بانک',
          drawerName: 'صادرکننده',
          partyName: 'مشتری کنترل مبلغ چک',
          partyId: partyId,
          amount: 2001,
          issueDate: '2026-11-14',
          dueDate: '2026-11-15',
          idempotencyKey: 'check-excess-amount',
          sourceDocumentId: saleId,
        ),
      ),
      throwsStateError,
    );
  });

  test('bounced outgoing check restores supplier payable and leaves due reminders', () async {
    final partyId = await parties.ensureParty(
      const PartyDraft(
        partyType: 'supplier',
        displayName: 'فروشنده چک برگشتی پرداختی',
      ),
    );
    final productId = await addProduct();
    final purchaseId = await recordPurchase(productId, partyId);
    final checkId = await checks.createCheck(
      CheckDraft(
        direction: 'outgoing',
        checkNumber: 'OUT-BOUNCE-01',
        bankName: 'بانک',
        drawerName: 'خدمات فنی حسین',
        partyName: 'فروشنده چک برگشتی پرداختی',
        partyId: partyId,
        amount: 800,
        issueDate: '2026-11-14',
        dueDate: '2026-11-15',
        idempotencyKey: 'outgoing-check-bounced',
        sourceDocumentId: purchaseId,
      ),
    );

    expect(await trades.getOutstandingAmount(purchaseId), 1200);
    await checks.updateCheckStatus(
      checkId: checkId,
      newStatus: 'bounced',
      reason: 'عدم موجودی حساب',
      eventDate: '2026-11-16',
    );

    expect(await trades.getOutstandingAmount(purchaseId), 2000);
    final statement = await parties.getPartyStatement(partyId);
    expect(statement['closing_balance'], 2000);
    final check = await checks.getCheck(checkId);
    expect(check['status'], 'bounced');
    expect(check['reversal_journal_id'], isNotNull);
    expect(
      (await checks.getDueChecks(asOfDate: DateTime(2026, 11, 17)))
          .any((row) => row['id'] == checkId),
      isFalse,
    );
    expect(await checks.getCheckEvents(checkId), hasLength(2));
  });

  test('cancelling a deposited incoming check restores receivable exactly once', () async {
    final partyId = await parties.ensureParty(
      const PartyDraft(
        partyType: 'customer',
        displayName: 'مشتری چک لغوشده',
      ),
    );
    final productId = await addProduct();
    final saleId = await recordSale(productId, partyId);
    final checkId = await checks.createCheck(
      CheckDraft(
        direction: 'incoming',
        checkNumber: 'CANCEL-100',
        bankName: 'بانک',
        drawerName: 'صادرکننده',
        partyName: 'مشتری چک لغوشده',
        partyId: partyId,
        amount: 700,
        issueDate: '2026-11-14',
        dueDate: '2026-11-15',
        idempotencyKey: 'incoming-check-cancelled-after-deposit',
        sourceDocumentId: saleId,
      ),
    );

    expect(await trades.getOutstandingAmount(saleId), 1300);
    await checks.updateCheckStatus(
      checkId: checkId,
      newStatus: 'deposited',
      reason: 'تحویل بانک شد',
      eventDate: '2026-11-14',
    );
    await checks.updateCheckStatus(
      checkId: checkId,
      newStatus: 'cancelled',
      reason: 'درخواست لغو چک',
      eventDate: '2026-11-15',
    );

    // A repeated terminal transition must not create another reversal.
    await checks.updateCheckStatus(
      checkId: checkId,
      newStatus: 'cancelled',
      reason: 'ثبت تکراری لغو',
      eventDate: '2026-11-16',
    );

    expect(await trades.getOutstandingAmount(saleId), 2000);
    final statement = await parties.getPartyStatement(partyId);
    expect(statement['closing_balance'], 2000);
    final check = await checks.getCheck(checkId);
    expect(check['status'], 'cancelled');
    expect(check['reversal_journal_id'], isNotNull);
    expect(await checks.getCheckEvents(checkId), hasLength(3));
    expect(
      (await checks.getDueChecks(asOfDate: DateTime(2026, 11, 17)))
          .any((row) => row['id'] == checkId),
      isFalse,
    );
    await expectLater(
      checks.updateCheckStatus(
        checkId: checkId,
        newStatus: 'cleared',
        reason: 'تغییر وضعیت نامعتبر',
        eventDate: '2026-11-17',
      ),
      throwsStateError,
    );
  });
}
