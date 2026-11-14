import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:khadamat_fanni_hosein/accounting_repository.dart';
import 'package:khadamat_fanni_hosein/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late AppDatabase store;
  late AccountingRepository accounting;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('khadamat_db_test_');
    store = AppDatabase(databasePath: '\${tempDir.path}/test.db');
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
  });

  test('migrates version 1 records and opening product balances', () async {
    final legacyPath = '\${tempDir.path}/legacy.db';
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
    await migrated.close();
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

    final totals = await accounting.getTrialBalance();
    expect(
      totals.fold<int>(0, (sum, row) => sum + (row['total_debit'] as num).toInt()),
      50000,
    );
    expect(
      totals.fold<int>(0, (sum, row) => sum + (row['total_credit'] as num).toInt()),
      50000,
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
      'بهای تمام‌شده هر واحد': '200',
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
