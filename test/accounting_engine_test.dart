import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:khadamat_fanni_hosein/accounting/accounting_engine.dart';
import 'package:khadamat_fanni_hosein/data/app_database_schema.dart';
import 'package:khadamat_fanni_hosein/main.dart' show DemoStore;

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await db.execute('''
      CREATE TABLE records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL,
        data TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await AppDatabaseSchema.create(db);
    await AccountingEngine.ensureDefaultAccounts(db);
  });

  tearDown(() async {
    if (db.isOpen) await db.close();
  });

  Future<int> addProduct(String name) {
    return db.insert('products', {
      'code': '',
      'name': name,
      'created_at': DateTime(2026, 1, 1).toIso8601String(),
    });
  }


  test('new sales invoice posts customer balance, deposit, stock and cost atomically', () async {
    final productId = await addProduct('کالای فروش آزمون');
    await AccountingEngine.recordStockMovementInTransaction(
      db,
      productId: productId,
      movementType: 'purchase',
      quantityDelta: 10,
      unitCost: 100,
      referenceType: 'test_purchase',
      referenceId: 'sale-posting-stock',
      occurredAt: DateTime(2026, 1, 1),
    );
    final customerId = await db.insert('customers', {
      'first_name': 'مشتری',
      'last_name': 'فروش آزمون',
      'created_at': DateTime(2026, 1, 1).toIso8601String(),
    });
    final cashId = await AccountingEngine.accountId(db, '1000');
    final depositId = await AccountingEngine.accountId(db, '2010');
    await AccountingEngine.postJournalInTransaction(
      db,
      entryNumber: 'TEST-SALE-DEPOSIT',
      occurredAt: DateTime(2026, 2, 1),
      description: 'بیعانه قبلی مشتری',
      sourceType: 'unit_test',
      sourceId: 'sale-posting-deposit',
      lines: [
        JournalLineInput(accountId: cashId, debit: 100),
        JournalLineInput(
          accountId: depositId,
          credit: 100,
          partyType: 'customer',
          partyId: customerId,
        ),
      ],
    );

    await DemoStore.postSaleInTransaction(
      db,
      recordId: 99001,
      occurredAt: DateTime(2026, 2, 2),
      item: {
        'شماره فاکتور': 'TEST-SALE-99001',
        'مبلغ کل': '600',
        'تخفیف': '0',
        'مبلغ مالیات': '0',
        'مبلغ دریافتی': '200',
        'بیعانه تخصیص‌یافته': '100',
        'شناسه مشتری': customerId.toString(),
        'نام مشتری': 'مشتری فروش آزمون',
        'روش پرداخت': 'نقدی',
        'ردیف‌های فاکتور': jsonEncode([
          {
            'kind': 'product',
            'product_id': productId.toString(),
            'description': 'کالای فروش آزمون',
            'quantity': '3',
            'line_total': '600',
          },
        ]),
      },
    );

    final product = (await db.query('products',
      columns: ['quantity'], where: 'id = ?', whereArgs: [productId])).single;
    expect(product['quantity'], 7);
    final saleMovements = await db.query('stock_movements',
      where: "reference_type = 'sale' AND reference_id = '99001'");
    expect(saleMovements, hasLength(1));
    expect(saleMovements.single['quantity_delta'], -3);
    expect(saleMovements.single['unit_cost'], 100);
    expect(saleMovements.single['total_cost'], 300);

    final journal = (await db.query('journal_entries',
      where: "source_type = 'sale' AND source_id = '99001'")).single;
    final totals = await db.rawQuery(
      'SELECT SUM(debit) AS debit_total, SUM(credit) AS credit_total FROM journal_lines WHERE entry_id = ?',
      [journal['id']],
    );
    expect(totals.single['debit_total'], totals.single['credit_total']);

    final ledger = await AccountingEngine.partyLedger(
      db,
      partyType: 'customer',
      partyId: customerId,
      accountCodes: const ['1100', '2010'],
    );
    expect(ledger.last['running_balance'], 300);
  });

  test('multi-line sale aggregates repeated product stock movement once', () async {
    final productId = await addProduct('کالای چندردیفی آزمون');
    await AccountingEngine.recordStockMovementInTransaction(
      db,
      productId: productId,
      movementType: 'purchase',
      quantityDelta: 10,
      unitCost: 75,
      referenceType: 'test_purchase',
      referenceId: 'multi-line-stock',
      occurredAt: DateTime(2026, 1, 1),
    );

    await DemoStore.postSaleInTransaction(
      db,
      recordId: 99002,
      occurredAt: DateTime(2026, 2, 3),
      item: {
        'شماره فاکتور': 'TEST-SALE-99002',
        'مبلغ کل': '300',
        'تخفیف': '0',
        'مبلغ مالیات': '0',
        'مبلغ دریافتی': '300',
        'بیعانه تخصیص‌یافته': '0',
        'روش پرداخت': 'نقدی',
        'ردیف‌های فاکتور': jsonEncode([
          {
            'kind': 'product',
            'product_id': productId.toString(),
            'description': 'ردیف اول',
            'quantity': '1',
            'line_total': '150',
          },
          {
            'kind': 'product',
            'product_id': productId.toString(),
            'description': 'ردیف دوم',
            'quantity': '1',
            'line_total': '150',
          },
        ]),
      },
    );

    final saleMovements = await db.query('stock_movements',
      where: "reference_type = 'sale' AND reference_id = '99002'");
    expect(saleMovements, hasLength(1));
    expect(saleMovements.single['quantity_delta'], -2);
    expect(saleMovements.single['total_cost'], 150);
    final product = (await db.query('products',
      columns: ['quantity'], where: 'id = ?', whereArgs: [productId])).single;
    expect(product['quantity'], 8);
  });



  test('service-only cheque sale posts to received-cheques without stock movement', () async {
    await DemoStore.postSaleInTransaction(
      db,
      recordId: 99004,
      occurredAt: DateTime(2026, 2, 5),
      item: {
        'شماره فاکتور': 'TEST-SALE-99004',
        'مبلغ کل': '500',
        'تخفیف': '0',
        'مبلغ مالیات': '0',
        'مبلغ دریافتی': '500',
        'بیعانه تخصیص‌یافته': '0',
        'روش پرداخت': 'چک',
        'شماره چک': 'RC-SALE-99004',
        'تاریخ سررسید میلادی': DateTime(2026, 3, 5).toIso8601String(),
        'ردیف‌های فاکتور': jsonEncode([
          {
            'kind': 'service',
            'product_id': '',
            'description': 'اجرت تعمیر',
            'quantity': '1',
            'line_total': '500',
          },
        ]),
      },
    );

    final check = (await db.query('checks_register',
      where: "source_type = 'sale' AND source_id = '99004'")).single;
    expect(check['direction'], 'received');
    expect(check['status'], 'pending');
    expect(check['amount'], 500);

    final journal = (await db.query('journal_entries',
      where: "source_type = 'sale' AND source_id = '99004'")).single;
    final lines = await db.rawQuery(
      '''SELECT a.code, l.debit, l.credit
         FROM journal_lines l JOIN accounts a ON a.id = l.account_id
         WHERE l.entry_id = ?''',
      [journal['id']],
    );
    final chequeLine = lines.singleWhere((line) => line['code'] == '1020');
    final serviceLine = lines.singleWhere((line) => line['code'] == '4010');
    expect(chequeLine['debit'], 500);
    expect(serviceLine['credit'], 500);
    expect(await db.query('stock_movements',
      where: "reference_type = 'sale' AND reference_id = '99004'"), isEmpty);
  });

  test('invalid sales cheque date rolls back the complete invoice posting', () async {
    await expectLater(
      db.transaction((txn) => DemoStore.postSaleInTransaction(
        txn,
        recordId: 99005,
        occurredAt: DateTime(2026, 2, 5),
        item: {
          'شماره فاکتور': 'TEST-SALE-99005',
          'مبلغ کل': '250',
          'تخفیف': '0',
          'مبلغ مالیات': '0',
          'مبلغ دریافتی': '250',
          'بیعانه تخصیص‌یافته': '0',
          'روش پرداخت': 'چک',
          'شماره چک': 'RC-SALE-99005',
          'تاریخ سررسید میلادی': DateTime(2026, 2, 4).toIso8601String(),
          'ردیف‌های فاکتور': jsonEncode([
            {
              'kind': 'service',
              'product_id': '',
              'description': 'اجرت تعمیر',
              'quantity': '1',
              'line_total': '250',
            },
          ]),
        },
      )),
      throwsA(isA<StateError>()),
    );

    expect(await db.query('journal_entries',
      where: "source_type = 'sale' AND source_id = '99005'"), isEmpty);
    expect(await db.query('checks_register',
      where: "source_type = 'sale' AND source_id = '99005'"), isEmpty);
  });

  test('stock quantity and moving average cost respect the invoice date', () async {
    final productId = await addProduct('کالای آزمون تاریخ‌دار');
    await AccountingEngine.recordStockMovementInTransaction(
      db,
      productId: productId,
      movementType: 'purchase',
      quantityDelta: 5,
      unitCost: 100,
      referenceType: 'test_purchase',
      referenceId: 'dated-stock-1',
      occurredAt: DateTime(2026, 1, 1),
    );
    await AccountingEngine.recordStockMovementInTransaction(
      db,
      productId: productId,
      movementType: 'purchase',
      quantityDelta: 5,
      unitCost: 300,
      referenceType: 'test_purchase',
      referenceId: 'dated-stock-2',
      occurredAt: DateTime(2026, 1, 3),
    );

    expect(
      await AccountingEngine.stockQuantityAt(
        db, productId, asOf: DateTime(2026, 1, 2, 23, 59),
      ),
      5,
    );
    expect(
      await AccountingEngine.averageUnitCost(
        db, productId, asOf: DateTime(2026, 1, 2, 23, 59),
      ),
      100,
    );
    expect(
      await AccountingEngine.stockQuantityAt(
        db, productId, asOf: DateTime(2026, 1, 4),
      ),
      10,
    );
    expect(
      await AccountingEngine.averageUnitCost(
        db, productId, asOf: DateTime(2026, 1, 4),
      ),
      200,
    );
  });

  test('backdated sale cannot consume stock purchased after its invoice date', () async {
    final productId = await addProduct('کالای خرید آینده');
    await AccountingEngine.recordStockMovementInTransaction(
      db,
      productId: productId,
      movementType: 'purchase',
      quantityDelta: 5,
      unitCost: 100,
      referenceType: 'test_purchase',
      referenceId: 'future-stock-for-sale',
      occurredAt: DateTime(2026, 2, 10),
    );

    await expectLater(
      db.transaction((txn) => DemoStore.postSaleInTransaction(
        txn,
        recordId: 99003,
        occurredAt: DateTime(2026, 2, 5),
        item: {
          'شماره فاکتور': 'TEST-SALE-99003',
          'مبلغ کل': '200',
          'تخفیف': '0',
          'مبلغ مالیات': '0',
          'مبلغ دریافتی': '200',
          'بیعانه تخصیص‌یافته': '0',
          'روش پرداخت': 'نقدی',
          'ردیف‌های فاکتور': jsonEncode([
            {
              'kind': 'product',
              'product_id': productId.toString(),
              'description': 'کالای خرید آینده',
              'quantity': '1',
              'line_total': '200',
            },
          ]),
        },
      )),
      throwsA(isA<StateError>()),
    );

    final product = (await db.query('products',
      columns: ['quantity'], where: 'id = ?', whereArgs: [productId])).single;
    expect(product['quantity'], 5);
    expect(await db.query('journal_entries',
      where: "source_type = 'sale' AND source_id = '99003'"), isEmpty);
    expect(await db.query('stock_movements',
      where: "reference_type = 'sale' AND reference_id = '99003'"), isEmpty);
  });

  test('customer deposit requires a linked customer record', () {
    expect(
      () => AccountingEngine.validateDepositParty(
        partyType: 'مشتری',
        partyId: null,
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      () => AccountingEngine.validateDepositParty(
        partyType: 'فروشنده',
        partyId: 12,
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      () => AccountingEngine.validateDepositParty(
        partyType: 'مشتری',
        partyId: 12,
      ),
      returnsNormally,
    );
  });

  test('settled invoice history row is visible without changing ledger balance', () {
    final row = AccountingEngine.invoiceHistoryRow(
      date: DateTime(2026, 3, 4),
      invoiceNumber: 'HOS-1042',
      gross: 120000,
      discount: 10000,
      tax: 9900,
      received: 119900,
      depositApplied: 0,
      paymentMethod: 'نقدی',
    );

    expect(row['is_history_only'], isTrue);
    expect(row['date'], DateTime(2026, 3, 4));
    expect(row['description'], contains('HOS-1042'));
    expect(row['description'], contains('تخفیف 10000'));
    expect(row['description'], contains('مالیات 9900'));
    expect(row['description'], contains('دریافتی 119900'));
    expect(row['debit'], 0.0);
    expect(row['credit'], 0.0);
    expect(
      (row['debit'] as double) - (row['credit'] as double),
      0.0,
      reason: 'A history-only invoice must never alter the customer balance.',
    );
  });

  test('legacy supplier receipt reduces receivable while payment reduces payable', () {
    final receipt = AccountingEngine.legacyPartyOperationAmounts(
      partyType: 'فروشنده',
      operation: 'دریافت وجه',
      amount: 250,
    );
    expect(receipt['debit'], 0);
    expect(receipt['credit'], 250);

    final payment = AccountingEngine.legacyPartyOperationAmounts(
      partyType: 'فروشنده',
      operation: 'پرداخت وجه',
      amount: 180,
    );
    expect(payment['debit'], 180);
    expect(payment['credit'], 0);

    final purchase = AccountingEngine.legacyPartyOperationAmounts(
      partyType: 'فروشنده',
      operation: 'خرید کالا',
      amount: 1000,
      paid: 300,
    );
    expect(purchase['debit'], 300);
    expect(purchase['credit'], 1000);

    final customerReceipt = AccountingEngine.legacyPartyOperationAmounts(
      partyType: 'مشتری',
      operation: 'دریافت وجه',
      amount: 90,
    );
    expect(customerReceipt['debit'], 0);
    expect(customerReceipt['credit'], 90);
  });

  test('supplier return reduces outstanding payable before cash refund', () {
    final partial = AccountingEngine.supplierReturnSettlementAmounts(
      returnAmount: 400,
      outstandingPayable: 250,
      settleAsCash: true,
    );
    expect(partial['payable_reduction'], 250);
    expect(partial['cash_refund'], 150);
    expect(partial['supplier_receivable'], 0);
    expect(
      partial.values.reduce((sum, value) => sum + value),
      400,
    );

    final credit = AccountingEngine.supplierReturnSettlementAmounts(
      returnAmount: 400,
      outstandingPayable: 250,
      settleAsCash: false,
    );
    expect(credit['payable_reduction'], 250);
    expect(credit['cash_refund'], 0);
    expect(credit['supplier_receivable'], 150);

    final fullyPaid = AccountingEngine.supplierReturnSettlementAmounts(
      returnAmount: 400,
      outstandingPayable: 0,
      settleAsCash: true,
    );
    expect(fullyPaid['payable_reduction'], 0);
    expect(fullyPaid['cash_refund'], 400);
    expect(fullyPaid['supplier_receivable'], 0);

    expect(
      () => AccountingEngine.supplierReturnSettlementAmounts(
        returnAmount: -1,
        outstandingPayable: 0,
        settleAsCash: true,
      ),
      throwsArgumentError,
    );
  });

  test('supplier purchase and overpayment create payable and advance once', () async {
    final supplierId = await AppDatabaseSchema.ensureSupplier(db, 'فروشنده خرید آزمون');
    final purchaseDate = DateTime(2026, 4, 1).toIso8601String();
    final paymentDate = DateTime(2026, 4, 2).toIso8601String();

    await db.insert('records', {
      'category': 'operations',
      'created_at': purchaseDate,
      'data': jsonEncode({
        'نوع عملیات': 'خرید کالا',
        'نام شخص': 'فروشنده خرید آزمون',
        'نوع طرف حساب': 'فروشنده',
        'شناسه فروشنده': supplierId.toString(),
        'مبلغ': '1000',
        'مبلغ پرداخت‌شده': '300',
        'روش': 'نقدی',
      }),
    });
    await db.insert('records', {
      'category': 'operations',
      'created_at': paymentDate,
      'data': jsonEncode({
        'نوع عملیات': 'پرداخت وجه',
        'نام شخص': 'فروشنده خرید آزمون',
        'نوع طرف حساب': 'فروشنده',
        'شناسه فروشنده': supplierId.toString(),
        'مبلغ': '800',
        'روش': 'نقدی',
      }),
    });

    await AppDatabaseSchema.migrateHistoricalJournals(db);
    final ledger = await AccountingEngine.partyLedger(
      db,
      partyType: 'supplier',
      partyId: supplierId,
      accountCodes: const ['2000', '1110'],
    );

    expect(ledger, hasLength(3));
    expect(ledger[0]['credit'], 700);
    expect(ledger[1]['debit'], 700);
    expect(ledger[2]['debit'], 100);
    expect(ledger.last['running_balance'], 100);

    await AppDatabaseSchema.migrateHistoricalJournals(db);
    final entries = await db.query(
      'journal_entries',
      where: "source_type IN ('purchase', 'operation')",
    );
    expect(entries, hasLength(2), reason: 'Legacy sources must never be posted twice.');
  });

  test('localized amount parser accepts Persian and Arabic digits and separators', () {
    expect(AccountingEngine.parseLocalizedAmount('۱۲٬۳۴۵'), 12345);
    expect(AccountingEngine.parseLocalizedAmount('١٢٣٫٥'), 123.5);
    expect(AccountingEngine.parseLocalizedAmount('1,234.75'), 1234.75);
    expect(AccountingEngine.parseLocalizedAmount('نامعتبر'), 0);
  });

  test('party ledger treats the end date as inclusive calendar day', () async {
    final customerId = await db.insert('customers', {
      'first_name': 'مشتری',
      'last_name': 'آزمایش بازه',
      'created_at': DateTime(2026, 1, 1).toIso8601String(),
    });
    final receivableId = await AccountingEngine.accountId(db, '1100');
    final revenueId = await AccountingEngine.accountId(db, '4000');

    await AccountingEngine.postJournalInTransaction(
      db,
      entryNumber: 'TEST-LEDGER-END-DAY-1',
      occurredAt: DateTime(2026, 2, 2, 23, 59),
      description: 'رویداد در انتهای روز انتخاب‌شده',
      sourceType: 'unit_test',
      sourceId: 'ledger-end-day-1',
      lines: [
        JournalLineInput(
          accountId: receivableId,
          debit: 100,
          partyType: 'customer',
          partyId: customerId,
        ),
        JournalLineInput(accountId: revenueId, credit: 100),
      ],
    );
    await AccountingEngine.postJournalInTransaction(
      db,
      entryNumber: 'TEST-LEDGER-END-DAY-2',
      occurredAt: DateTime(2026, 2, 3, 12),
      description: 'رویداد روز بعد که نباید وارد گزارش شود',
      sourceType: 'unit_test',
      sourceId: 'ledger-end-day-2',
      lines: [
        JournalLineInput(
          accountId: receivableId,
          debit: 250,
          partyType: 'customer',
          partyId: customerId,
        ),
        JournalLineInput(accountId: revenueId, credit: 250),
      ],
    );

    final rows = await AccountingEngine.partyLedger(
      db,
      partyType: 'customer',
      partyId: customerId,
      to: DateTime(2026, 2, 2, 17),
      accountCodes: const ['1100'],
    );

    expect(rows, hasLength(1));
    expect(rows.single['debit'], 100);
    expect(rows.single['running_balance'], 100);
  });

  test('supplier ledger includes miscellaneous debit and credit operations', () async {
    final supplierId = await db.insert('suppliers', {
      'name': 'فروشنده آزمایشی',
      'normalized_name': 'فروشنده آزمایشی',
      'created_at': DateTime(2026, 1, 1).toIso8601String(),
    });
    final supplierAdvanceId = await AccountingEngine.accountId(db, '1110');
    final supplierPayableId = await AccountingEngine.accountId(db, '2000');
    final revenueId = await AccountingEngine.accountId(db, '4000');
    final expenseId = await AccountingEngine.accountId(db, '6000');

    await AccountingEngine.postJournalInTransaction(
      db,
      entryNumber: 'TEST-SUPPLIER-MISC-DEBIT',
      occurredAt: DateTime(2026, 2, 1),
      description: 'فروشنده بدهکار',
      sourceType: 'unit_test',
      sourceId: 'supplier-misc-debit',
      lines: [
        JournalLineInput(
          accountId: supplierAdvanceId,
          debit: 300,
          partyType: 'supplier',
          partyId: supplierId,
        ),
        JournalLineInput(accountId: revenueId, credit: 300),
      ],
    );
    await AccountingEngine.postJournalInTransaction(
      db,
      entryNumber: 'TEST-SUPPLIER-MISC-CREDIT',
      occurredAt: DateTime(2026, 2, 2),
      description: 'فروشنده بستانکار',
      sourceType: 'unit_test',
      sourceId: 'supplier-misc-credit',
      lines: [
        JournalLineInput(accountId: expenseId, debit: 125),
        JournalLineInput(
          accountId: supplierPayableId,
          credit: 125,
          partyType: 'supplier',
          partyId: supplierId,
        ),
      ],
    );

    final rows = await AccountingEngine.partyLedger(
      db,
      partyType: 'supplier',
      partyId: supplierId,
      accountCodes: const ['2000', '1110'],
    );

    expect(rows, hasLength(2));
    expect(rows[0]['debit'], 300);
    expect(rows[1]['credit'], 125);
    expect(rows.last['running_balance'], 175);
  });

  test('received cheque cannot be cancelled after bank clearance', () {
    expect(
      () => AccountingEngine.validateCheckStatusTransition(
        direction: 'received',
        oldStatus: 'pending',
        nextStatus: 'deposited',
      ),
      returnsNormally,
    );
    expect(
      () => AccountingEngine.validateCheckStatusTransition(
        direction: 'received',
        oldStatus: 'cashed',
        nextStatus: 'bounced',
      ),
      returnsNormally,
    );
    expect(
      () => AccountingEngine.validateCheckStatusTransition(
        direction: 'received',
        oldStatus: 'cashed',
        nextStatus: 'cancelled',
      ),
      throwsStateError,
    );
    expect(
      () => AccountingEngine.validateCheckStatusTransition(
        direction: 'received',
        oldStatus: 'cancelled',
        nextStatus: 'cashed',
      ),
      throwsStateError,
    );
  });

  test('issued cheque cannot be cancelled after it has been spent', () {
    expect(
      () => AccountingEngine.validateCheckStatusTransition(
        direction: 'issued',
        oldStatus: 'pending',
        nextStatus: 'spent',
      ),
      returnsNormally,
    );
    expect(
      () => AccountingEngine.validateCheckStatusTransition(
        direction: 'issued',
        oldStatus: 'spent',
        nextStatus: 'bounced',
      ),
      returnsNormally,
    );
    expect(
      () => AccountingEngine.validateCheckStatusTransition(
        direction: 'issued',
        oldStatus: 'spent',
        nextStatus: 'cancelled',
      ),
      throwsStateError,
    );
    expect(
      () => AccountingEngine.validateCheckStatusTransition(
        direction: 'unknown',
        oldStatus: 'pending',
        nextStatus: 'cancelled',
      ),
      throwsStateError,
    );
  });


  test('bouncing a received operation cheque restores the customer receivable once', () async {
    final customerId = await db.insert('customers', {
      'first_name': 'احمد',
      'last_name': 'آزمایشی',
      'created_at': DateTime(2026, 1, 1).toIso8601String(),
    });
    final receivedAt = DateTime(2026, 2, 1);
    const amount = 250.0;
    await AccountingEngine.postJournalInTransaction(
      db,
      entryNumber: 'TEST-RECEIPT-1',
      occurredAt: receivedAt,
      description: 'دریافت آزمایشی چک از مشتری',
      sourceType: 'operation',
      sourceId: 'test-received-check-1',
      lines: [
        JournalLineInput(
          accountId: await AccountingEngine.accountId(db, '1020'),
          debit: amount,
        ),
        JournalLineInput(
          accountId: await AccountingEngine.accountId(db, '1100'),
          credit: amount,
          partyType: 'customer',
          partyId: customerId,
        ),
      ],
    );
    final checkId = await AppDatabaseSchema.insertCheck(
      db,
      checkNumber: 'RC-1001',
      direction: 'received',
      partyType: 'customer',
      partyName: 'احمد آزمایشی',
      partyId: customerId,
      amount: amount,
      issueDate: receivedAt,
      dueDate: DateTime(2026, 3, 1),
      sourceType: 'operation',
      sourceId: 'test-received-check-1',
    );

    await db.transaction((txn) => AccountingEngine.transitionCheckStatusInTransaction(
      txn,
      checkId: checkId,
      expectedOldStatus: 'pending',
      nextStatus: 'bounced',
      occurredAt: DateTime(2026, 3, 2),
    ));

    final check = (await db.query('checks_register', where: 'id = ?', whereArgs: [checkId])).single;
    expect(check['status'], 'bounced');
    expect(await db.query('checks_history', where: 'check_id = ?', whereArgs: [checkId]), hasLength(2));
    final balances = await db.rawQuery(
      '''SELECT a.code, COALESCE(SUM(l.debit - l.credit), 0) AS balance
         FROM journal_lines l
         JOIN accounts a ON a.id = l.account_id
         WHERE (a.code = '1020' OR (a.code = '1100' AND l.party_type = 'customer' AND l.party_id = ?))
         GROUP BY a.code''',
      [customerId],
    );
    final byCode = {for (final row in balances) row['code']: (row['balance'] as num).toDouble()};
    expect(byCode['1020'], closeTo(0, 0.001));
    expect(byCode['1100'], closeTo(0, 0.001));
    final statusEntries = await db.query(
      'journal_entries',
      where: "source_type = 'check_status' AND source_id = ?",
      whereArgs: ['$checkId:bounced'],
    );
    expect(statusEntries, hasLength(1));
  });

  test('cancelling a pending issued purchase cheque restores supplier payable', () async {
    final supplierId = await AppDatabaseSchema.ensureSupplier(db, 'فروشنده آزمایشی');
    final issuedAt = DateTime(2026, 4, 1);
    const amount = 450.0;
    await AccountingEngine.postJournalInTransaction(
      db,
      entryNumber: 'TEST-PURCHASE-CHECK-1',
      occurredAt: issuedAt,
      description: 'ثبت آزمایشی بدهی و چک پرداختی',
      sourceType: 'purchase',
      sourceId: 'test-purchase-check-1',
      lines: [
        JournalLineInput(
          accountId: await AccountingEngine.accountId(db, '2000'),
          debit: amount,
          partyType: 'supplier',
          partyId: supplierId,
        ),
        JournalLineInput(
          accountId: await AccountingEngine.accountId(db, '2110'),
          credit: amount,
          partyType: 'supplier',
          partyId: supplierId,
        ),
      ],
    );
    final checkId = await AppDatabaseSchema.insertCheck(
      db,
      checkNumber: 'PC-2001',
      direction: 'issued',
      partyType: 'supplier',
      partyName: 'فروشنده آزمایشی',
      partyId: supplierId,
      amount: amount,
      issueDate: issuedAt,
      dueDate: DateTime(2026, 5, 1),
      sourceType: 'purchase',
      sourceId: 'test-purchase-check-1',
    );

    await db.transaction((txn) => AccountingEngine.transitionCheckStatusInTransaction(
      txn,
      checkId: checkId,
      expectedOldStatus: 'pending',
      nextStatus: 'cancelled',
      occurredAt: DateTime(2026, 5, 2),
    ));

    final check = (await db.query('checks_register', where: 'id = ?', whereArgs: [checkId])).single;
    expect(check['status'], 'cancelled');
    final balances = await db.rawQuery(
      '''SELECT a.code, COALESCE(SUM(l.debit - l.credit), 0) AS balance
         FROM journal_lines l
         JOIN accounts a ON a.id = l.account_id
         WHERE a.code IN ('2000', '2110')
         GROUP BY a.code''',
    );
    final byCode = {for (final row in balances) row['code']: (row['balance'] as num).toDouble()};
    expect(byCode['2000'], closeTo(0, 0.001));
    expect(byCode['2110'], closeTo(0, 0.001));
    final history = await db.query('checks_history', where: 'check_id = ?', whereArgs: [checkId]);
    expect(history, hasLength(2));
  });



  test('bounced spent supplier cheque restores full supplier payable exactly once', () async {
    final supplierId = await AppDatabaseSchema.ensureSupplier(db, 'فروشنده چک برگشتی');
    final issuedAt = DateTime(2026, 4, 1);
    const purchaseTotal = 1000.0;
    const chequeAmount = 300.0;

    await AccountingEngine.postJournal(
      db,
      entryNumber: 'TEST-PURCHASE-BOUNCE-1',
      occurredAt: issuedAt,
      description: 'خرید با چک و بدهی باقیمانده',
      sourceType: 'purchase',
      sourceId: 'test-purchase-bounce-1',
      lines: [
        JournalLineInput(
          accountId: await AccountingEngine.accountId(db, '1200'),
          debit: purchaseTotal,
        ),
        JournalLineInput(
          accountId: await AccountingEngine.accountId(db, '2110'),
          credit: chequeAmount,
          partyType: 'supplier',
          partyId: supplierId,
        ),
        JournalLineInput(
          accountId: await AccountingEngine.accountId(db, '2000'),
          credit: purchaseTotal - chequeAmount,
          partyType: 'supplier',
          partyId: supplierId,
        ),
      ],
    );
    final checkId = await AppDatabaseSchema.insertCheck(
      db,
      checkNumber: 'PC-BOUNCE-300',
      direction: 'issued',
      partyType: 'supplier',
      partyName: 'فروشنده چک برگشتی',
      partyId: supplierId,
      amount: chequeAmount,
      issueDate: issuedAt,
      dueDate: DateTime(2026, 5, 1),
      sourceType: 'purchase',
      sourceId: 'test-purchase-bounce-1',
    );

    await db.transaction((txn) => AccountingEngine.transitionCheckStatusInTransaction(
      txn,
      checkId: checkId,
      expectedOldStatus: 'pending',
      nextStatus: 'spent',
      occurredAt: DateTime(2026, 5, 1),
    ));
    await db.transaction((txn) => AccountingEngine.transitionCheckStatusInTransaction(
      txn,
      checkId: checkId,
      expectedOldStatus: 'spent',
      nextStatus: 'bounced',
      occurredAt: DateTime(2026, 5, 3),
    ));

    final ledger = await AccountingEngine.partyLedger(
      db,
      partyType: 'supplier',
      partyId: supplierId,
      accountCodes: const ['2000', '1110'],
    );
    expect(ledger.last['running_balance'], closeTo(-purchaseTotal, 0.001));

    final balances = await db.rawQuery(
      '''SELECT a.code, COALESCE(SUM(l.debit - l.credit), 0) AS balance
         FROM journal_lines l
         JOIN accounts a ON a.id = l.account_id
         WHERE a.code IN ('1010', '2000', '2110')
         GROUP BY a.code''',
    );
    final byCode = {
      for (final row in balances)
        row['code']: (row['balance'] as num).toDouble(),
    };
    expect(byCode['1010'], closeTo(0, 0.001));
    expect(byCode['2000'], closeTo(-purchaseTotal, 0.001));
    expect(byCode['2110'], closeTo(0, 0.001));

    await expectLater(
      db.transaction((txn) => AccountingEngine.transitionCheckStatusInTransaction(
        txn,
        checkId: checkId,
        expectedOldStatus: 'spent',
        nextStatus: 'bounced',
        occurredAt: DateTime(2026, 5, 4),
      )),
      throwsStateError,
    );
    expect(
      await db.query(
        'journal_entries',
        where: "source_type = 'check_status' AND source_id = ?",
        whereArgs: ['$checkId:bounced'],
      ),
      hasLength(1),
    );
  });

  test('sale return is blocked while a received cheque is pending or deposited', () async {
    final checkId = await AppDatabaseSchema.insertCheck(
      db,
      checkNumber: 'SALE-RETURN-OPEN',
      direction: 'received',
      partyType: 'customer',
      partyName: 'مشتری برگشت',
      amount: 180,
      issueDate: DateTime(2026, 10, 1),
      dueDate: DateTime(2026, 11, 1),
      sourceType: 'sale',
      sourceId: '1',
    );

    await expectLater(
      AccountingEngine.ensureNoOutstandingChecksForReturn(
        db,
        originalCategory: 'sales',
        originalSourceId: 1,
      ),
      throwsA(isA<StateError>().having(
        (error) => error.message,
        'message',
        contains('SALE-RETURN-OPEN'),
      )),
    );

    await db.update(
      'checks_register',
      {'status': 'deposited'},
      where: 'id = ?',
      whereArgs: [checkId],
    );
    await expectLater(
      AccountingEngine.ensureNoOutstandingChecksForReturn(
        db,
        originalCategory: 'sales',
        originalSourceId: 1,
      ),
      throwsStateError,
    );

    await db.update(
      'checks_register',
      {'status': 'cancelled'},
      where: 'id = ?',
      whereArgs: [checkId],
    );
    await expectLater(
      AccountingEngine.ensureNoOutstandingChecksForReturn(
        db,
        originalCategory: 'sales',
        originalSourceId: 1,
      ),
      completes,
    );
  });

  test('purchase return guard continues to block an unsettled issued cheque', () async {
    await AppDatabaseSchema.insertCheck(
      db,
      checkNumber: 'PURCHASE-RETURN-OPEN',
      direction: 'issued',
      partyType: 'supplier',
      partyName: 'فروشنده برگشت',
      amount: 220,
      issueDate: DateTime(2026, 10, 1),
      dueDate: DateTime(2026, 11, 1),
      sourceType: 'purchase',
      sourceId: '1',
    );

    await expectLater(
      AccountingEngine.ensureNoOutstandingChecksForReturn(
        db,
        originalCategory: 'operations',
        originalSourceId: 1,
      ),
      throwsA(isA<StateError>().having(
        (error) => error.message,
        'message',
        contains('PURCHASE-RETURN-OPEN'),
      )),
    );
  });

  test('settled sale cheques do not block a return', () async {
    final checkId = await AppDatabaseSchema.insertCheck(
      db,
      checkNumber: 'SALE-RETURN-SETTLED',
      direction: 'received',
      partyType: 'customer',
      partyName: 'مشتری تسویه‌شده',
      amount: 90,
      issueDate: DateTime(2026, 10, 1),
      dueDate: DateTime(2026, 11, 1),
      sourceType: 'sale',
      sourceId: '2',
    );
    await db.update(
      'checks_register',
      {'status': 'cashed'},
      where: 'id = ?',
      whereArgs: [checkId],
    );

    await expectLater(
      AccountingEngine.ensureNoOutstandingChecksForReturn(
        db,
        originalCategory: 'sales',
        originalSourceId: 2,
      ),
      completes,
    );
  });

  test('bouncing a sale cheque consumes the applied customer credit before restoring receivable', () async {
    final customerId = await db.insert('customers', {
      'first_name': 'مشتری',
      'last_name': 'فروش آزمایشی',
      'created_at': DateTime(2026, 1, 1).toIso8601String(),
    });
    final issueDate = DateTime(2026, 7, 1);
    const chequeAmount = 300.0;
    await AccountingEngine.postJournalInTransaction(
      db,
      entryNumber: 'TEST-SALE-CHECK-OVERPAYMENT',
      occurredAt: issueDate,
      description: 'فروش آزمایشی با اعتبار مازاد',
      sourceType: 'sale',
      sourceId: 'test-sale-cheque-overpayment',
      lines: [
        JournalLineInput(
          accountId: await AccountingEngine.accountId(db, '1020'),
          debit: chequeAmount,
        ),
        JournalLineInput(
          accountId: await AccountingEngine.accountId(db, '2010'),
          credit: 100,
          partyType: 'customer',
          partyId: customerId,
        ),
        JournalLineInput(
          accountId: await AccountingEngine.accountId(db, '4000'),
          credit: 200,
        ),
      ],
    );
    final checkId = await AppDatabaseSchema.insertCheck(
      db,
      checkNumber: 'SALE-300',
      direction: 'received',
      partyType: 'customer',
      partyName: 'مشتری فروش آزمایشی',
      partyId: customerId,
      amount: chequeAmount,
      issueDate: issueDate,
      dueDate: DateTime(2026, 8, 1),
      sourceType: 'sale',
      sourceId: 'test-sale-cheque-overpayment',
    );

    await db.transaction((txn) => AccountingEngine.transitionCheckStatusInTransaction(
      txn,
      checkId: checkId,
      expectedOldStatus: 'pending',
      nextStatus: 'bounced',
      occurredAt: DateTime(2026, 8, 2),
    ));

    final balances = await db.rawQuery(
      '''SELECT a.code, COALESCE(SUM(l.debit - l.credit), 0) AS balance
         FROM journal_lines l
         JOIN accounts a ON a.id = l.account_id
         WHERE a.code = '1020'
            OR (a.code IN ('1100', '2010') AND l.party_type = 'customer' AND l.party_id = ?)
         GROUP BY a.code''',
      [customerId],
    );
    final byCode = {for (final row in balances) row['code']: (row['balance'] as num).toDouble()};
    expect(byCode['1020'], closeTo(0, 0.001));
    expect(byCode['2010'], closeTo(0, 0.001));
    expect(byCode['1100'], closeTo(200, 0.001));
  });

  test('unlinked historical cheque cannot be bounced and leaves its history unchanged', () async {
    final checkId = await AppDatabaseSchema.insertCheck(
      db,
      checkNumber: 'OLD-UNLINKED-1',
      direction: 'received',
      partyType: 'customer',
      partyName: 'مشتری قدیمی',
      amount: 125,
      issueDate: DateTime(2026, 8, 1),
      dueDate: DateTime(2026, 9, 1),
    );

    await expectLater(
      db.transaction((txn) => AccountingEngine.transitionCheckStatusInTransaction(
        txn,
        checkId: checkId,
        expectedOldStatus: 'pending',
        nextStatus: 'bounced',
        occurredAt: DateTime(2026, 9, 2),
      )),
      throwsStateError,
    );

    final check = (await db.query('checks_register', where: 'id = ?', whereArgs: [checkId])).single;
    expect(check['status'], 'pending');
    expect(await db.query('checks_history', where: 'check_id = ?', whereArgs: [checkId]), hasLength(1));
    expect(
      await db.query('journal_entries', where: "source_type = 'check_status' AND source_id LIKE ?", whereArgs: ['$checkId:%']),
      isEmpty,
    );
  });

  test('stale cheque status update is rejected without changing status or history', () async {
    final checkId = await AppDatabaseSchema.insertCheck(
      db,
      checkNumber: 'RC-STALE',
      direction: 'received',
      partyType: 'customer',
      partyName: 'مشتری آزمایشی',
      amount: 100,
      issueDate: DateTime(2026, 6, 1),
      dueDate: DateTime(2026, 7, 1),
    );
    await db.transaction((txn) => AccountingEngine.transitionCheckStatusInTransaction(
      txn,
      checkId: checkId,
      expectedOldStatus: 'pending',
      nextStatus: 'deposited',
      occurredAt: DateTime(2026, 6, 2),
    ));

    await expectLater(
      db.transaction((txn) => AccountingEngine.transitionCheckStatusInTransaction(
        txn,
        checkId: checkId,
        expectedOldStatus: 'pending',
        nextStatus: 'cashed',
        occurredAt: DateTime(2026, 6, 3),
      )),
      throwsStateError,
    );
    final check = (await db.query('checks_register', where: 'id = ?', whereArgs: [checkId])).single;
    expect(check['status'], 'deposited');
    expect(await db.query('checks_history', where: 'check_id = ?', whereArgs: [checkId]), hasLength(2));
    expect(
      await db.query('journal_entries', where: "source_type = 'check_status' AND source_id LIKE ?", whereArgs: ['$checkId:%']),
      isEmpty,
    );
  });

  test('localized amount parser handles Persian and Arabic digits and separators', () {
    expect(AccountingEngine.parseLocalizedAmount('۱۲۳٬۴۵۶'), 123456);
    expect(AccountingEngine.parseLocalizedAmount('١٢٣,٤٥٦'), 123456);
    expect(AccountingEngine.parseLocalizedAmount('۱۲۳٫۵'), 123.5);
    expect(AccountingEngine.parseLocalizedAmount('1 234 567'), 1234567);
    expect(AccountingEngine.parseLocalizedAmount('عدد نامعتبر'), 0);
  });

  test('supplier identity trims and collapses whitespace before deduplication', () async {
    final firstId = await AppDatabaseSchema.ensureSupplier(
      db,
      '  ACME   Tools  ',
    );
    final secondId = await AppDatabaseSchema.ensureSupplier(
      db,
      'acme tools',
    );

    expect(secondId, firstId);
    expect(await db.query('suppliers'), hasLength(1));
    final supplier = (await db.query('suppliers')).single;
    expect(supplier['name'], 'ACME Tools');
    expect(supplier['normalized_name'], 'acme tools');
  });

  test('party ledger date filter carries forward the opening balance', () async {
    final receivableId = await AccountingEngine.accountId(db, '1100');
    final revenueId = await AccountingEngine.accountId(db, '4000');
    final cashId = await AccountingEngine.accountId(db, '1000');

    await AccountingEngine.postJournal(
      db,
      entryNumber: 'PARTY-OPENING-1',
      occurredAt: DateTime(2026, 1, 5),
      description: 'مانده قبل از دوره',
      sourceType: 'unit_test',
      sourceId: 'party-opening-1',
      lines: [
        JournalLineInput(
          accountId: receivableId,
          debit: 500,
          partyType: 'customer',
          partyId: 42,
        ),
        JournalLineInput(accountId: revenueId, credit: 500),
      ],
    );
    await AccountingEngine.postJournal(
      db,
      entryNumber: 'PARTY-PERIOD-1',
      occurredAt: DateTime(2026, 2, 5),
      description: 'دریافت در دوره',
      sourceType: 'unit_test',
      sourceId: 'party-period-1',
      lines: [
        JournalLineInput(
          accountId: cashId,
          debit: 200,
        ),
        JournalLineInput(
          accountId: receivableId,
          credit: 200,
          partyType: 'customer',
          partyId: 42,
        ),
      ],
    );

    final ledger = await AccountingEngine.partyLedger(
      db,
      partyType: 'customer',
      partyId: 42,
      from: DateTime(2026, 2, 1),
      to: DateTime(2026, 2, 28),
    );

    expect(ledger, hasLength(1));
    expect(ledger.single['running_balance'], 300.0);
    expect(ledger.single['debit'], 0);
    expect(ledger.single['credit'], 200);
  });

  test('party ledger account filter includes AR and customer credit only', () async {
    final receivableId = await AccountingEngine.accountId(db, '1100');
    final customerCreditId = await AccountingEngine.accountId(db, '2010');
    final revenueId = await AccountingEngine.accountId(db, '4000');
    final returnRevenueId = await AccountingEngine.accountId(db, '4100');
    final cashId = await AccountingEngine.accountId(db, '1000');

    await AccountingEngine.postJournal(
      db,
      entryNumber: 'PARTY-FILTER-OPENING',
      occurredAt: DateTime(2026, 1, 5),
      description: 'فاکتور و گردش اعتبار قبل از دوره',
      sourceType: 'unit_test',
      sourceId: 'party-filter-opening',
      lines: [
        JournalLineInput(
          accountId: receivableId,
          debit: 100,
          partyType: 'customer',
          partyId: 84,
        ),
        // Revenue is intentionally tagged to the party too; the subledger
        // must not count it in addition to the receivable.
        JournalLineInput(
          accountId: revenueId,
          credit: 100,
          partyType: 'customer',
          partyId: 84,
        ),
      ],
    );
    await AccountingEngine.postJournal(
      db,
      entryNumber: 'PARTY-FILTER-DEPOSIT',
      occurredAt: DateTime(2026, 1, 8),
      description: 'بیعانه مشتری',
      sourceType: 'unit_test',
      sourceId: 'party-filter-deposit',
      lines: [
        JournalLineInput(accountId: cashId, debit: 50),
        JournalLineInput(
          accountId: customerCreditId,
          credit: 50,
          partyType: 'customer',
          partyId: 84,
        ),
      ],
    );
    await AccountingEngine.postJournal(
      db,
      entryNumber: 'PARTY-FILTER-RETURN',
      occurredAt: DateTime(2026, 2, 8),
      description: 'برگشت از فروش',
      sourceType: 'unit_test',
      sourceId: 'party-filter-return',
      lines: [
        JournalLineInput(accountId: returnRevenueId, debit: 30),
        JournalLineInput(
          accountId: receivableId,
          credit: 30,
          partyType: 'customer',
          partyId: 84,
        ),
      ],
    );

    final ledger = await AccountingEngine.partyLedger(
      db,
      partyType: 'customer',
      partyId: 84,
      from: DateTime(2026, 2, 1),
      to: DateTime(2026, 2, 28),
      accountCodes: ['1100', '2010'],
    );

    expect(ledger, hasLength(1));
    expect(ledger.single['account_code'], '1100');
    expect(ledger.single['credit'], 30);
    expect(ledger.single['running_balance'], 20);
  });

  test('stock cardex carries movements before the selected date as opening balance',
      () async {
    final productId = await addProduct('کالای آزمون کارتکس');
    await AccountingEngine.recordStockMovement(
      db,
      productId: productId,
      movementType: 'opening_balance',
      quantityDelta: 10,
      unitCost: 100,
      occurredAt: DateTime(2026, 1, 1),
    );
    await AccountingEngine.recordStockMovement(
      db,
      productId: productId,
      movementType: 'sale',
      quantityDelta: -3,
      unitCost: 100,
      occurredAt: DateTime(2026, 1, 10, 12),
    );
    await AccountingEngine.recordStockMovement(
      db,
      productId: productId,
      movementType: 'purchase',
      quantityDelta: 2,
      unitCost: 120,
      occurredAt: DateTime(2026, 1, 14, 9),
    );

    final cardex = await AccountingEngine.stockCardex(
      db,
      productId,
      from: DateTime(2026, 1, 10),
      to: DateTime(2026, 1, 31),
    );

    expect(cardex, hasLength(2));
    expect(cardex.first['opening_quantity'], 10.0);
    expect(cardex.first['running_quantity'], 7.0);
    expect(cardex.last['running_quantity'], 9.0);
  });

  test('party ledger start date includes the full selected day and carries opening balance', () async {
    final customerId = await db.insert('customers', {
      'first_name': 'مشتری',
      'last_name': 'آزمایش شروع',
      'created_at': DateTime(2026, 1, 1).toIso8601String(),
    });
    final receivableId = await AccountingEngine.accountId(db, '1100');
    final revenueId = await AccountingEngine.accountId(db, '4000');

    Future<void> post(String number, DateTime at, double amount) async {
      await AccountingEngine.postJournalInTransaction(
        db,
        entryNumber: number,
        occurredAt: at,
        description: number,
        sourceType: 'unit_test',
        sourceId: number,
        lines: [
          JournalLineInput(
            accountId: receivableId,
            debit: amount,
            partyType: 'customer',
            partyId: customerId,
          ),
          JournalLineInput(accountId: revenueId, credit: amount),
        ],
      );
    }

    await post('TEST-LEDGER-START-OPENING', DateTime(2026, 2, 1, 23, 59), 40);
    await post('TEST-LEDGER-START-DAY', DateTime(2026, 2, 2, 0, 30), 100);

    final rows = await AccountingEngine.partyLedger(
      db,
      partyType: 'customer',
      partyId: customerId,
      from: DateTime(2026, 2, 2, 17),
      accountCodes: const ['1100'],
    );

    expect(rows, hasLength(1));
    expect(rows.single['debit'], 100);
    expect(rows.single['running_balance'], 140);
  });

  test('stock cardex end date includes the full selected day only', () async {
    final productId = await addProduct('کالای آزمون پایان کارتکس');
    await AccountingEngine.recordStockMovement(
      db,
      productId: productId,
      movementType: 'purchase',
      quantityDelta: 4,
      unitCost: 50,
      occurredAt: DateTime(2026, 3, 1, 10),
    );
    await AccountingEngine.recordStockMovement(
      db,
      productId: productId,
      movementType: 'sale',
      quantityDelta: -1,
      unitCost: 50,
      occurredAt: DateTime(2026, 3, 2, 23, 59),
    );
    await AccountingEngine.recordStockMovement(
      db,
      productId: productId,
      movementType: 'purchase',
      quantityDelta: 7,
      unitCost: 60,
      occurredAt: DateTime(2026, 3, 3, 0, 1),
    );

    final cardex = await AccountingEngine.stockCardex(
      db,
      productId,
      from: DateTime(2026, 3, 1),
      to: DateTime(2026, 3, 2, 18),
    );

    expect(cardex, hasLength(2));
    expect(cardex.last['running_quantity'], 3.0);
  });

  test('stock cardex start date includes full selected day and opening quantity', () async {
    final productId = await addProduct('کالای آزمون ابتدای کارتکس');
    await AccountingEngine.recordStockMovement(
      db,
      productId: productId,
      movementType: 'purchase',
      quantityDelta: 4,
      unitCost: 50,
      occurredAt: DateTime(2026, 3, 1, 23, 59),
    );
    await AccountingEngine.recordStockMovement(
      db,
      productId: productId,
      movementType: 'purchase',
      quantityDelta: 2,
      unitCost: 60,
      occurredAt: DateTime(2026, 3, 2, 0, 30),
    );

    final cardex = await AccountingEngine.stockCardex(
      db,
      productId,
      from: DateTime(2026, 3, 2, 17),
    );

    expect(cardex, hasLength(1));
    expect(cardex.single['opening_quantity'], 4.0);
    expect(cardex.single['running_quantity'], 6.0);
  });

  test('weighted average cost uses immutable movement costs rather than current product price',
      () async {
    final productId = await addProduct('کالای آزمون بهای تمام‌شده');
    await AccountingEngine.recordStockMovement(
      db,
      productId: productId,
      movementType: 'purchase',
      quantityDelta: 10,
      unitCost: 100,
      occurredAt: DateTime(2026, 1, 1),
    );
    await AccountingEngine.recordStockMovement(
      db,
      productId: productId,
      movementType: 'purchase',
      quantityDelta: 10,
      unitCost: 200,
      occurredAt: DateTime(2026, 1, 2),
    );
    await AccountingEngine.recordStockMovement(
      db,
      productId: productId,
      movementType: 'sale',
      quantityDelta: -5,
      unitCost: 150,
      occurredAt: DateTime(2026, 1, 3),
    );
    await db.update(
      'products',
      {'purchase_price': 9999},
      where: 'id = ?',
      whereArgs: [productId],
    );

    final cost = await AccountingEngine.averageUnitCost(
      db,
      productId,
      fallback: 9999,
    );

    expect(cost, closeTo(150, 0.000001));
  });

  test('normalized sales insert posts invoice stock journal and received cheque once', () async {
    final productId = await addProduct('کالای فروش آزمون');
    await db.update(
      'products',
      {'quantity': 10.0, 'purchase_price': 50.0},
      where: 'id = ?',
      whereArgs: [productId],
    );
    final customerId = await db.insert('customers', {
      'first_name': 'مشتری',
      'last_name': 'آزمون',
      'created_at': DateTime(2026, 1, 1).toIso8601String(),
    });
    final cashId = await AccountingEngine.accountId(db, '1000');
    final creditId = await AccountingEngine.accountId(db, '2010');
    await AccountingEngine.postJournal(
      db,
      entryNumber: 'CUSTOMER-CREDIT-1',
      occurredAt: DateTime(2026, 1, 2),
      description: 'بیعانه اولیه',
      sourceType: 'unit_test',
      sourceId: 'customer-credit-1',
      lines: [
        JournalLineInput(accountId: cashId, debit: 200),
        JournalLineInput(
          accountId: creditId,
          credit: 200,
          partyType: 'customer',
          partyId: customerId,
        ),
      ],
    );

    final createdAt = DateTime(2026, 2, 1).toIso8601String();
    final sale = <String, String>{
      'شماره فاکتور': 'HOS-00001',
      'نام مشتری': 'مشتری آزمون',
      'شناسه مشتری': customerId.toString(),
      'تعداد': '2',
      'مبلغ کل': '1000',
      'تخفیف': '100',
      'مبلغ مالیات': '90',
      'مبلغ دریافتی': '300',
      'بیعانه تخصیص‌یافته': '200',
      'روش پرداخت': 'چک',
      'شماره چک': 'CHK-TEST-100',
      'بانک چک': 'بانک آزمون',
      'تاریخ میلادی': createdAt,
      'تاریخ سررسید میلادی': DateTime(2026, 3, 2).toIso8601String(),
      'ردیف‌های فاکتور': jsonEncode([
        {
          'product_id': productId.toString(),
          'description': 'کالای فروش آزمون',
          'unit': 'عدد',
          'quantity': 2,
          'unit_price': 500,
          'line_total': 1000,
          'is_used': '0',
        },
      ]),
    };

    await db.transaction((txn) async {
      final sourceId = await txn.insert('records', {
        'category': 'sales',
        'data': jsonEncode(sale),
        'created_at': createdAt,
      });
      await AppDatabaseSchema.insertLegacyRecord(
        txn, 'sales', sale, sourceId, createdAt,
      );
    });

    final product = await db.query(
      'products',
      columns: ['quantity'],
      where: 'id = ?',
      whereArgs: [productId],
    );
    expect((product.single['quantity'] as num).toDouble(), 8.0);

    final movementRows = await db.query(
      'stock_movements',
      where: "reference_type = 'sale'",
    );
    expect(movementRows, hasLength(1));
    expect((movementRows.single['total_cost'] as num).toDouble(), 100.0);

    final invoiceRows = await db.query('invoices');
    expect(invoiceRows, hasLength(1));
    expect((invoiceRows.single['total'] as num).toDouble(), 990.0);
    expect(await db.query('invoice_items'), hasLength(1));

    final journalRows = await db.query(
      'journal_entries',
      where: "source_type = 'sale'",
    );
    expect(journalRows, hasLength(1));
    final saleJournalId = journalRows.single['id'] as int;
    final totals = await db.rawQuery(
      '''SELECT SUM(debit) AS debit_total, SUM(credit) AS credit_total
         FROM journal_lines WHERE entry_id = ?''',
      [saleJournalId],
    );
    expect(
      (totals.single['debit_total'] as num).toDouble(),
      closeTo((totals.single['credit_total'] as num).toDouble(), 0.001),
    );

    final receivableRows = await db.rawQuery(
      '''SELECT SUM(debit - credit) AS balance FROM journal_lines
         WHERE account_id = ? AND party_type = 'customer' AND party_id = ?''',
      [await AccountingEngine.accountId(db, '1100'), customerId],
    );
    expect((receivableRows.single['balance'] as num).toDouble(), 490.0);

    final checks = await db.query(
      'checks_register',
      where: "source_type = 'sale' AND source_id = ?",
      whereArgs: [journalRows.single['source_id']],
    );
    expect(checks, hasLength(1));
    expect(checks.single['direction'], 'received');
    expect(checks.single['status'], 'pending');
  });

  test('sales invoice with outstanding balance requires a linked customer', () async {
    final createdAt = DateTime(2026, 2, 3).toIso8601String();
    final sale = <String, String>{
      'شماره فاکتور': 'HOS-UNLINKED',
      'نام مشتری': 'مشتری بدون پرونده',
      'تعداد': '1',
      'مبلغ کل': '100',
      'تخفیف': '0',
      'مبلغ مالیات': '0',
      'مبلغ دریافتی': '20',
      'روش پرداخت': 'نقدی',
      'تاریخ میلادی': createdAt,
      'شرح کالا/خدمت': 'خدمت آزمون',
    };

    await expectLater(
      db.transaction((txn) async {
        final sourceId = await txn.insert('records', {
          'category': 'sales',
          'data': jsonEncode(sale),
          'created_at': createdAt,
        });
        await AppDatabaseSchema.insertLegacyRecord(
          txn, 'sales', sale, sourceId, createdAt,
        );
      }),
      throwsA(isA<StateError>()),
    );
    expect(await db.query('invoices'), isEmpty);
    expect(
      await db.query('journal_entries', where: "source_type = 'sale'"),
      isEmpty,
    );
  });

  test('invoice cannot allocate more customer credit than the available balance', () async {
    final customerId = await db.insert('customers', {
      'first_name': 'مشتری',
      'last_name': 'اعتبار',
      'created_at': DateTime(2026, 1, 1).toIso8601String(),
    });
    final cashId = await AccountingEngine.accountId(db, '1000');
    final creditId = await AccountingEngine.accountId(db, '2010');
    await AccountingEngine.postJournal(
      db,
      entryNumber: 'CUSTOMER-CREDIT-SMALL',
      occurredAt: DateTime(2026, 1, 2),
      description: 'اعتبار محدود مشتری',
      sourceType: 'unit_test',
      sourceId: 'customer-credit-small',
      lines: [
        JournalLineInput(accountId: cashId, debit: 100),
        JournalLineInput(
          accountId: creditId,
          credit: 100,
          partyType: 'customer',
          partyId: customerId,
        ),
      ],
    );

    final createdAt = DateTime(2026, 2, 4).toIso8601String();
    final sale = <String, String>{
      'شماره فاکتور': 'HOS-EXCESS-CREDIT',
      'نام مشتری': 'مشتری اعتبار',
      'شناسه مشتری': customerId.toString(),
      'تعداد': '1',
      'مبلغ کل': '500',
      'تخفیف': '0',
      'مبلغ مالیات': '0',
      'مبلغ دریافتی': '0',
      'بیعانه تخصیص‌یافته': '200',
      'روش پرداخت': 'نقدی',
      'تاریخ میلادی': createdAt,
      'شرح کالا/خدمت': 'خدمت آزمون',
    };

    await expectLater(
      db.transaction((txn) async {
        final sourceId = await txn.insert('records', {
          'category': 'sales',
          'data': jsonEncode(sale),
          'created_at': createdAt,
        });
        await AppDatabaseSchema.insertLegacyRecord(
          txn, 'sales', sale, sourceId, createdAt,
        );
      }),
      throwsA(isA<StateError>()),
    );
    expect(await db.query('invoices'), isEmpty);
    expect(
      await db.query('journal_entries', where: "source_type = 'sale'"),
      isEmpty,
    );
  });

  test('linked repair labor is recognized once and invoice receipt reduces its balance', () async {
    final customerId = await db.insert('customers', {
      'first_name': 'مشتری',
      'last_name': 'تعمیر',
      'created_at': DateTime(2026, 1, 1).toIso8601String(),
    });
    final repairCreatedAt = DateTime(2026, 1, 1).toIso8601String();
    final repairSourceId = await db.insert('records', {
      'category': 'repairs',
      'data': '{}',
      'created_at': repairCreatedAt,
    });
    await db.insert('repairs', {
      'customer_id': customerId,
      'customer_name_snapshot': 'مشتری تعمیر',
      'device_type': 'دستگاه آزمایش',
      'received_at': repairCreatedAt,
      'labor_cost': 500.0,
      'legacy_source_id': repairSourceId,
    });

    final receivableId = await AccountingEngine.accountId(db, '1100');
    final repairIncomeId = await AccountingEngine.accountId(db, '4010');
    await AccountingEngine.postJournal(
      db,
      entryNumber: 'REPAIR-$repairSourceId',
      occurredAt: DateTime(2026, 1, 1),
      description: 'اجرت پذیرش تعمیر',
      sourceType: 'repair',
      sourceId: repairSourceId.toString(),
      lines: [
        JournalLineInput(
          accountId: receivableId,
          debit: 500,
          partyType: 'customer',
          partyId: customerId,
        ),
        JournalLineInput(accountId: repairIncomeId, credit: 500),
      ],
    );

    final createdAt = DateTime(2026, 2, 4).toIso8601String();
    final sale = <String, String>{
      'شماره فاکتور': 'HOS-REPAIR-1',
      'نام مشتری': 'مشتری تعمیر',
      'شناسه مشتری': customerId.toString(),
      'پذیرش تعمیر مرتبط': repairSourceId.toString(),
      'تعداد': '1',
      'مبلغ کل': '500',
      'تخفیف': '0',
      'مبلغ مالیات': '0',
      'مبلغ دریافتی': '200',
      'روش پرداخت': 'نقدی',
      'تاریخ میلادی': createdAt,
      'ردیف‌های فاکتور': jsonEncode([
        {
          'product_id': '',
          'description': 'اجرت تعمیر',
          'unit': 'خدمت',
          'quantity': 1,
          'unit_price': 500,
          'line_total': 500,
        },
      ]),
    };

    await db.transaction((txn) async {
      final sourceId = await txn.insert('records', {
        'category': 'sales',
        'data': jsonEncode(sale),
        'created_at': createdAt,
      });
      await AppDatabaseSchema.insertLegacyRecord(
        txn, 'sales', sale, sourceId, createdAt,
      );
    });

    final balanceRows = await db.rawQuery(
      '''SELECT COALESCE(SUM(debit - credit), 0) AS balance
         FROM journal_lines
         WHERE account_id = ? AND party_type = 'customer' AND party_id = ?''',
      [receivableId, customerId],
    );
    expect((balanceRows.single['balance'] as num).toDouble(), 300.0);

    final incomeRows = await db.rawQuery(
      '''SELECT COALESCE(SUM(credit - debit), 0) AS balance
         FROM journal_lines WHERE account_id = ?''',
      [repairIncomeId],
    );
    expect((incomeRows.single['balance'] as num).toDouble(), 500.0);
  });

  test('failed stock deduction rolls back normalized invoice and journal', () async {
    final productId = await addProduct('کالای ناموجود آزمون');
    await db.update(
      'products',
      {'quantity': 1.0, 'purchase_price': 25.0},
      where: 'id = ?',
      whereArgs: [productId],
    );
    final createdAt = DateTime(2026, 2, 5).toIso8601String();
    final sale = <String, String>{
      'شماره فاکتور': 'HOS-NO-STOCK',
      'تعداد': '2',
      'مبلغ کل': '200',
      'تخفیف': '0',
      'مبلغ مالیات': '0',
      'مبلغ دریافتی': '200',
      'روش پرداخت': 'نقدی',
      'تاریخ میلادی': createdAt,
      'ردیف‌های فاکتور': jsonEncode([
        {
          'product_id': productId.toString(),
          'description': 'کالای ناموجود آزمون',
          'unit': 'عدد',
          'quantity': 2,
          'unit_price': 100,
          'line_total': 200,
        },
      ]),
    };

    await expectLater(
      db.transaction((txn) async {
        final sourceId = await txn.insert('records', {
          'category': 'sales',
          'data': jsonEncode(sale),
          'created_at': createdAt,
        });
        await AppDatabaseSchema.insertLegacyRecord(
          txn, 'sales', sale, sourceId, createdAt,
        );
      }),
      throwsA(isA<StateError>()),
    );
    expect(await db.query('invoices'), isEmpty);
    expect(await db.query('invoice_items'), isEmpty);
    expect(
      await db.query('journal_entries', where: "source_type = 'sale'"),
      isEmpty,
    );
    final product = await db.query(
      'products',
      columns: ['quantity'],
      where: 'id = ?',
      whereArgs: [productId],
    );
    expect((product.single['quantity'] as num).toDouble(), 1.0);
  });

  test('balanced journal is stored and unbalanced journal is rejected',
      () async {
    final cashId = await AccountingEngine.accountId(db, '1000');
    final revenueId = await AccountingEngine.accountId(db, '4000');
    await AccountingEngine.postJournal(
      db,
      entryNumber: 'TEST-BALANCED-1',
      occurredAt: DateTime(2026, 2, 1),
      description: 'آزمون تراز سند',
      sourceType: 'unit_test',
      sourceId: 'balanced-1',
      lines: [
        JournalLineInput(accountId: cashId, debit: 250),
        JournalLineInput(accountId: revenueId, credit: 250),
      ],
    );

    final stored = await db.rawQuery(
      '''SELECT SUM(debit) AS debit, SUM(credit) AS credit
         FROM journal_lines''',
    );
    expect((stored.first['debit'] as num).toDouble(), 250);
    expect((stored.first['credit'] as num).toDouble(), 250);

    await expectLater(
      AccountingEngine.postJournal(
        db,
        entryNumber: 'TEST-UNBALANCED-1',
        occurredAt: DateTime(2026, 2, 2),
        description: 'آزمون سند نامتوازن',
        sourceType: 'unit_test',
        sourceId: 'unbalanced-1',
        lines: [
          JournalLineInput(accountId: cashId, debit: 250),
          JournalLineInput(accountId: revenueId, credit: 200),
        ],
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('partial sale returns restore stock and cost, offset receivable then customer credit, and prevent over-return', () async {
    final productId = await addProduct('کالای برگشت فروش');
    await db.update('products', {'quantity': 0.0, 'purchase_price': 50.0},
        where: 'id = ?', whereArgs: [productId]);
    await AccountingEngine.recordStockMovementInTransaction(
      db,
      productId: productId,
      movementType: 'purchase',
      quantityDelta: 10,
      unitCost: 50,
      referenceType: 'test_purchase',
      referenceId: 'sale-return-stock',
      occurredAt: DateTime(2026, 1, 1),
    );
    final customerId = await db.insert('customers', {
      'first_name': 'مشتری',
      'last_name': 'برگشت فروش',
      'created_at': DateTime(2026, 1, 1).toIso8601String(),
    });
    const sourceId = 99101;
    final occurredAt = DateTime(2026, 2, 1);
    final sale = <String, String>{
      'شماره فاکتور': 'TEST-RETURN-99101',
      'شناسه مشتری': customerId.toString(),
      'نام مشتری': 'مشتری برگشت فروش',
      'تعداد': '4',
      'مبلغ کل': '400',
      'تخفیف': '40',
      'مبلغ مالیات': '36',
      'مبلغ دریافتی': '200',
      'بیعانه تخصیص‌یافته': '0',
      'روش پرداخت': 'نقدی',
      'ردیف‌های فاکتور': jsonEncode([
        {
          'kind': 'product',
          'product_id': productId.toString(),
          'description': 'کالای برگشت فروش',
          'quantity': '4',
          'line_total': '400',
        },
      ]),
    };
    await db.insert('records', {
      'id': sourceId,
      'category': 'sales',
      'data': jsonEncode(sale),
      'created_at': occurredAt.toIso8601String(),
    });
    await DemoStore.postSaleInTransaction(
      db,
      recordId: sourceId,
      item: sale,
      occurredAt: occurredAt,
    );
    DemoStore.useDatabaseForTesting(db);

    await DemoStore.addReturn(
      originalCategory: 'sales',
      originalSourceId: sourceId,
      quantity: 1,
      reason: 'آزمون برگشت اول',
      settleAsCash: false,
    );
    await DemoStore.addReturn(
      originalCategory: 'sales',
      originalSourceId: sourceId,
      quantity: 1,
      reason: 'آزمون برگشت دوم',
      settleAsCash: false,
    );

    final product = (await db.query('products', columns: ['quantity'],
        where: 'id = ?', whereArgs: [productId])).single;
    expect((product['quantity'] as num).toDouble(), 8.0);
    final returns = await db.query('document_returns',
        where: 'original_category = ? AND original_source_id = ?',
        whereArgs: ['sales', sourceId]);
    expect(returns, hasLength(2));
    expect(returns.fold<double>(0, (sum, row) => sum + (row['amount'] as num).toDouble()), 198.0);

    final returnJournals = await db.query('journal_entries',
        where: "source_type = 'document_return' AND source_id IN (?, ?)",
        whereArgs: [returns[0]['id'].toString(), returns[1]['id'].toString()]);
    expect(returnJournals, hasLength(2));
    for (final journal in returnJournals) {
      final totals = (await db.rawQuery(
        'SELECT SUM(debit) AS debit_total, SUM(credit) AS credit_total FROM journal_lines WHERE entry_id = ?',
        [journal['id']],
      )).single;
      expect((totals['debit_total'] as num).toDouble(),
          closeTo((totals['credit_total'] as num).toDouble(), 0.001));
    }

    final inventoryId = await AccountingEngine.accountId(db, '1200');
    final cogsId = await AccountingEngine.accountId(db, '5000');
    final returnCost = await db.rawQuery(
      'SELECT COALESCE(SUM(debit), 0) AS restored FROM journal_lines WHERE account_id = ? AND entry_id IN (SELECT id FROM journal_entries WHERE source_type = \'document_return\')',
      [inventoryId],
    );
    final cogsCredit = await db.rawQuery(
      'SELECT COALESCE(SUM(credit), 0) AS restored FROM journal_lines WHERE account_id = ? AND entry_id IN (SELECT id FROM journal_entries WHERE source_type = \'document_return\')',
      [cogsId],
    );
    expect((returnCost.single['restored'] as num).toDouble(), 100.0);
    expect((cogsCredit.single['restored'] as num).toDouble(), 100.0);

    final customerCreditId = await AccountingEngine.accountId(db, '2010');
    final credit = await db.rawQuery(
      "SELECT COALESCE(SUM(credit - debit), 0) AS balance FROM journal_lines WHERE account_id = ? AND party_type = 'customer' AND party_id = ?",
      [customerCreditId, customerId],
    );
    expect((credit.single['balance'] as num).toDouble(), 2.0);

    await expectLater(
      DemoStore.addReturn(
        originalCategory: 'sales',
        originalSourceId: sourceId,
        quantity: 3,
        reason: 'بیش از مانده قابل برگشت',
        settleAsCash: false,
      ),
      throwsA(isA<StateError>()),
    );
    expect(await db.query('document_returns',
        where: 'original_category = ? AND original_source_id = ?',
        whereArgs: ['sales', sourceId]), hasLength(2));
    final finalProduct = (await db.query('products', columns: ['quantity'],
        where: 'id = ?', whereArgs: [productId])).single;
    expect((finalProduct['quantity'] as num).toDouble(), 8.0);
  });

  test('partial sale returns restore stock and reverse cost without allowing over-return', () async {
    final productId = await addProduct('کالای برگشت فروش');
    final saleDate = DateTime.now();
    await AccountingEngine.recordStockMovementInTransaction(
      db,
      productId: productId,
      movementType: 'purchase',
      quantityDelta: 10,
      unitCost: 100,
      referenceType: 'test_purchase',
      referenceId: 'return-sale-stock',
      occurredAt: saleDate.subtract(const Duration(days: 1)),
    );
    final saleItem = <String, String>{
      'شماره فاکتور': 'TEST-RETURN-01',
      'مبلغ کل': '600',
      'تخفیف': '0',
      'مبلغ مالیات': '0',
      'مبلغ دریافتی': '600',
      'بیعانه تخصیص‌یافته': '0',
      'روش پرداخت': 'نقدی',
      'ردیف‌های فاکتور': jsonEncode([
        {
          'kind': 'product',
          'product_id': productId.toString(),
          'description': 'کالای برگشت فروش',
          'quantity': '3',
          'line_total': '600',
        },
      ]),
    };
    final saleRecordId = await db.insert('records', {
      'category': 'sales',
      'data': jsonEncode(saleItem),
      'created_at': saleDate.toIso8601String(),
    });
    await DemoStore.postSaleInTransaction(
      db,
      recordId: saleRecordId,
      item: saleItem,
      occurredAt: saleDate,
    );

    final firstReturn = await DemoStore.addReturnInTransaction(
      db,
      originalCategory: 'sales',
      originalSourceId: saleRecordId,
      quantity: 1,
      reason: 'آزمایش برگشت جزئی',
      settleAsCash: true,
      occurredAt: saleDate.add(const Duration(minutes: 1)),
    );
    expect(firstReturn['مبلغ برگشت'], '200');

    final productAfterFirstReturn = (await db.query(
      'products',
      columns: ['quantity'],
      where: 'id = ?',
      whereArgs: [productId],
    )).single;
    expect((productAfterFirstReturn['quantity'] as num).toDouble(), 8);

    final returnMovement = (await db.query(
      'stock_movements',
      where: "reference_type = 'sale_return'",
    )).single;
    expect((returnMovement['quantity_delta'] as num).toDouble(), 1);
    expect((returnMovement['unit_cost'] as num).toDouble(), 100);
    expect((returnMovement['total_cost'] as num).toDouble(), 100);

    final returnJournal = (await db.query(
      'journal_entries',
      where: "source_type = 'document_return'",
    )).single;
    final journalTotals = (await db.rawQuery(
      'SELECT SUM(debit) AS debit_total, SUM(credit) AS credit_total FROM journal_lines WHERE entry_id = ?',
      [returnJournal['id']],
    )).single;
    expect(
      (journalTotals['debit_total'] as num).toDouble(),
      closeTo((journalTotals['credit_total'] as num).toDouble(), 0.001),
    );

    final returnLines = await db.rawQuery(
      '''SELECT a.code, l.debit, l.credit
         FROM journal_lines l JOIN accounts a ON a.id = l.account_id
         WHERE l.entry_id = ?''',
      [returnJournal['id']],
    );
    double debitFor(String code) => returnLines
        .where((row) => row['code'] == code)
        .fold<double>(0, (sum, row) => sum + (row['debit'] as num).toDouble());
    double creditFor(String code) => returnLines
        .where((row) => row['code'] == code)
        .fold<double>(0, (sum, row) => sum + (row['credit'] as num).toDouble());
    expect(debitFor('4100'), 200);
    expect(creditFor('1000'), 200);
    expect(debitFor('1200'), 100);
    expect(creditFor('5000'), 100);

    await DemoStore.addReturnInTransaction(
      db,
      originalCategory: 'sales',
      originalSourceId: saleRecordId,
      quantity: 2,
      reason: 'تکمیل برگشت',
      settleAsCash: true,
      occurredAt: saleDate.add(const Duration(minutes: 2)),
    );
    await expectLater(
      DemoStore.addReturnInTransaction(
        db,
        originalCategory: 'sales',
        originalSourceId: saleRecordId,
        quantity: 0.1,
        reason: 'بیشتر از مقدار فاکتور',
        settleAsCash: true,
        occurredAt: saleDate.add(const Duration(minutes: 3)),
      ),
      throwsA(isA<StateError>()),
    );

    final allReturns = await db.query(
      'document_returns',
      where: 'original_category = ? AND original_source_id = ?',
      whereArgs: ['sales', saleRecordId],
    );
    expect(allReturns, hasLength(2));
    final finalProduct = (await db.query(
      'products',
      columns: ['quantity'],
      where: 'id = ?',
      whereArgs: [productId],
    )).single;
    expect((finalProduct['quantity'] as num).toDouble(), 10);
  });


  test('multi-line sale return restores only the selected product at its original cost', () async {
    final firstProductId = await addProduct('کالای ردیف اول');
    final secondProductId = await addProduct('کالای ردیف دوم');
    final saleDate = DateTime(2026, 3, 10, 10);
    await AccountingEngine.recordStockMovementInTransaction(
      db,
      productId: firstProductId,
      movementType: 'purchase',
      quantityDelta: 5,
      unitCost: 10,
      referenceType: 'test_purchase',
      referenceId: 'multi-line-first',
      occurredAt: saleDate.subtract(const Duration(days: 1)),
    );
    await AccountingEngine.recordStockMovementInTransaction(
      db,
      productId: secondProductId,
      movementType: 'purchase',
      quantityDelta: 5,
      unitCost: 20,
      referenceType: 'test_purchase',
      referenceId: 'multi-line-second',
      occurredAt: saleDate.subtract(const Duration(days: 1)),
    );

    final sale = <String, String>{
      'شماره فاکتور': 'TEST-MULTI-RETURN',
      'مبلغ کل': '500',
      'تخفیف': '0',
      'مبلغ مالیات': '0',
      'مبلغ دریافتی': '500',
      'بیعانه تخصیص‌یافته': '0',
      'روش پرداخت': 'نقدی',
      'ردیف‌های فاکتور': jsonEncode([
        {
          'kind': 'product',
          'product_id': firstProductId.toString(),
          'description': 'کالای ردیف اول',
          'quantity': '2',
          'line_total': '200',
        },
        {
          'kind': 'product',
          'product_id': secondProductId.toString(),
          'description': 'کالای ردیف دوم',
          'quantity': '3',
          'line_total': '300',
        },
      ]),
    };
    final saleId = await db.insert('records', {
      'category': 'sales',
      'data': jsonEncode(sale),
      'created_at': saleDate.toIso8601String(),
    });
    await DemoStore.postSaleInTransaction(
      db,
      recordId: saleId,
      item: sale,
      occurredAt: saleDate,
    );

    final returned = await DemoStore.addReturnInTransaction(
      db,
      originalCategory: 'sales',
      originalSourceId: saleId,
      quantity: 1,
      reason: 'برگشت فقط ردیف دوم',
      settleAsCash: true,
      invoiceLineIndex: 1,
      occurredAt: saleDate.add(const Duration(hours: 1)),
    );

    expect(returned['مبلغ برگشت'], '100');
    final firstProduct = (await db.query('products',
        columns: ['quantity'], where: 'id = ?', whereArgs: [firstProductId])).single;
    final secondProduct = (await db.query('products',
        columns: ['quantity'], where: 'id = ?', whereArgs: [secondProductId])).single;
    expect((firstProduct['quantity'] as num).toDouble(), 3);
    expect((secondProduct['quantity'] as num).toDouble(), 3);

    final movement = (await db.query('stock_movements',
        where: "reference_type = 'sale_return'")).single;
    expect(movement['product_id'], secondProductId);
    expect((movement['quantity_delta'] as num).toDouble(), 1);
    expect((movement['unit_cost'] as num).toDouble(), 20);
    expect((movement['total_cost'] as num).toDouble(), 20);

    final returnEntry = (await db.query('journal_entries',
        where: "source_type = 'document_return'")).single;
    final lines = await db.rawQuery(
      '''SELECT a.code, l.debit, l.credit
         FROM journal_lines l JOIN accounts a ON a.id = l.account_id
         WHERE l.entry_id = ?''',
      [returnEntry['id']],
    );
    double debitFor(String code) => lines
        .where((row) => row['code'] == code)
        .fold<double>(0, (sum, row) => sum + (row['debit'] as num).toDouble());
    double creditFor(String code) => lines
        .where((row) => row['code'] == code)
        .fold<double>(0, (sum, row) => sum + (row['credit'] as num).toDouble());
    expect(debitFor('4100'), 100);
    expect(creditFor('1000'), 100);
    expect(debitFor('1200'), 20);
    expect(creditFor('5000'), 20);
    expect(
      lines.fold<double>(0, (sum, row) => sum + (row['debit'] as num).toDouble()),
      closeTo(lines.fold<double>(0, (sum, row) => sum + (row['credit'] as num).toDouble()), 0.001),
    );
  });


  test('sales return and returned discount reduce net income and reverse only returned COGS', () async {
    final productId = await addProduct('کالای آزمون سود خالص');
    final saleDate = DateTime(2026, 5, 10, 10);
    await AccountingEngine.recordStockMovementInTransaction(
      db,
      productId: productId,
      movementType: 'purchase',
      quantityDelta: 5,
      unitCost: 40,
      referenceType: 'test_purchase',
      referenceId: 'profit-return-stock',
      occurredAt: saleDate.subtract(const Duration(days: 1)),
    );

    final sale = <String, String>{
      'شماره فاکتور': 'TEST-PROFIT-RETURN',
      'مبلغ کل': '200',
      'تخفیف': '20',
      'مبلغ مالیات': '0',
      'مبلغ دریافتی': '180',
      'بیعانه تخصیص‌یافته': '0',
      'روش پرداخت': 'نقدی',
      'ردیف‌های فاکتور': jsonEncode([
        {
          'kind': 'product',
          'product_id': productId.toString(),
          'description': 'کالای آزمون سود خالص',
          'quantity': '2',
          'line_total': '200',
        },
      ]),
    };
    final saleId = await db.insert('records', {
      'category': 'sales',
      'data': jsonEncode(sale),
      'created_at': saleDate.toIso8601String(),
    });
    await DemoStore.postSaleInTransaction(
      db,
      recordId: saleId,
      item: sale,
      occurredAt: saleDate,
    );

    await DemoStore.addReturnInTransaction(
      db,
      originalCategory: 'sales',
      originalSourceId: saleId,
      quantity: 1,
      reason: 'برگشت یک واحد برای آزمون سود',
      settleAsCash: true,
      occurredAt: saleDate.add(const Duration(hours: 1)),
    );

    final balances = await db.rawQuery('''
      SELECT a.code, a.type,
        COALESCE(SUM(l.debit), 0) AS debit,
        COALESCE(SUM(l.credit), 0) AS credit
      FROM journal_lines l
      JOIN journal_entries e ON e.id = l.entry_id
      JOIN accounts a ON a.id = l.account_id
      WHERE e.occurred_at >= ? AND e.occurred_at < ?
      GROUP BY a.code, a.type
    ''', [
      saleDate.toIso8601String(),
      saleDate.add(const Duration(days: 1)).toIso8601String(),
    ]);

    var netIncome = 0.0;
    var netCostOfGoods = 0.0;
    for (final row in balances) {
      final debit = (row['debit'] as num).toDouble();
      final credit = (row['credit'] as num).toDouble();
      if (row['type'] == 'income') netIncome += credit - debit;
      if (row['code'] == '5000') netCostOfGoods += debit - credit;
    }

    // 200 sales - 20 discount - 100 return + 10 discount reversal = 90.
    expect(netIncome, closeTo(90, 0.001));
    // 80 original COGS - 40 restored on return = 40.
    expect(netCostOfGoods, closeTo(40, 0.001));
    expect(netIncome - netCostOfGoods, closeTo(50, 0.001));
  });


  test('sales return after full customer payment creates customer credit instead of negative receivable', () async {
    final productId = await addProduct('کالای برگشت پس از تسویه');
    final customerId = await db.insert('customers', {
      'first_name': 'مشتری',
      'last_name': 'تسویه‌شده',
      'created_at': DateTime(2026, 1, 1).toIso8601String(),
    });
    final saleDate = DateTime(2026, 6, 10, 9);
    await AccountingEngine.recordStockMovementInTransaction(
      db,
      productId: productId,
      movementType: 'purchase',
      quantityDelta: 5,
      unitCost: 10,
      referenceType: 'test_purchase',
      referenceId: 'settled-return-stock',
      occurredAt: saleDate.subtract(const Duration(days: 1)),
    );

    final sale = <String, String>{
      'شماره فاکتور': 'TEST-SETTLED-RETURN',
      'مبلغ کل': '100',
      'تخفیف': '0',
      'مبلغ مالیات': '0',
      'مبلغ دریافتی': '0',
      'بیعانه تخصیص‌یافته': '0',
      'شناسه مشتری': customerId.toString(),
      'نام مشتری': 'مشتری تسویه‌شده',
      'روش پرداخت': 'نقدی',
      'ردیف‌های فاکتور': jsonEncode([
        {
          'kind': 'product',
          'product_id': productId.toString(),
          'description': 'کالای برگشت پس از تسویه',
          'quantity': '2',
          'line_total': '100',
        },
      ]),
    };
    final saleId = await db.insert('records', {
      'category': 'sales',
      'data': jsonEncode(sale),
      'created_at': saleDate.toIso8601String(),
    });
    await DemoStore.postSaleInTransaction(
      db,
      recordId: saleId,
      item: sale,
      occurredAt: saleDate,
    );

    final cashId = await AccountingEngine.accountId(db, '1000');
    final receivableId = await AccountingEngine.accountId(db, '1100');
    await AccountingEngine.postJournalInTransaction(
      db,
      entryNumber: 'TEST-SETTLE-SALE-RECEIVABLE',
      occurredAt: saleDate.add(const Duration(hours: 1)),
      description: 'دریافت کامل وجه فاکتور',
      sourceType: 'unit_test',
      sourceId: 'settle-sale-receivable',
      lines: [
        JournalLineInput(accountId: cashId, debit: 100),
        JournalLineInput(
          accountId: receivableId,
          credit: 100,
          partyType: 'customer',
          partyId: customerId,
        ),
      ],
    );

    await DemoStore.addReturnInTransaction(
      db,
      originalCategory: 'sales',
      originalSourceId: saleId,
      quantity: 1,
      reason: 'برگشت پس از تسویه کامل',
      settleAsCash: false,
      occurredAt: saleDate.add(const Duration(hours: 2)),
    );

    final arRows = await db.rawQuery(
      '''SELECT COALESCE(SUM(debit - credit), 0) AS balance
         FROM journal_lines
         WHERE account_id = ? AND party_type = 'customer' AND party_id = ?''',
      [receivableId, customerId],
    );
    expect(arRows.single['balance'], 0);

    final customerCreditId = await AccountingEngine.accountId(db, '2010');
    final creditRows = await db.rawQuery(
      '''SELECT COALESCE(SUM(credit - debit), 0) AS balance
         FROM journal_lines
         WHERE account_id = ? AND party_type = 'customer' AND party_id = ?''',
      [customerCreditId, customerId],
    );
    expect(creditRows.single['balance'], 50);

    final ledger = await AccountingEngine.partyLedger(
      db,
      partyType: 'customer',
      partyId: customerId,
      accountCodes: const ['1100', '2010'],
    );
    expect(ledger.last['running_balance'], -50);
  });

}
