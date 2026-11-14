import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:khadamat_fanni_hosein/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('khadamat_single_device_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('fresh local database has no multi-device sync tables', () async {
    final database = AppDatabase(databasePath: '${tempDir.path}/fresh.db');
    final db = await database.database;
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final names = tables.map((row) => row['name']).toSet();

    expect(names, containsAll(['products', 'customers', 'repairs', 'sales']));
    expect(names, isNot(contains('sync_outbox')));
    expect(names, isNot(contains('sync_conflicts')));
    await database.close();
  });

  test('version 8 database is migrated by removing unused sync tables', () async {
    final path = '${tempDir.path}/legacy_v8.db';
    final legacy = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 8,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE sync_outbox (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              event_id TEXT NOT NULL UNIQUE
            )
          ''');
          await db.execute('''
            CREATE TABLE sync_conflicts (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              event_id TEXT NOT NULL,
              FOREIGN KEY (event_id) REFERENCES sync_outbox(event_id)
            )
          ''');
        },
      ),
    );
    await legacy.close();

    final upgraded = AppDatabase(databasePath: path);
    final db = await upgraded.database;
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final names = tables.map((row) => row['name']).toSet();

    expect(names, isNot(contains('sync_outbox')));
    expect(names, isNot(contains('sync_conflicts')));
    expect(names, contains('products'));
    await upgraded.close();
  });
}
