import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:khadamat_fanni_hosein/app_database.dart';
import 'package:khadamat_fanni_hosein/invoice_archive_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late AppDatabase database;
  late InvoiceArchiveRepository archives;
  late int documentId;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('khadamat_invoice_archive_');
    database = AppDatabase(databasePath: '${tempDir.path}/archive.db');
    archives = InvoiceArchiveRepository(database);
    final db = await database.database;
    documentId = await db.insert('business_documents', {
      'document_type': 'sale',
      'document_date': '2026-11-14',
      'document_number': 'SAL-0001',
      'counterparty_name': 'مشتری آزمایشی',
      'subtotal': 120000,
      'discount_amount': 0,
      'charges_amount': 0,
      'vat_amount': 0,
      'total_amount': 120000,
      'paid_amount': 120000,
      'source_document_id': null,
      'journal_entry_id': null,
      'idempotency_key': 'sale-archive-fixture',
      'payload_json': '{}',
      'created_at': DateTime.now().toIso8601String(),
    });
  });

  tearDown(() async {
    await database.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('archives exact invoice snapshot once and reads it back', () async {
    final snapshot = <String, Object?>{
      'shopName': 'خدمات فنی حسین',
      'ownerName': 'حجت محمدی',
      'phone': '09150000000',
      'stampImage': 'stamp-v1-base64',
      'signatureImage': 'signature-v1-base64',
      'items': [
        {'name': 'قطعه آزمایشی', 'quantity': 2, 'unitPrice': 60000},
      ],
    };

    final first = await archives.archive(
      businessDocumentId: documentId,
      snapshot: snapshot,
      idempotencyKey: 'archive-sale-1',
    );
    final repeated = await archives.archive(
      businessDocumentId: documentId,
      snapshot: snapshot,
      idempotencyKey: 'archive-sale-1',
    );

    expect(repeated, first);
    final saved = await archives.getArchive(documentId);
    expect(saved, isNotNull);
    expect(saved!['snapshot'], snapshot);
    expect(saved['render_version'], 1);
    expect(await archives.getArchives(), hasLength(1));
  });

  test('rejects a second different snapshot for an already archived invoice', () async {
    await archives.archive(
      businessDocumentId: documentId,
      snapshot: {'shopName': 'نام زمان صدور'},
      idempotencyKey: 'archive-original',
    );

    await expectLater(
      archives.archive(
        businessDocumentId: documentId,
        snapshot: {'shopName': 'نام جدید'},
        idempotencyKey: 'archive-correction',
      ),
      throwsStateError,
    );
    expect(await archives.getArchives(), hasLength(1));
  });

  test('database prevents archive update and deletion', () async {
    await archives.archive(
      businessDocumentId: documentId,
      snapshot: {'shopName': 'خدمات فنی حسین'},
      idempotencyKey: 'archive-immutable',
    );
    final db = await database.database;

    await expectLater(
      db.update('invoice_archives', {'snapshot_json': '{}'}),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      db.delete('invoice_archives'),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('requires an existing business document and a non-empty snapshot', () async {
    await expectLater(
      archives.archive(
        businessDocumentId: 999999,
        snapshot: {'shopName': 'مغازه'},
        idempotencyKey: 'archive-missing-document',
      ),
      throwsStateError,
    );
    await expectLater(
      archives.archive(
        businessDocumentId: documentId,
        snapshot: const {},
        idempotencyKey: 'archive-empty-snapshot',
      ),
      throwsArgumentError,
    );
  });

  test('schema version 10 upgrades by creating invoice archive storage', () async {
    final path = '${tempDir.path}/legacy-v10.db';
    final legacy = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 10,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE business_documents (
              id INTEGER PRIMARY KEY AUTOINCREMENT
            )
          ''');
        },
      ),
    );
    await legacy.close();

    final upgraded = AppDatabase(databasePath: path);
    final db = await upgraded.database;
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'invoice_archives'",
    );
    expect(tables, hasLength(1));
    await upgraded.close();
  });
}
