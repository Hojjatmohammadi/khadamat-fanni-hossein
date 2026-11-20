import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:khadamat_fanni_hosein/accounting/accounting_engine.dart';
import 'package:khadamat_fanni_hosein/data/app_database_schema.dart';

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
}
