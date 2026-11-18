import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:khadamat_fanni_hosein/accounting_repository.dart';
import 'package:khadamat_fanni_hosein/app_database.dart';
import 'package:khadamat_fanni_hosein/trade_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late AppDatabase store;
  late AccountingRepository accounting;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('khadamat_db_test_');
    store = AppDatabase(databasePath: '${tempDir.path}/test.db');
    accounting = AccountingRepository(store);
    await store.database;
  });

  tearDown(() async {
    await store.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('stores records and tracks opening product stock', () async {
    await store.insert('customers', {
      'نام مشتری': 'آزمون',
      'شماره تماس': '09120000000',
    });

    final customerRows = await store.getAll('customers');
    expect(customerRows, hasLength(1));
    expect(customerRows.single['نام مشتری'], 'آزمون');
    expect(customerRows.single['__database_id'], isNotEmpty);
    expect(await store.getAll('repairs'), isEmpty);

    final productId = await store.insert('products', {
      'نام کالا': 'خازن آزمایشی',
      'موجودی': '12',
      'بهای تمام‌شده هر واحد': '350',
    });
    expect(await store.getStockOnHand(productId), 12);
    final db = await store.database;
    final openingEntries = await db.query('journal_entries');
    expect(openingEntries, hasLength(1));
    final openingLines = await db.query(
      'journal_lines',
      where: 'journal_entry_id = ?',
      whereArgs: [openingEntries.single['id']],
      orderBy: 'line_no ASC',
    );
    expect(openingLines[0]['account_code'], '1200');
    expect(openingLines[0]['debit'], 4200);
    expect(openingLines[1]['account_code'], '3000');
    expect(openingLines[1]['credit'], 4200);
  });

  test('migrates version 1 records and opening product balances', () async {
    final legacyPath = '${tempDir.path}/legacy.db';
    final legacyDb = await databaseFactory.openDatabase(
      legacyPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE records (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              category TEXT NOT NULL,
              data TEXT NOT NULL,
              created_at TEXT NOT NULL
            )
          ''');
          await db.insert('records', {
            'id': 17,
            'category': 'customers',
            'data': '{"نام مشتری":"مشتری قدیمی"}',
            'created_at': '2026-01-01T10:00:00.000',
          });
          await db.insert('records', {
            'id': 18,
            'category': 'unknown_legacy',
            'data': '{"value":"preserve"}',
            'created_at': '2026-01-02T10:00:00.000',
          });
          await db.insert('records', {
            'id': 19,
            'category': 'products',
            'data': '{"نام کالا":"کالای قدیمی","موجودی":"4","بهای تمام‌شده هر واحد":"25"}',
            'created_at': '2026-01-03T10:00:00.000',
          });
        },
      ),
    );
    await legacyDb.close();

    final migrated = AppDatabase(databasePath: legacyPath);
    final rows = await migrated.getAll('customers');
    expect(rows, hasLength(1));
    expect(rows.single['نام مشتری'], 'مشتری قدیمی');

    final db = await migrated.database;
    final movedCustomer = await db.query('customers');
    expect(movedCustomer.single['id'], 17);
    final preserved = await db.query('legacy_records');
    expect(preserved, hasLength(1));
    expect(preserved.single['category'], 'unknown_legacy');

    final migratedProducts = await db.query('products');
    expect(migratedProducts.single['id'], 19);
    final stock = await migrated.getStockOnHand(19);
    expect(stock, 4);
    final openingEntries = await db.query('journal_entries');
    expect(openingEntries, hasLength(1));
    final openingLines = await db.query('journal_lines');
    expect(openingLines, hasLength(2));
    expect(openingLines[0]['debit'], 100);
    expect(openingLines[1]['credit'], 100);
    await migrated.close();
  });

  test('version 13 migration creates multi-role links for existing contacts', () async {
    final legacyPath = '${tempDir.path}/legacy-v13.db';
    final legacyDb = await databaseFactory.openDatabase(
      legacyPath,
      options: OpenDatabaseOptions(
        version: 13,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE parties (
              id TEXT PRIMARY KEY,
              party_type TEXT NOT NULL,
              display_name TEXT NOT NULL,
              normalized_name TEXT NOT NULL,
              phone TEXT,
              address TEXT,
              notes TEXT,
              source_category TEXT,
              source_id TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
          await db.insert('parties', {
            'id': 'legacy-customer-1',
            'party_type': 'customer',
            'display_name': 'مشتری قدیمی',
            'normalized_name': 'مشتری قدیمی',
            'created_at': '2026-01-01T00:00:00.000',
            'updated_at': '2026-01-01T00:00:00.000',
          });
          await db.insert('parties', {
            'id': 'legacy-supplier-1',
            'party_type': 'supplier',
            'display_name': 'فروشنده قدیمی',
            'normalized_name': 'فروشنده قدیمی',
            'created_at': '2026-01-02T00:00:00.000',
            'updated_at': '2026-01-02T00:00:00.000',
          });
        },
      ),
    );
    await legacyDb.close();

    final migrated = AppDatabase(databasePath: legacyPath);
    final db = await migrated.database;
    final roles = await db.query(
      'party_roles',
      orderBy: 'party_id ASC',
    );

    expect(roles, hasLength(2));
    expect(
      roles.map((row) => '${row['party_id']}:${row['role']}'),
      containsAll([
        'legacy-customer-1:customer',
        'legacy-supplier-1:supplier',
      ]),
    );
    await migrated.close();
  });

  test('version 14 upgrade preserves documents and installs immutable payment allocations', () async {
    final legacyPath = '\${tempDir.path}/legacy-v14.db';
    final legacyDb = await databaseFactory.openDatabase(
      legacyPath,
      options: OpenDatabaseOptions(
        version: 14,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE business_documents (
              id INTEGER PRIMARY KEY,
              document_type TEXT NOT NULL
            )
          ''');
          await db.insert('business_documents', {
            'id': 201,
            'document_type': 'payment',
          });
          await db.insert('business_documents', {
            'id': 202,
            'document_type': 'sale',
          });
        },
      ),
    );
    await legacyDb.close();

    final upgraded = AppDatabase(databasePath: legacyPath);
    final db = await upgraded.database;

    final documents = await db.query(
      'business_documents',
      orderBy: 'id ASC',
    );
    expect(
      documents.map((row) => row['id']),
      [201, 202],
    );

    final allocationTables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'invoice_payment_allocations'",
    );
    expect(allocationTables, hasLength(1));

    final allocationIndexes = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'idx_payment_allocations_%'",
    );
    expect(
      allocationIndexes.map((row) => row['name']),
      containsAll([
        'idx_payment_allocations_invoice',
        'idx_payment_allocations_payment',
      ]),
    );

    final allocationId = await db.insert('invoice_payment_allocations', {
      'payment_document_id': 201,
      'invoice_document_id': 202,
      'amount': 1250,
      'created_at': '2026-11-18T12:00:00.000',
    });
    final allocations = await db.query(
      'invoice_payment_allocations',
      where: 'id = ?',
      whereArgs: [allocationId],
    );
    expect(allocations.single['amount'], 1250);

    await expectLater(
      db.update(
        'invoice_payment_allocations',
        {'amount': 1200},
        where: 'id = ?',
        whereArgs: [allocationId],
      ),
      throwsA(isA<Exception>()),
    );
    await expectLater(
      db.delete(
        'invoice_payment_allocations',
        where: 'id = ?',
        whereArgs: [allocationId],
      ),
      throwsA(isA<Exception>()),
    );

    final unchanged = await db.query(
      'invoice_payment_allocations',
      where: 'id = ?',
      whereArgs: [allocationId],
    );
    expect(unchanged.single['amount'], 1250);

    await upgraded.close();
  });

  test('version 4 migration normalizes whitespace in migrated party names', () async {
    final legacyPath = '${tempDir.path}/legacy-v4.db';
    final legacyDb = await databaseFactory.openDatabase(
      legacyPath,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE customers (
              id INTEGER PRIMARY KEY,
              data_json TEXT NOT NULL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE business_documents (
              id INTEGER PRIMARY KEY,
              document_type TEXT NOT NULL,
              counterparty_id TEXT,
              counterparty_name TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE accounts (
              code TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              account_type TEXT NOT NULL,
              normal_side TEXT NOT NULL,
              is_system INTEGER NOT NULL DEFAULT 1
            )
          ''');
          await db.insert('customers', {
            'id': 7,
            'data_json': '{"نام مشتری":"  علی   محمدی  "}',
            'created_at': '2026-01-01T00:00:00.000',
            'updated_at': '2026-01-01T00:00:00.000',
          });
          await db.insert('business_documents', {
            'id': 12,
            'document_type': 'purchase',
            'counterparty_id': 'supplier:legacy-12',
            'counterparty_name': '  فروشنده   قدیمی  ',
          });
        },
      ),
    );
    await legacyDb.close();

    final migrated = AppDatabase(databasePath: legacyPath);
    final db = await migrated.database;
    final customer = await db.query(
      'parties',
      where: 'id = ?',
      whereArgs: ['customer:7'],
      limit: 1,
    );
    final supplier = await db.query(
      'parties',
      where: 'id = ?',
      whereArgs: ['supplier:legacy-12'],
      limit: 1,
    );

    expect(customer.single['normalized_name'], 'علی محمدی');
    expect(supplier.single['normalized_name'], 'فروشنده قدیمی');
    await migrated.close();
  });

  test('product list reads current stock from movements without requiring a metadata edit', () async {
    final productId = await store.insert('products', {
      'نام کالا': 'موجودی پویا',
      'موجودی': '10',
      'بهای تمام‌شده هر واحد': '1000',
    });

    await accounting.recordStockMovement(
      StockMovementDraft(
        productId: productId,
        movementType: 'sale',
        quantityDelta: -3,
        unitCost: 1000,
        occurredAt: '2026-11-14T12:00:00.000',
        idempotencyKey: 'live-stock-list-sale-$productId',
        referenceType: 'test',
        referenceId: 'sale-live-stock',
      ),
    );

    final listedProduct = (await store.getAll('products')).single;
    expect(listedProduct['موجودی'], '7.0');
    expect(await store.getStockOnHand(productId), 7);
  });

  test('editing product details preserves live stock and immutable accounting history', () async {
    final productId = await store.insert('products', {
      'نام کالا': 'خازن قدیمی',
      'موجودی': '10',
      'بهای تمام‌شده هر واحد': '1000',
      'قیمت فروش': '1500',
    });

    await accounting.recordStockMovement(
      StockMovementDraft(
        productId: productId,
        movementType: 'sale',
        quantityDelta: -2,
        unitCost: 1000,
        occurredAt: '2026-11-14T12:00:00.000',
        idempotencyKey: 'metadata-edit-sale-$productId',
        referenceType: 'test',
        referenceId: 'sale-1',
        journalEntry: JournalEntryDraft(
          entryDate: '2026-11-14',
          description: 'ثبت خروج آزمایشی کالا',
          idempotencyKey: 'metadata-edit-journal-$productId',
          lines: const [
            JournalLineDraft(accountCode: '5000', debit: 2000),
            JournalLineDraft(accountCode: '1200', credit: 2000),
          ],
        ),
      ),
    );

    final db = await store.database;
    final beforeEntries = await db.query('journal_entries');
    final beforeMovements = await db.query('inventory_movements');
    final beforeLines = await db.query('journal_lines');

    await store.updateRecord('products', productId, {
      'نام کالا': 'خازن جدید',
      'گروه اصلی': 'الکترونیک',
      'زیرگروه': 'خازن‌ها',
      'موجودی': '999',
      'بهای تمام‌شده هر واحد': '1200',
      'قیمت فروش': '1800',
    });

    final product = (await store.getAll('products')).single;
    expect(product['نام کالا'], 'خازن جدید');
    expect(product['موجودی'], '8.0');
    expect(await store.getStockOnHand(productId), 8);

    expect(await db.query('journal_entries'), beforeEntries);
    expect(await db.query('inventory_movements'), beforeMovements);
    expect(await db.query('journal_lines'), beforeLines);
  });

  test('physical stock count posts valued surplus and shortage atomically', () async {
    final productId = await store.insert('products', {
      'نام کالا': 'قطعه انبارگردانی',
      'موجودی': '10',
      'بهای تمام‌شده هر واحد': '1000',
    });

    final increaseId = await accounting.recordStockAdjustment(
      productId: productId,
      countedQuantity: 12,
      fallbackUnitCost: 700,
      occurredAt: '2026-11-14T09:00:00.000',
      reason: 'شمارش اولیه',
      idempotencyKey: 'stock-count-increase-$productId',
    );
    expect(
      await accounting.recordStockAdjustment(
        productId: productId,
        countedQuantity: 12,
        fallbackUnitCost: 700,
        occurredAt: '2026-11-14T09:00:00.000',
        reason: 'شمارش اولیه',
        idempotencyKey: 'stock-count-increase-$productId',
      ),
      increaseId,
    );
    expect(await store.getStockOnHand(productId), 12);

    final db = await store.database;
    final surplus = await db.query(
      'inventory_movements',
      where: 'id = ?',
      whereArgs: [increaseId],
    );
    expect(surplus.single['quantity_delta'], 2);
    expect(surplus.single['unit_cost'], 1000);
    expect(surplus.single['total_cost'], 2000);

    final decreaseId = await accounting.recordStockAdjustment(
      productId: productId,
      countedQuantity: 9,
      fallbackUnitCost: 700,
      occurredAt: '2026-11-14T10:00:00.000',
      reason: 'ثبت کسری شمارش',
      idempotencyKey: 'stock-count-decrease-$productId',
    );
    expect(await store.getStockOnHand(productId), 9);

    final shortage = await db.query(
      'inventory_movements',
      where: 'id = ?',
      whereArgs: [decreaseId],
    );
    expect(shortage.single['quantity_delta'], -3);
    expect(shortage.single['unit_cost'], 1000);
    expect(shortage.single['total_cost'], 3000);

    final surplusAccount = await db.query(
      'journal_lines',
      where: 'account_code = ?',
      whereArgs: ['4055'],
    );
    final shortageAccount = await db.query(
      'journal_lines',
      where: 'account_code = ?',
      whereArgs: ['5200'],
    );
    expect(surplusAccount.fold<int>(
      0,
      (sum, line) => sum + (line['credit'] as num).toInt(),
    ), 2000);
    expect(shortageAccount.fold<int>(
      0,
      (sum, line) => sum + (line['debit'] as num).toInt(),
    ), 3000);

    final trialBalance = await accounting.getTrialBalance();
    expect(
      trialBalance.fold<int>(
        0,
        (sum, row) => sum + (row['total_debit'] as num).toInt(),
      ),
      trialBalance.fold<int>(
        0,
        (sum, row) => sum + (row['total_credit'] as num).toInt(),
      ),
    );

    await expectLater(
      accounting.recordStockAdjustment(
        productId: productId,
        countedQuantity: 8,
        fallbackUnitCost: 700,
        occurredAt: '2026-11-14T10:00:00.000',
        reason: 'تغییر غیرمجاز',
        idempotencyKey: 'stock-count-increase-$productId',
      ),
      throwsStateError,
    );
  });

  test('schema v9 upgrade seeds stock count surplus and shortage accounts', () async {
    final legacyPath = '${tempDir.path}/legacy_v9.db';
    final legacyDb = await databaseFactory.openDatabase(
      legacyPath,
      options: OpenDatabaseOptions(
        version: 9,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE accounts (
              code TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              account_type TEXT NOT NULL,
              normal_side TEXT NOT NULL,
              is_system INTEGER NOT NULL DEFAULT 1
            )
          ''');
          await db.insert('accounts', {
            'code': '1000',
            'name': 'صندوق',
            'account_type': 'asset',
            'normal_side': 'debit',
            'is_system': 1,
          });
        },
      ),
    );
    await legacyDb.close();

    final upgraded = AppDatabase(databasePath: legacyPath);
    final db = await upgraded.database;
    final accounts = await db.query(
      'accounts',
      where: 'code IN (?, ?)',
      whereArgs: ['4055', '5200'],
      orderBy: 'code ASC',
    );

    expect(accounts.map((row) => row['code']), ['4055', '5200']);
    expect(accounts.first['account_type'], 'income');
    expect(accounts.last['account_type'], 'expense');
    expect(await db.rawQuery('PRAGMA user_version'), isNotEmpty);
    await upgraded.close();
  });

  test('rejects unknown categories and empty records', () async {
    await expectLater(
      store.insert('unknown', {'عنوان': 'نمونه'}),
      throwsArgumentError,
    );
    await expectLater(
      store.insert('products', {'نام کالا': '  '}),
      throwsArgumentError,
    );
  });

  test('posts only balanced double-entry journal entries', () async {
    final draft = JournalEntryDraft(
      entryDate: '2026-11-14',
      description: 'ثبت دریافت وجه آزمایشی',
      idempotencyKey: 'journal-cash-test-1',
      lines: const [
        JournalLineDraft(accountCode: '1000', debit: 125000),
        JournalLineDraft(accountCode: '4000', credit: 125000),
      ],
    );

    final firstId = await accounting.postJournalEntry(draft);
    final repeatedId = await accounting.postJournalEntry(draft);
    expect(repeatedId, firstId);

    final db = await store.database;
    expect(await db.query('journal_entries'), hasLength(1));
    expect(await db.query('journal_lines'), hasLength(2));

    final trialBalance = await accounting.getTrialBalance();
    final debitTotal = trialBalance.fold<int>(
      0,
      (sum, row) => sum + (row['total_debit'] as num).toInt(),
    );
    final creditTotal = trialBalance.fold<int>(
      0,
      (sum, row) => sum + (row['total_credit'] as num).toInt(),
    );
    expect(debitTotal, 125000);
    expect(creditTotal, 125000);
  });

  test('rejects unbalanced or invalid journal entries without saving them', () async {
    final unbalanced = JournalEntryDraft(
      entryDate: '2026-11-14',
      description: 'سند نامتوازن',
      idempotencyKey: 'journal-unbalanced-1',
      lines: const [
        JournalLineDraft(accountCode: '1000', debit: 1000),
        JournalLineDraft(accountCode: '4000', credit: 900),
      ],
    );
    await expectLater(
      accounting.postJournalEntry(unbalanced),
      throwsStateError,
    );

    final bothSides = JournalEntryDraft(
      entryDate: '2026-11-14',
      description: 'سطر نامعتبر',
      idempotencyKey: 'journal-invalid-line-1',
      lines: const [
        JournalLineDraft(accountCode: '1000', debit: 1000, credit: 1000),
        JournalLineDraft(accountCode: '4000', credit: 1000),
      ],
    );
    await expectLater(
      accounting.postJournalEntry(bothSides),
      throwsArgumentError,
    );

    final db = await store.database;
    expect(await db.query('journal_entries'), isEmpty);
  });

  test('reverses a posted journal using a separate opposite entry', () async {
    final originalId = await accounting.postJournalEntry(
      JournalEntryDraft(
        entryDate: '2026-11-14',
        description: 'سند اصلی',
        idempotencyKey: 'journal-to-reverse-1',
        lines: const [
          JournalLineDraft(accountCode: '1000', debit: 50000),
          JournalLineDraft(accountCode: '4000', credit: 50000),
        ],
      ),
    );

    final reversalId = await accounting.reverseJournalEntry(
      journalEntryId: originalId,
      reversalDate: '2026-11-15',
      reason: 'اصلاح ثبت آزمایشی',
      idempotencyKey: 'journal-reversal-1',
    );
    expect(reversalId, isNot(originalId));

    final repeatedReversalId = await accounting.reverseJournalEntry(
      journalEntryId: originalId,
      reversalDate: '2026-11-15',
      reason: 'تلاش مجدد',
      idempotencyKey: 'journal-reversal-retry',
    );
    expect(repeatedReversalId, reversalId);

    final db = await store.database;
    final entries = await db.query('journal_entries');
    expect(entries, hasLength(2));
    final originalLines = await db.query(
      'journal_lines',
      where: 'journal_entry_id = ?',
      whereArgs: [originalId],
      orderBy: 'line_no ASC',
    );
    final reversalLines = await db.query(
      'journal_lines',
      where: 'journal_entry_id = ?',
      whereArgs: [reversalId],
      orderBy: 'line_no ASC',
    );
    expect(originalLines[0]['debit'], 50000);
    expect(reversalLines[0]['credit'], 50000);
    expect(reversalLines[1]['debit'], 50000);
    await expectLater(
      db.update(
        'journal_entries',
        {'description': 'تغییر غیرمجاز'},
        where: 'id = ?',
        whereArgs: [originalId],
      ),
      throwsA(isA<DatabaseException>()),
    );

    final totals = await accounting.getTrialBalance();
    expect(
      totals.fold<int>(0, (sum, row) => sum + (row['total_debit'] as num).toInt()),
      100000,
    );
    expect(
      totals.fold<int>(0, (sum, row) => sum + (row['total_credit'] as num).toInt()),
      100000,
    );
    expect(
      totals.every((row) => row['balance_debit_minus_credit'] == 0),
      isTrue,
    );
  });

  test('records stock in and out atomically and prevents duplicate or negative stock', () async {
    final productId = await store.insert('products', {
      'نام کالا': 'قطعه گردش انبار',
      'موجودی': '10',
      'بهای تمام‌شده هر واحد': '1000',
    });
    expect(await accounting.getStockOnHand(productId), 10);

    final movement = StockMovementDraft(
      productId: productId,
      movementType: 'sale',
      quantityDelta: -3,
      unitCost: 1000,
      occurredAt: '2026-11-14T10:00:00.000',
      idempotencyKey: 'stock-sale-product-$productId-1',
      referenceType: 'sale',
      referenceId: 'sale-1',
      journalEntry: JournalEntryDraft(
        entryDate: '2026-11-14',
        description: 'ثبت بهای تمام‌شده فروش',
        idempotencyKey: 'journal-stock-sale-product-$productId-1',
        lines: const [
          JournalLineDraft(accountCode: '5000', debit: 3000),
          JournalLineDraft(accountCode: '1200', credit: 3000),
        ],
      ),
    );

    final movementId = await accounting.recordStockMovement(movement);
    expect(await accounting.recordStockMovement(movement), movementId);
    expect(await accounting.getStockOnHand(productId), 7);

    final db = await store.database;
    expect(
      await db.query('inventory_movements', where: 'product_id = ?', whereArgs: [productId]),
      hasLength(2),
    );
    await expectLater(
      db.delete(
        'inventory_movements',
        where: 'id = ?',
        whereArgs: [movementId],
      ),
      throwsA(isA<DatabaseException>()),
    );

    await expectLater(
      accounting.recordStockMovement(
        StockMovementDraft(
          productId: productId,
          movementType: 'sale',
          quantityDelta: -20,
          unitCost: 1000,
          occurredAt: '2026-11-14T11:00:00.000',
          idempotencyKey: 'stock-overdraw-$productId',
        ),
      ),
      throwsStateError,
    );
    expect(await accounting.getStockOnHand(productId), 7);
  });

  test('rolls back stock movement when its linked journal entry is invalid', () async {
    final productId = await store.insert('products', {
      'نام کالا': 'قطعه تراکنش اتمی',
      'موجودی': '5',
      'بهای تمام‌شده هر واحد': '0',
    });

    await expectLater(
      accounting.recordStockMovement(
        StockMovementDraft(
          productId: productId,
          movementType: 'sale',
          quantityDelta: -1,
          unitCost: 200,
          occurredAt: '2026-11-14T12:00:00.000',
          idempotencyKey: 'stock-atomic-failure-$productId',
          journalEntry: JournalEntryDraft(
            entryDate: '2026-11-14',
            description: 'سند نامتوازن متصل به گردش',
            idempotencyKey: 'journal-atomic-failure-$productId',
            lines: const [
              JournalLineDraft(accountCode: '5000', debit: 200),
              JournalLineDraft(accountCode: '1200', credit: 150),
            ],
          ),
        ),
      ),
      throwsStateError,
    );

    expect(await accounting.getStockOnHand(productId), 5);
    final db = await store.database;
    expect(
      await db.query(
        'inventory_movements',
        where: 'product_id = ?',
        whereArgs: [productId],
      ),
      hasLength(1),
    );
    expect(await db.query('journal_entries'), isEmpty);
  });

  test('enforces only essential fields at the database boundary', () async {
    await expectLater(
      store.insert('products', {'نام کالا': 'کالای بدون موجودی'}),
      throwsArgumentError,
    );
    await expectLater(
      store.insert('products', {'نام کالا': 'کالا', 'موجودی': '-1'}),
      throwsArgumentError,
    );
    await expectLater(
      store.insert('repairs', {'نام مشتری': 'مشتری'}),
      throwsArgumentError,
    );

    final customerId = await store.insert('customers', {
      'نام مشتری': 'مشتری با مشخصات اختیاری خالی',
      'شماره تماس': '',
      'آدرس': '',
    });
    expect(customerId, greaterThan(0));
    final productId = await store.insert('products', {
      'نام کالا': 'کالای دارای موجودی صفر',
      'موجودی': '۰',
      'گروه اصلی': '',
      'قیمت فروش': '',
    });
    expect(productId, greaterThan(0));
  });

  test('deletes only unreferenced records and protects product stock history', () async {
    final emptyProductId = await store.insert('products', {
      'نام کالا': 'کالای بدون گردش',
      'موجودی': '0',
    });
    await store.deleteRecord('products', emptyProductId);
    expect(
      await (await store.database).query(
        'products',
        where: 'id = ?',
        whereArgs: [emptyProductId],
      ),
      isEmpty,
    );

    final stockedProductId = await store.insert('products', {
      'نام کالا': 'کالای دارای سابقه',
      'موجودی': '3',
      'بهای تمام‌شده هر واحد': '100',
    });
    await expectLater(
      store.deleteRecord('products', stockedProductId),
      throwsStateError,
    );
    expect(await store.getStockOnHand(stockedProductId), 3);
  });

  test('protects repairs with stock consumption even when the part cost is zero', () async {
    final repairWithoutHistory = await store.insert('repairs', {
      'نام مشتری': 'مشتری بدون سابقه',
      'نوع دستگاه': 'دریل',
    });
    await store.deleteRecord('repairs', repairWithoutHistory);

    final repairWithHistory = await store.insert('repairs', {
      'نام مشتری': 'مشتری دارای مصرف قطعه',
      'نوع دستگاه': 'فرز',
    });
    final productId = await store.insert('products', {
      'نام کالا': 'قطعه بدون بهای ثبت‌شده',
      'موجودی': '3',
      'بهای تمام‌شده هر واحد': '0',
    });
    final trades = TradeRepository(store);
    await trades.recordRepairConsumption(
      documentDate: '2026-11-17',
      repairId: repairWithHistory.toString(),
      customerName: 'مشتری دارای مصرف قطعه',
      parts: [
        TradeLineDraft(productId: productId, quantity: 1, unitPrice: 0),
      ],
      idempotencyKey: 'zero-cost-repair-consumption-$repairWithHistory',
    );

    expect(await store.getStockOnHand(productId), 2);
    await expectLater(
      store.deleteRecord('repairs', repairWithHistory),
      throwsStateError,
    );
    expect(
      await (await store.database).query(
        'repairs',
        where: 'id = ?',
        whereArgs: [repairWithHistory],
      ),
      hasLength(1),
    );
  });

  test('does not delete customer records still linked to the contacts ledger', () async {
    final customerId = await store.insert('customers', {
      'نام مشتری': 'مشتری دارای پرونده',
    });
    final db = await store.database;
    await db.insert('parties', {
      'id': 'customer:$customerId',
      'party_type': 'customer',
      'display_name': 'مشتری دارای پرونده',
      'normalized_name': 'مشتری دارای پرونده',
      'source_category': 'customers',
      'source_id': customerId.toString(),
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });

    await expectLater(
      store.deleteRecord('customers', customerId),
      throwsStateError,
    );
    expect(
      await db.query('customers', where: 'id = ?', whereArgs: [customerId]),
      hasLength(1),
    );
  });

  test('rejects reusing an idempotency key for different journal data', () async {
    await accounting.postJournalEntry(
      JournalEntryDraft(
        entryDate: '2026-11-14',
        description: 'ثبت اول',
        idempotencyKey: 'same-key',
        lines: const [
          JournalLineDraft(accountCode: '1000', debit: 100),
          JournalLineDraft(accountCode: '4000', credit: 100),
        ],
      ),
    );

    await expectLater(
      accounting.postJournalEntry(
        JournalEntryDraft(
          entryDate: '2026-11-14',
          description: 'ثبت متفاوت',
          idempotencyKey: 'same-key',
          lines: const [
            JournalLineDraft(accountCode: '1000', debit: 200),
            JournalLineDraft(accountCode: '4000', credit: 200),
          ],
        ),
      ),
      throwsStateError,
    );
    final db = await store.database;
    expect(await db.query('journal_entries'), hasLength(1));
  });
}
