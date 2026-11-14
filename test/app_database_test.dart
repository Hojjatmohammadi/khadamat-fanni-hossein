import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:khadamat_fanni_hosein/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late AppDatabase store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('khadamat_db_test_');
    store = AppDatabase(databasePath: '${tempDir.path}/test.db');
  });

  tearDown(() async {
    await store.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('stores and reloads records in the correct domain table', () async {
    await store.insert('customers', {
      'نام مشتری': 'آزمون',
      'شماره تماس': '09120000000',
    });

    final rows = await store.getAll('customers');
    expect(rows, hasLength(1));
    expect(rows.single['نام مشتری'], 'آزمون');
    expect(await store.getAll('products'), isEmpty);
  });

  test('migrates version 1 records without losing their original row id', () async {
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
        },
      ),
    );
    await legacyDb.close();

    final migrated = AppDatabase(databasePath: legacyPath);
    final rows = await migrated.getAll('customers');
    expect(rows, hasLength(1));
    expect(rows.single['نام مشتری'], 'مشتری قدیمی');

    final db = await migrated.database;
    final moved = await db.query('customers');
    expect(moved.single['id'], 17);
    final preserved = await db.query('legacy_records');
    expect(preserved, hasLength(1));
    expect(preserved.single['category'], 'unknown_legacy');
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
}
