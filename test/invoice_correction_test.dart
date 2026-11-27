import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:khadamat_fanni_hosein/accounting/accounting_engine.dart';
import 'package:khadamat_fanni_hosein/data/app_database_schema.dart';
import 'package:khadamat_fanni_hosein/invoice/invoice_number_allocator.dart';
import 'package:khadamat_fanni_hosein/main.dart' show DemoStore;

void main() {
  late Database db;
  late int originalSourceId;
  late Map<String, String> originalSnapshot;

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
    await db.execute('''
      CREATE TABLE invoice_archive (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        legacy_source_id INTEGER NOT NULL UNIQUE,
        invoice_number TEXT NOT NULL UNIQUE,
        snapshot_json TEXT NOT NULL,
        archived_at TEXT NOT NULL
      )
    ''');
    await InvoiceNumberAllocator.createTable(db);

    originalSnapshot = {
      'شماره فاکتور': 'HOS-00017',
      'نوع سند': 'فاکتور فروش',
      'نام مشتری': 'احمد رضایی',
      'نام مشتری در زمان صدور': 'احمد رضایی',
      'شماره تماس مشتری در زمان صدور': '09120000000',
      'نشانی مشتری در زمان صدور': 'خیابان قدیمی',
      'نام فروشگاه در زمان صدور': 'خدمات فنی حسین',
      'نام صاحب فروشگاه در زمان صدور': 'حسین',
      'تلفن فروشگاه در زمان صدور': '05130000000',
      'نشانی فروشگاه در زمان صدور': 'نشانی قدیمی فروشگاه',
      'کد پستی در زمان صدور': '1234567890',
      'مبلغ کل': '800000',
      'تخفیف': '50000',
      'مبلغ مالیات': '0',
      'مبلغ دریافتی': '300000',
      'بیعانه تخصیص‌یافته': '100000',
      'تعداد': '2',
      'ردیف‌های فاکتور': jsonEncode([
        {
          'kind': 'product',
          'description': 'قطعه پمپ',
          'unit': 'عدد',
          'quantity': '2',
          'unit_price': '400000',
          'line_total': '800000',
        },
      ]),
    };
    originalSourceId = await db.insert('records', {
      'category': 'sales',
      'data': jsonEncode(originalSnapshot),
      'created_at': DateTime(2026, 11, 1).toIso8601String(),
    });
    await db.insert('invoice_archive', {
      'legacy_source_id': originalSourceId,
      'invoice_number': originalSnapshot['شماره فاکتور'],
      'snapshot_json': jsonEncode(originalSnapshot),
      'archived_at': DateTime(2026, 11, 1).toIso8601String(),
    });
  });

  tearDown(() async {
    if (db.isOpen) await db.close();
  });

  test('creates a standalone correction snapshot without changing original financial data', () async {
    final correction = await db.transaction((txn) =>
        DemoStore.addInvoiceCorrectionInTransaction(
          txn,
          originalSourceId: originalSourceId,
          correctionPrefix: 'COR',
          reason: 'اصلاح اشتباه تایپی در نشانی مشتری',
          correctedFields: {
            'نشانی مشتری در زمان صدور': 'خیابان جدید',
          },
          issuedAt: DateTime(2026, 11, 27, 10, 30),
        ));

    expect(correction['شماره فاکتور'], 'COR-00001');
    expect(correction['نوع سند'], 'فاکتور اصلاحی');
    expect(correction['شماره فاکتور مرجع'], 'HOS-00017');
    expect(correction['علت اصلاح'], 'اصلاح اشتباه تایپی در نشانی مشتری');
    expect(correction['نشانی مشتری در زمان صدور'], 'خیابان جدید');

    // The original invoice remains byte-for-byte the same in the immutable archive.
    final originalArchive = (await db.query(
      'invoice_archive',
      where: 'legacy_source_id = ?',
      whereArgs: [originalSourceId],
    )).single;
    expect(originalArchive['snapshot_json'], jsonEncode(originalSnapshot));

    final correctionRows = await db.query('invoice_corrections');
    expect(correctionRows, hasLength(1));
    expect(correctionRows.single['original_source_id'], originalSourceId);
    expect(correctionRows.single['original_invoice_number'], 'HOS-00017');
    expect(correctionRows.single['reason'], 'اصلاح اشتباه تایپی در نشانی مشتری');

    final correctionArchive = await db.query(
      'invoice_archive',
      where: 'invoice_number = ?',
      whereArgs: ['COR-00001'],
    );
    expect(correctionArchive, hasLength(1));
    final archivedCorrection = jsonDecode(
      correctionArchive.single['snapshot_json'] as String,
    ) as Map<String, dynamic>;
    expect(archivedCorrection['مبلغ کل'], '800000');
    expect(archivedCorrection['تخفیف'], '50000');
    expect(archivedCorrection['مبلغ دریافتی'], '300000');
    expect(archivedCorrection['ردیف‌های فاکتور'], originalSnapshot['ردیف‌های فاکتور']);

    expect(await db.query('journal_entries'), isEmpty);
    expect(await db.query('stock_movements'), isEmpty);
  });

  test('rejects financial and inventory fields in a non-financial correction', () async {
    await expectLater(
      db.transaction((txn) => DemoStore.addInvoiceCorrectionInTransaction(
        txn,
        originalSourceId: originalSourceId,
        correctionPrefix: 'COR',
        reason: 'تلاش نامعتبر',
        correctedFields: {'مبلغ کل': '900000'},
      )),
      throwsArgumentError,
    );

    await expectLater(
      db.transaction((txn) => DemoStore.addInvoiceCorrectionInTransaction(
        txn,
        originalSourceId: originalSourceId,
        correctionPrefix: 'COR',
        reason: 'تلاش نامعتبر',
        correctedFields: {'ردیف‌های فاکتور': '[]'},
      )),
      throwsArgumentError,
    );

    expect(await db.query('invoice_corrections'), isEmpty);
    expect((await db.query('invoice_archive')), hasLength(1));
  });

  test('requires a reason and at least one actual change', () async {
    await expectLater(
      db.transaction((txn) => DemoStore.addInvoiceCorrectionInTransaction(
        txn,
        originalSourceId: originalSourceId,
        correctionPrefix: 'COR',
        reason: ' ',
        correctedFields: {'نشانی مشتری در زمان صدور': 'نشانی جدید'},
      )),
      throwsArgumentError,
    );

    await expectLater(
      db.transaction((txn) => DemoStore.addInvoiceCorrectionInTransaction(
        txn,
        originalSourceId: originalSourceId,
        correctionPrefix: 'COR',
        reason: 'بدون تغییر واقعی',
        correctedFields: {'نشانی مشتری در زمان صدور': 'خیابان قدیمی'},
      )),
      throwsStateError,
    );
    expect(await db.query('invoice_corrections'), isEmpty);
  });

  test('cannot correct another correction or a non-sales record', () async {
    final otherId = await db.insert('records', {
      'category': 'operations',
      'data': '{}',
      'created_at': DateTime.now().toIso8601String(),
    });

    await expectLater(
      db.transaction((txn) => DemoStore.addInvoiceCorrectionInTransaction(
        txn,
        originalSourceId: otherId,
        correctionPrefix: 'COR',
        reason: 'اصلاح',
        correctedFields: {'نشانی مشتری در زمان صدور': 'نشانی تازه'},
      )),
      throwsStateError,
    );
  });

  test('correction rows are immutable and cannot be deleted', () async {
    await db.transaction((txn) => DemoStore.addInvoiceCorrectionInTransaction(
      txn,
      originalSourceId: originalSourceId,
      correctionPrefix: 'COR',
      reason: 'اصلاح نام',
      correctedFields: {'نام مشتری در زمان صدور': 'احمد محمدی'},
    ));
    final row = (await db.query('invoice_corrections')).single;

    await expectLater(
      db.update(
        'invoice_corrections',
        {'reason': 'دستکاری'},
        where: 'id = ?',
        whereArgs: [row['id']],
      ),
      throwsException,
    );
    await expectLater(
      db.delete(
        'invoice_corrections',
        where: 'id = ?',
        whereArgs: [row['id']],
      ),
      throwsException,
    );
  });

  test('failed correction transaction does not consume its correction number', () async {
    await db.execute('''
      CREATE TRIGGER reject_invoice_correction
      BEFORE INSERT ON invoice_corrections
      BEGIN
        SELECT RAISE(ABORT, 'simulated correction insert failure');
      END
    ''');

    await expectLater(
      db.transaction((txn) => DemoStore.addInvoiceCorrectionInTransaction(
        txn,
        originalSourceId: originalSourceId,
        correctionPrefix: 'COR',
        reason: 'اصلاح نام',
        correctedFields: {'نام مشتری در زمان صدور': 'احمد محمدی'},
      )),
      throwsException,
    );

    await db.execute('DROP TRIGGER reject_invoice_correction');
    final correction = await db.transaction((txn) =>
        DemoStore.addInvoiceCorrectionInTransaction(
          txn,
          originalSourceId: originalSourceId,
          correctionPrefix: 'COR',
          reason: 'اصلاح نام',
          correctedFields: {'نام مشتری در زمان صدور': 'احمد محمدی'},
        ));

    expect(correction['شماره فاکتور'], 'COR-00001');
    expect(await db.query('invoice_corrections'), hasLength(1));
  });
}
