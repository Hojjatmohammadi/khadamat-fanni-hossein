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

  test('sales invoice posts balanced accounting and reduces stock atomically', () async {
    final productId = await addProduct('کالای فروش آزمون');
    await AccountingEngine.recordStockMovement(
      db,
      productId: productId,
      movementType: 'opening_balance',
      quantityDelta: 10,
      unitCost: 50,
      occurredAt: DateTime(2026, 1, 1),
    );
    final customerId = await db.insert('customers', {
      'first_name': 'مشتری',
      'last_name': 'آزمون',
      'created_at': DateTime(2026, 1, 1).toIso8601String(),
    });
    final creditAccount = await AccountingEngine.accountId(db, '2010');
    final cashAccount = await AccountingEngine.accountId(db, '1000');
    await AccountingEngine.postJournal(
      db,
      entryNumber: 'CUSTOMER-CREDIT-1',
      occurredAt: DateTime(2026, 1, 2),
      description: 'بیعانه اولیه',
      sourceType: 'unit_test',
      sourceId: 'customer-credit-1',
      lines: [
        JournalLineInput(accountId: cashAccount, debit: 200),
        JournalLineInput(
          accountId: creditAccount,
          credit: 200,
          partyType: 'customer',
          partyId: customerId,
        ),
      ],
    );

    await db.transaction((txn) => AccountingEngine.postSaleInTransaction(
      txn,
      entryNumber: 'HOS-00001',
      sourceId: '501',
      occurredAt: DateTime(2026, 2, 1),
      gross: 1000,
      discount: 100,
      tax: 90,
      depositApplied: 200,
      received: 300,
      paymentMethod: 'نقدی',
      customerId: customerId,
      customerName: 'مشتری آزمون',
      productLines: [
        {'product_id': productId, 'quantity': 2.0},
      ],
    ));

    final quantityRows = await db.query(
      'products',
      columns: ['quantity'],
      where: 'id = ?',
      whereArgs: [productId],
    );
    expect((quantityRows.single['quantity'] as num).toDouble(), 8.0);

    final movementRows = await db.query(
      'stock_movements',
      where: "reference_type = 'sale' AND reference_id = ?",
      whereArgs: ['501'],
    );
    expect(movementRows, hasLength(1));
    expect((movementRows.single['total_cost'] as num).toDouble(), 100.0);

    final entryRows = await db.query(
      'journal_entries',
      where: "source_type = 'sale' AND source_id = ?",
      whereArgs: ['501'],
    );
    expect(entryRows, hasLength(1));
    final entryId = entryRows.single['id'] as int;
    final totals = await db.rawQuery(
      '''SELECT SUM(debit) AS debit_total, SUM(credit) AS credit_total
         FROM journal_lines WHERE entry_id = ?''',
      [entryId],
    );
    expect(
      (totals.single['debit_total'] as num).toDouble(),
      closeTo((totals.single['credit_total'] as num).toDouble(), 0.001),
    );
    final receivable = await db.rawQuery(
      '''SELECT SUM(debit - credit) AS balance FROM journal_lines
         WHERE entry_id = ? AND account_id = ?''',
      [entryId, await AccountingEngine.accountId(db, '1100')],
    );
    expect((receivable.single['balance'] as num).toDouble(), 490.0);
  });

  test('linked repair labor is not recognized or receivable twice on its invoice', () async {
    final customerId = await db.insert('customers', {
      'first_name': 'مشتری',
      'last_name': 'تعمیر',
      'created_at': DateTime(2026, 1, 1).toIso8601String(),
    });
    final repairSourceId = await db.insert('records', {
      'category': 'repairs',
      'data': '{}',
      'created_at': DateTime(2026, 1, 1).toIso8601String(),
    });
    await db.insert('repairs', {
      'customer_id': customerId,
      'customer_name_snapshot': 'مشتری تعمیر',
      'device_type': 'دستگاه آزمایش',
      'received_at': DateTime(2026, 1, 1).toIso8601String(),
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

    await db.transaction((txn) => AccountingEngine.postSaleInTransaction(
      txn,
      entryNumber: 'HOS-REPAIR-1',
      sourceId: '504',
      occurredAt: DateTime(2026, 2, 4),
      gross: 500,
      discount: 0,
      tax: 0,
      depositApplied: 0,
      received: 200,
      paymentMethod: 'نقدی',
      customerId: customerId,
      customerName: 'مشتری تعمیر',
      productLines: const [],
      linkedRepairSourceId: repairSourceId,
    ));

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

    final saleEntry = await db.query(
      'journal_entries',
      where: "source_type = 'sale' AND source_id = ?",
      whereArgs: ['504'],
    );
    expect(saleEntry, hasLength(1));
    final saleLines = await db.query(
      'journal_lines',
      where: 'entry_id = ? AND account_id = ?',
      whereArgs: [saleEntry.single['id'], repairIncomeId],
    );
    expect(saleLines, isEmpty);
  });

  test('sale with unpaid balance requires a linked customer record', () async {
    await expectLater(
      db.transaction((txn) => AccountingEngine.postSaleInTransaction(
        txn,
        entryNumber: 'HOS-UNLINKED',
        sourceId: '503',
        occurredAt: DateTime(2026, 2, 3),
        gross: 100,
        discount: 0,
        tax: 0,
        depositApplied: 0,
        received: 20,
        paymentMethod: 'نقدی',
        customerId: null,
        customerName: 'مشتری بدون پرونده',
        productLines: const [],
      )),
      throwsA(isA<StateError>()),
    );
    expect(
      await db.query(
        'journal_entries',
        where: "source_type = 'sale' AND source_id = ?",
        whereArgs: ['503'],
      ),
      isEmpty,
    );
  });

  test('failed sale stock deduction rolls back journal and inventory changes', () async {
    final productId = await addProduct('کالای ناموجود آزمون');
    await db.update(
      'products',
      {'quantity': 1.0, 'purchase_price': 25.0},
      where: 'id = ?',
      whereArgs: [productId],
    );
    await expectLater(
      db.transaction((txn) => AccountingEngine.postSaleInTransaction(
        txn,
        entryNumber: 'HOS-00002',
        sourceId: '502',
        occurredAt: DateTime(2026, 2, 2),
        gross: 100,
        discount: 0,
        tax: 0,
        depositApplied: 0,
        received: 0,
        paymentMethod: 'نقدی',
        customerId: null,
        customerName: 'مشتری آزمون',
        productLines: [
          {'product_id': productId, 'quantity': 2.0},
        ],
      )),
      throwsA(isA<StateError>()),
    );

    expect(
      await db.query(
        'journal_entries',
        where: "source_type = 'sale' AND source_id = ?",
        whereArgs: ['502'],
      ),
      isEmpty,
    );
    expect(
      await db.query(
        'stock_movements',
        where: "reference_type = 'sale' AND reference_id = ?",
        whereArgs: ['502'],
      ),
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
