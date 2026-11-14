import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

/// Local SQLite backup and validated restore operations.
class BackupService {
  BackupService(this._appDatabase);

  final AppDatabase _appDatabase;

  Future<String> get _databaseFile async =>
      p.join(await getDatabasesPath(), AppDatabase.databaseName);

  Future<File> createBackup() async {
    final db = await _appDatabase.database;
    await db.rawQuery('PRAGMA wal_checkpoint(FULL)');
    await _appDatabase.close();

    final source = File(await _databaseFile);
    if (!await source.exists()) {
      throw StateError('پایگاه داده برنامه پیدا نشد.');
    }

    final directory = await getApplicationDocumentsDirectory();
    final backupDirectory = Directory(p.join(directory.path, 'backups'));
    await backupDirectory.create(recursive: true);
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final destination = File(
      p.join(backupDirectory.path, 'khadamat-backup-$stamp.db'),
    );
    await source.copy(destination.path);
    await _appDatabase.database;
    return destination;
  }

  Future<void> shareLatestBackup() async {
    final file = await createBackup();
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/x-sqlite3')],
      text: 'نسخه پشتیبان اطلاعات خدمات فنی حسین',
      subject: 'پشتیبان اطلاعات فروشگاه',
    );
  }

  Future<void> restoreFromFile() async {
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['db', 'sqlite', 'sqlite3'],
      allowMultiple: false,
      withData: false,
    );
    if (selection == null || selection.files.isEmpty) return;
    final selectedPath = selection.files.single.path;
    if (selectedPath == null) {
      throw StateError('دسترسی به فایل انتخاب‌شده ممکن نیست.');
    }

    final selected = File(selectedPath);
    if (!await selected.exists() || await selected.length() < 100) {
      throw const FormatException('فایل پشتیبان معتبر یا کامل نیست.');
    }
    final handle = await selected.open();
    final header = await handle.read(16);
    await handle.close();
    const sqliteHeader = [83, 81, 76, 105, 116, 101, 32, 102, 111, 114, 109, 97, 116, 32, 51, 0];
    if (header.length != 16 ||
        List<int>.generate(16, (i) => header[i]).join(',') !=
            sqliteHeader.join(',')) {
      throw const FormatException('این فایل، نسخه پشتیبان SQLite نیست.');
    }

    final directory = await getTemporaryDirectory();
    final candidate = File(p.join(
      directory.path,
      'restore-check-${DateTime.now().microsecondsSinceEpoch}.db',
    ));
    await selected.copy(candidate.path);
    Database? checkDb;
    try {
      checkDb = await openDatabase(candidate.path, readOnly: true);
      final integrity = await checkDb.rawQuery('PRAGMA integrity_check');
      if (integrity.isEmpty || integrity.first.values.first != 'ok') {
        throw const FormatException('سلامت فایل پشتیبان تأیید نشد.');
      }
      final versionRows = await checkDb.rawQuery('PRAGMA user_version');
      final version = (versionRows.first.values.first as num).toInt();
      if (version < 1 || version > AppDatabase.schemaVersion) {
        throw FormatException('نسخه پایگاه داده پشتیبان پشتیبانی نمی‌شود: $version');
      }
      final tables = await checkDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name IN "
        "('products','journal_entries','business_documents')",
      );
      if (tables.length != 3) {
        throw const FormatException('ساختار فایل پشتیبان متعلق به این برنامه نیست.');
      }
    } finally {
      await checkDb?.close();
      if (await candidate.exists()) await candidate.delete();
    }

    final targetPath = await _databaseFile;
    final target = File(targetPath);
    final rollback = File('$targetPath.before-restore');
    await _appDatabase.close();
    try {
      if (await target.exists()) {
        if (await rollback.exists()) await rollback.delete();
        await target.copy(rollback.path);
      }
      await selected.copy(targetPath);
      await _appDatabase.database;
      if (await rollback.exists()) await rollback.delete();
    } catch (_) {
      if (await rollback.exists()) {
        if (await target.exists()) await target.delete();
        await rollback.copy(targetPath);
      }
      rethrow;
    }
  }
}
