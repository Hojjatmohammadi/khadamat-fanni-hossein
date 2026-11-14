import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:khadamat_fanni_hosein/app_database.dart';
import 'package:khadamat_fanni_hosein/backup_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory root;
  late Directory backups;
  late Directory temporary;
  late String databasePath;
  late AppDatabase database;
  late DateTime clock;
  late BackupService service;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('khadamat_backup_test_');
    backups = Directory('${root.path}/backups');
    temporary = Directory('${root.path}/temporary');
    databasePath = '${root.path}/shop.db';
    clock = DateTime(2026, 11, 14, 9, 30);
    database = AppDatabase(databasePath: databasePath);
    await database.database;
    service = BackupService(
      database,
      databasePath: databasePath,
      backupDirectory: backups,
      temporaryDirectory: temporary,
      clock: () => clock,
    );
  });

  tearDown(() async {
    await database.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('creates one valid automatic backup per local day', () async {
    final first = await service.createDailyBackupIfDue();
    expect(first, isNotNull);
    expect(await first!.exists(), isTrue);
    expect(first.path, contains('khadamat-backup-daily-2026-11-14.db'));

    final second = await service.createDailyBackupIfDue();
    expect(second, isNull);

    clock = DateTime(2026, 11, 15, 8);
    final nextDay = await service.createDailyBackupIfDue();
    expect(nextDay, isNotNull);
    expect(await service.listBackups(), hasLength(2));
  });

  test('creates a manual backup and exposes it in backup history', () async {
    await database.insert('customers', {'نام مشتری': 'مشتری آزمایشی'});

    final backup = await service.createBackup();
    expect(await backup.exists(), isTrue);
    expect((await service.listBackups()).map((f) => f.path), contains(backup.path));

    final handle = await backup.open();
    final header = await handle.read(16);
    await handle.close();
    expect(String.fromCharCodes(header), 'SQLite format 3\u0000');
  });

  test('restores a validated backup and removes later records', () async {
    await database.insert('customers', {'نام مشتری': 'مشتری قبل از پشتیبان'});
    final backup = await service.createBackup();

    await database.insert('customers', {'نام مشتری': 'مشتری بعد از پشتیبان'});
    expect(await database.getAll('customers'), hasLength(2));

    await service.restoreFromPath(backup.path);

    final restored = await database.getAll('customers');
    expect(restored, hasLength(1));
    expect(restored.single['نام مشتری'], 'مشتری قبل از پشتیبان');
  });

  test('rejects a malformed backup without changing current data', () async {
    await database.insert('customers', {'نام مشتری': 'باقی بماند'});
    final malformed = File('${root.path}/broken.db');
    await malformed.writeAsString('not a SQLite database');

    await expectLater(
      service.restoreFromPath(malformed.path),
      throwsA(isA<FormatException>()),
    );

    final rows = await database.getAll('customers');
    expect(rows, hasLength(1));
    expect(rows.single['نام مشتری'], 'باقی بماند');
  });

  test('prevents deleting files outside the app backup folder', () async {
    final outside = File('${root.path}/keep.db');
    await outside.writeAsString('keep');

    await expectLater(
      service.deleteBackup(outside),
      throwsA(isA<ArgumentError>()),
    );
    expect(await outside.exists(), isTrue);
  });
}
