import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:khadamat_fanni_hosein/invoice/invoice_number_allocator.dart';

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
      CREATE TABLE invoice_archive (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_number TEXT NOT NULL UNIQUE,
        snapshot_json TEXT NOT NULL DEFAULT '{}',
        archived_at TEXT NOT NULL DEFAULT ''
      )
    ''');
    await InvoiceNumberAllocator.createTable(db);
  });

  tearDown(() async {
    if (db.isOpen) await db.close();
  });

  test('initialization continues after the highest issued invoice per prefix', () async {
    await db.insert('invoice_archive', {
      'invoice_number': 'HOS-00008',
    });
    await db.insert('invoice_archive', {
      'invoice_number': 'HOS-00041',
    });
    await db.insert('invoice_archive', {
      'invoice_number': 'SHOP-00120',
    });

    final next = await InvoiceNumberAllocator.initialize(
      db,
      prefix: 'HOS',
      preferredNextNumber: 3,
    );

    expect(next, 42);
    final otherPrefix = await InvoiceNumberAllocator.initialize(
      db,
      prefix: 'SHOP',
      preferredNextNumber: 1,
    );
    expect(otherPrefix, 121);
  });

  test('reserves sequential unique numbers for each prefix', () async {
    await InvoiceNumberAllocator.initialize(
      db,
      prefix: 'HOS',
      preferredNextNumber: 7,
    );

    final first = await db.transaction((txn) =>
        InvoiceNumberAllocator.reserve(
          txn,
          prefix: 'HOS',
          fallbackNextNumber: 1,
        ));
    final second = await db.transaction((txn) =>
        InvoiceNumberAllocator.reserve(
          txn,
          prefix: 'HOS',
          fallbackNextNumber: 1,
        ));
    final separate = await db.transaction((txn) =>
        InvoiceNumberAllocator.reserve(
          txn,
          prefix: 'SHOP',
          fallbackNextNumber: 1,
        ));

    expect(first.invoiceNumber, 'HOS-00007');
    expect(second.invoiceNumber, 'HOS-00008');
    expect(separate.invoiceNumber, 'SHOP-00001');
    expect(second.nextNumber, 9);
  });

  test('a rolled-back invoice transaction does not consume its number', () async {
    await InvoiceNumberAllocator.initialize(
      db,
      prefix: 'HOS',
      preferredNextNumber: 1,
    );

    await expectLater(
      db.transaction((txn) async {
        final reservation = await InvoiceNumberAllocator.reserve(
          txn,
          prefix: 'HOS',
          fallbackNextNumber: 1,
        );
        expect(reservation.invoiceNumber, 'HOS-00001');
        throw StateError('simulate invoice posting failure');
      }),
      throwsStateError,
    );

    final next = await db.transaction((txn) =>
        InvoiceNumberAllocator.reserve(
          txn,
          prefix: 'HOS',
          fallbackNextNumber: 1,
        ));
    expect(next.invoiceNumber, 'HOS-00001');
  });

  test('skips a previously archived number even if sequence metadata is stale', () async {
    await db.insert('invoice_archive', {
      'invoice_number': 'HOS-00001',
    });
    await db.insert('invoice_number_sequences', {
      'prefix': 'HOS',
      'next_number': 1,
      'updated_at': DateTime(2026, 1, 1).toIso8601String(),
    });

    final reservation = await db.transaction((txn) =>
        InvoiceNumberAllocator.reserve(
          txn,
          prefix: 'HOS',
          fallbackNextNumber: 1,
        ));

    expect(reservation.invoiceNumber, 'HOS-00002');
    expect(reservation.nextNumber, 3);
  });

  test('rejects invalid prefixes and sequence values', () async {
    expect(
      () => InvoiceNumberAllocator.normalizePrefix('  '),
      throwsArgumentError,
    );
    expect(
      () => InvoiceNumberAllocator.initialize(
        db,
        prefix: 'HOS',
        preferredNextNumber: 0,
      ),
      throwsArgumentError,
    );
  });
}
