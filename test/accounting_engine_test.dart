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
