import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:khadamat_fanni_hosein/app_database.dart';
import 'package:khadamat_fanni_hosein/backup_service.dart';
import 'package:khadamat_fanni_hosein/backup_storage.dart';

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
  late _FakeBackupFolderAccess folderAccess;
  late FileBackupLocationStore locationStore;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('khadamat_backup_test_');
    backups = Directory('${root.path}/backups');
    temporary = Directory('${root.path}/temporary');
    databasePath = '${root.path}/shop.db';
    clock = DateTime(2026, 11, 14, 9, 30);
    database = AppDatabase(databasePath: databasePath);
    await database.database;
    folderAccess = _FakeBackupFolderAccess();
    locationStore = FileBackupLocationStore(
      file: File(root.path + '/backup_location.json'),
    );
    service = BackupService(
      database,
      databasePath: databasePath,
      backupDirectory: backups,
      temporaryDirectory: temporary,
      clock: () => clock,
      folderAccess: folderAccess,
      locationStore: locationStore,
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

    // A successful restore must leave a separately accessible emergency
    // backup of the database state that existed immediately before restore.
    final history = await service.listBackups();
    final emergency = history.singleWhere(
      (file) => file.path.contains('khadamat-backup-emergency-'),
    );
    final emergencyDb = await databaseFactory.openDatabase(emergency.path);
    try {
      final emergencyCustomers = await emergencyDb.query('customers');
      expect(emergencyCustomers, hasLength(2));
      final emergencyNames = emergencyCustomers
          .map(
            (row) => (jsonDecode(row['data_json']! as String)
                as Map<String, dynamic>)['نام مشتری'],
          )
          .toList();
      expect(
        emergencyNames,
        containsAll(['مشتری قبل از پشتیبان', 'مشتری بعد از پشتیبان']),
      );
    } finally {
      await emergencyDb.close();
    }
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


  test('rejects a current-version backup missing required payment-allocation tables', () async {
    await database.insert('customers', {'نام مشتری': 'اطلاعات باید حفظ شود'});
    final backup = await service.createBackup();

    final damaged = await databaseFactory.openDatabase(
      backup.path,
      options: OpenDatabaseOptions(
        version: AppDatabase.schemaVersion,
        onOpen: (db) async {
          await db.execute('DROP TABLE invoice_payment_allocations');
        },
      ),
    );
    await damaged.close();

    await expectLater(
      service.restoreFromPath(backup.path),
      throwsA(isA<FormatException>()),
    );

    final rows = await database.getAll('customers');
    expect(rows, hasLength(1));
    expect(rows.single['نام مشتری'], 'اطلاعات باید حفظ شود');
  });

  test('rejects a backup with broken foreign-key relationships', () async {
    final backup = await service.createBackup();
    final damaged = await databaseFactory.openDatabase(
      backup.path,
      options: OpenDatabaseOptions(
        singleInstance: false,
        onOpen: (db) async {
          await db.execute('PRAGMA foreign_keys = OFF');
          await db.insert('inventory_movements', {
            'product_id': 999999,
            'movement_type': 'test',
            'quantity_delta': 1,
            'unit_cost': 0,
            'total_cost': 0,
            'occurred_at': '2026-11-14',
            'idempotency_key': 'broken-foreign-key-test',
            'payload_json': '{}',
            'created_at': '2026-11-14',
          });
        },
      ),
    );
    await damaged.close();

    await expectLater(
      service.restoreFromPath(backup.path),
      throwsA(isA<FormatException>()),
    );
  });



  test('persists the selected folder and copies validated backups there', () async {
    final selected = await service.chooseBackupLocation();
    expect(selected?.name, 'پوشه پشتیبان');
    expect(folderAccess.probeVerified, isTrue);
    expect((await locationStore.read())?.uri, 'content://backup-folder');

    final backup = await service.createBackup();
    expect(await backup.exists(), isTrue);
    expect(folderAccess.copiedFiles, hasLength(1));
    expect(folderAccess.copiedFiles.single, backup.path);
    expect(service.lastBackupWarning, isNull);
  });

  test('keeps the internal backup when copying to the selected folder fails', () async {
    await service.chooseBackupLocation();
    folderAccess.copyFailure = StateError('storage unavailable');

    final backup = await service.createBackup();

    expect(await backup.exists(), isTrue);
    expect(service.lastBackupWarning, contains('نسخهٔ داخلی محفوظ است'));
  });

  test('falls back to internal storage when the persisted folder grant is revoked', () async {
    await service.chooseBackupLocation();
    folderAccess.hasWriteGrant = false;

    final backup = await service.createBackup();

    expect(await backup.exists(), isTrue);
    expect(folderAccess.copiedFiles, isEmpty);
    expect(service.lastBackupWarning, contains('مجوز پوشهٔ بیرونی لغو شده'));
  });

  test('lists and deletes backups from the selected external folder', () async {
    await service.chooseBackupLocation();
    const external = ExternalBackupFile(
      uri: 'content://backup-folder/khadamat-backup-2026-11-14.db',
      folderUri: 'content://backup-folder',
      name: 'khadamat-backup-2026-11-14.db',
      length: 2048,
      lastModified: 1794648600000,
    );
    folderAccess.externalBackups.add(external);

    final listed = await service.listExternalBackups();
    expect(listed, hasLength(1));
    expect(listed.single.name, external.name);

    await service.deleteExternalBackup(external);
    expect(folderAccess.deletedUris, [external.uri]);
    expect(await service.listExternalBackups(), isEmpty);
  });

  test('restores a validated backup selected from the external folder', () async {
    final selectedFolder = await service.chooseBackupLocation();
    await database.insert('customers', {'نام مشتری': 'مشتری داخل نسخه بیرونی'});
    final backup = await service.createBackup();
    const externalUri =
        'content://backup-folder/khadamat-backup-external-restore.db';
    final external = ExternalBackupFile(
      uri: externalUri,
      folderUri: selectedFolder!.uri,
      name: 'khadamat-backup-external-restore.db',
      length: await backup.length(),
      lastModified: clock.millisecondsSinceEpoch,
    );
    folderAccess.externalSources[externalUri] = backup.path;
    folderAccess.externalBackups.add(external);

    await database.insert('customers', {'نام مشتری': 'اطلاعات جدید برای جایگزینی'});
    expect(await database.getAll('customers'), hasLength(2));

    await service.restoreFromExternalBackup(external);

    final restored = await database.getAll('customers');
    expect(restored, hasLength(1));
    expect(restored.single['نام مشتری'], 'مشتری داخل نسخه بیرونی');
  });

  test('rejects an external backup reference that is not in the selected folder', () async {
    final folder = await service.chooseBackupLocation();
    final forged = ExternalBackupFile(
      uri: 'content://unrelated/private.db',
      folderUri: folder!.uri,
      name: 'khadamat-backup-forged.db',
      length: 2048,
      lastModified: clock.millisecondsSinceEpoch,
    );

    await expectLater(
      service.deleteExternalBackup(forged),
      throwsA(isA<StateError>()),
    );
    expect(folderAccess.deletedUris, isEmpty);
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


class _FakeBackupFolderAccess implements BackupFolderAccess {
  bool hasWriteGrant = true;
  bool probeVerified = false;
  Object? copyFailure;
  final List<String> copiedFiles = <String>[];
  final List<ExternalBackupFile> externalBackups = <ExternalBackupFile>[];
  final Map<String, String> externalSources = <String, String>{};
  final List<String> deletedUris = <String>[];

  @override
  Future<BackupFolder?> pickDirectory({String? initialUri}) async =>
      const BackupFolder(uri: 'content://backup-folder', name: 'پوشه پشتیبان');

  @override
  Future<bool> hasPersistedWritePermission(String uri) async =>
      uri == 'content://backup-folder' && hasWriteGrant;

  @override
  Future<void> verifyWritable(String uri) async {
    if (!hasWriteGrant) throw StateError('write permission revoked');
    probeVerified = true;
  }

  @override
  Future<void> copyLocalFile(File source, String destinationUri) async {
    final failure = copyFailure;
    if (failure != null) throw failure;
    copiedFiles.add(source.path);
  }

  @override
  Future<List<ExternalBackupFile>> listBackups(String folderUri) async =>
      externalBackups
          .where((file) => file.folderUri == folderUri)
          .toList(growable: false);

  @override
  Future<void> copyToLocalFile(String sourceUri, String destinationPath) async {
    final sourcePath = externalSources[sourceUri];
    if (sourcePath == null) {
      throw StateError('external test file not registered');
    }
    await File(sourcePath).copy(destinationPath);
  }

  @override
  Future<void> deleteFile(String uri) async {
    deletedUris.add(uri);
    externalBackups.removeWhere((file) => file.uri == uri);
    externalSources.remove(uri);
  }
}
