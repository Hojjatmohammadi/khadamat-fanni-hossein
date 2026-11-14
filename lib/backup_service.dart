import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

/// Local SQLite backup, daily backup and validated restore operations.
class BackupService {
  BackupService(
    this._appDatabase, {
    String? databasePath,
    Directory? backupDirectory,
    Directory? temporaryDirectory,
    DateTime Function()? clock,
  })  : _databasePathOverride = databasePath,
        _backupDirectoryOverride = backupDirectory,
        _temporaryDirectoryOverride = temporaryDirectory,
        _clock = clock ?? DateTime.now;

  final AppDatabase _appDatabase;
  final String? _databasePathOverride;
  final Directory? _backupDirectoryOverride;
  final Directory? _temporaryDirectoryOverride;
  final DateTime Function() _clock;

  Future<String> get _databaseFile async {
    final override = _databasePathOverride;
    if (override != null) return override;
    return p.join(await getDatabasesPath(), AppDatabase.databaseName);
  }

  Future<Directory> get _backupDirectory async {
    final override = _backupDirectoryOverride;
    if (override != null) return override;
    final documents = await getApplicationDocumentsDirectory();
    return Directory(p.join(documents.path, 'backups'));
  }

  Future<Directory> get _temporaryDirectory async {
    final override = _temporaryDirectoryOverride;
    if (override != null) return override;
    return getTemporaryDirectory();
  }

  String _dateStamp(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  String _timeStamp(DateTime date) =>
      '${date.hour.toString().padLeft(2, '0')}-'
      '${date.minute.toString().padLeft(2, '0')}-'
      '${date.second.toString().padLeft(2, '0')}-'
      '${date.millisecond.toString().padLeft(3, '0')}';

  /// Creates one automatic backup per local calendar day while the app is opened.
  /// Returns null when a valid backup for today already exists.
  Future<File?> createDailyBackupIfDue() async {
    final now = _clock();
    final directory = await _backupDirectory;
    await directory.create(recursive: true);
    final dailyFile = File(
      p.join(directory.path, 'khadamat-backup-daily-${_dateStamp(now)}.db'),
    );

    if (await dailyFile.exists()) {
      try {
        await _validateBackupFile(dailyFile);
        return null;
      } catch (_) {
        await dailyFile.delete();
      }
    }

    return createBackup(daily: true);
  }

  /// Makes a consistent on-disk copy after checking that SQLite can checkpoint.
  Future<File> createBackup({bool daily = false}) async {
    final db = await _appDatabase.database;
    final checkpoint = await db.rawQuery('PRAGMA wal_checkpoint(FULL)');
    if (checkpoint.isNotEmpty) {
      final busy = checkpoint.first['busy'];
      if (busy is num && busy != 0) {
        throw StateError(
          'پایگاه داده در حال استفاده است؛ تهیه نسخه پشتیبان انجام نشد. دوباره تلاش کنید.',
        );
      }
    }

    await _appDatabase.close();
    File? destination;
    try {
      final source = File(await _databaseFile);
      if (!await source.exists()) {
        throw StateError('پایگاه داده برنامه پیدا نشد.');
      }

      final directory = await _backupDirectory;
      await directory.create(recursive: true);
      final now = _clock();
      final fileName = daily
          ? 'khadamat-backup-daily-${_dateStamp(now)}.db'
          : 'khadamat-backup-${_dateStamp(now)}-${_timeStamp(now)}-'
              '${now.microsecondsSinceEpoch % 1000000}.db';
      destination = File(p.join(directory.path, fileName));

      await source.copy(destination.path);
      await _validateBackupFile(destination);
      await _applyRetention();
      return destination;
    } catch (_) {
      if (destination != null && await destination.exists()) {
        await destination.delete();
      }
      rethrow;
    } finally {
      // Reopen the shared database handle even when copying or validation fails.
      await _appDatabase.database;
    }
  }

  Future<List<File>> listBackups() async {
    final directory = await _backupDirectory;
    if (!await directory.exists()) return <File>[];

    final files = <File>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File) {
        final name = p.basename(entity.path);
        if (name.startsWith('khadamat-backup-') && name.endsWith('.db')) {
          files.add(entity);
        }
      }
    }
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }

  Future<void> _applyRetention({int keep = 30}) async {
    final files = await listBackups();
    for (final file in files.skip(keep)) {
      await file.delete();
    }
  }

  Future<void> deleteBackup(File file) async {
    final directory = await _backupDirectory;
    final directoryPath = p.normalize(directory.absolute.path);
    final filePath = p.normalize(file.absolute.path);
    if (p.dirname(filePath) != directoryPath ||
        !p.basename(filePath).startsWith('khadamat-backup-') ||
        !p.basename(filePath).endsWith('.db')) {
      throw ArgumentError('فقط فایل‌های پشتیبان همین برنامه قابل حذف هستند.');
    }
    if (await file.exists()) await file.delete();
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
    await restoreFromPath(selectedPath);
  }

  /// Public path-based restore method also allows deterministic automated tests.
  Future<void> restoreFromPath(String sourcePath) async {
    final selected = File(sourcePath);
    if (!await selected.exists()) {
      throw const FormatException('فایل پشتیبان پیدا نشد.');
    }

    final targetPath = await _databaseFile;
    if (p.normalize(selected.absolute.path) ==
        p.normalize(File(targetPath).absolute.path)) {
      throw const FormatException(
        'فایل پایگاه داده فعال را نمی‌توان به‌عنوان فایل پشتیبان انتخاب کرد.',
      );
    }

    await _validateBackupFile(selected);

    final temporaryDirectory = await _temporaryDirectory;
    await temporaryDirectory.create(recursive: true);
    final candidate = File(
      p.join(
        temporaryDirectory.path,
        'restore-check-${_clock().microsecondsSinceEpoch}.db',
      ),
    );
    try {
      await selected.copy(candidate.path);
      await _validateBackupFile(candidate);
    } finally {
      if (await candidate.exists()) await candidate.delete();
    }

    final target = File(targetPath);
    await target.parent.create(recursive: true);
    final rollback = File('$targetPath.before-restore');
    final staged = File(
      '$targetPath.restore-${_clock().microsecondsSinceEpoch}',
    );
    var hadOriginal = false;

    await _appDatabase.close();
    try {
      await _removeSidecars(targetPath);
      if (await target.exists()) {
        if (await rollback.exists()) await rollback.delete();
        await target.copy(rollback.path);
        hadOriginal = true;
      }

      await selected.copy(staged.path);
      final stagedHandle = await staged.open(mode: FileMode.append);
      try {
        await stagedHandle.flush();
      } finally {
        await stagedHandle.close();
      }
      if (await target.exists()) await target.delete();
      await staged.rename(targetPath);

      final restoredDb = await _appDatabase.database;
      await _checkDatabaseIntegrity(restoredDb);

      if (await rollback.exists()) await rollback.delete();
    } catch (_) {
      await _appDatabase.close();
      await _removeSidecars(targetPath);
      if (await target.exists()) await target.delete();

      if (hadOriginal && await rollback.exists()) {
        await rollback.copy(targetPath);
      }
      // Restore the shared connection even after rolling back a failed import.
      await _appDatabase.database;
      rethrow;
    } finally {
      if (await staged.exists()) await staged.delete();
    }
  }

  Future<void> _removeSidecars(String databasePath) async {
    for (final suffix in const ['-wal', '-shm', '-journal']) {
      final sidecar = File('$databasePath$suffix');
      if (await sidecar.exists()) await sidecar.delete();
    }
  }

  Future<void> _validateBackupFile(File file) async {
    if (!await file.exists() || await file.length() < 100) {
      throw const FormatException('فایل پشتیبان معتبر یا کامل نیست.');
    }

    final handle = await file.open();
    final headerBytes = await handle.read(16);
    await handle.close();
    const sqliteHeader = 'SQLite format 3\u0000';
    if (String.fromCharCodes(headerBytes) != sqliteHeader) {
      throw const FormatException('این فایل، نسخه پشتیبان SQLite نیست.');
    }

    Database? checkDb;
    try {
      checkDb = await openDatabase(
        file.path,
        readOnly: true,
        singleInstance: false,
      );
      await _checkDatabaseIntegrity(checkDb);

      final versionRows = await checkDb.rawQuery('PRAGMA user_version');
      if (versionRows.isEmpty || versionRows.first.values.first is! num) {
        throw const FormatException('نسخه پایگاه داده قابل تشخیص نیست.');
      }
      final version = (versionRows.first.values.first as num).toInt();
      if (version < 1 || version > AppDatabase.schemaVersion) {
        throw FormatException(
          'نسخه پایگاه داده پشتیبان پشتیبانی نمی‌شود: $version',
        );
      }

      final tableRows = await checkDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final tables = tableRows.map((row) => row['name'].toString()).toSet();
      final required = <String>{};

      if (version < 2) {
        required.add('records');
      } else {
        required.addAll([
          'products',
          'customers',
          'repairs',
          'sales',
          'legacy_records',
        ]);
      }
      if (version >= 3) {
        required.addAll([
          'accounts',
          'journal_entries',
          'journal_lines',
          'inventory_movements',
        ]);
      }
      if (version >= 4) {
        required.addAll(['business_documents', 'business_document_lines']);
      }
      if (version >= 5) {
        required.addAll(['parties', 'check_records', 'check_events']);
      }
      if (version >= 7) required.add('bank_reconciliations');

      final missing = required.difference(tables);
      if (missing.isNotEmpty) {
        throw FormatException(
          'ساختار فایل پشتیبان ناقص است: ${missing.join('، ')}',
        );
      }
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException('خواندن نسخه پشتیبان ناموفق بود: $error');
    } finally {
      await checkDb?.close();
    }
  }

  Future<void> _checkDatabaseIntegrity(Database db) async {
    final integrity = await db.rawQuery('PRAGMA integrity_check');
    if (integrity.isEmpty ||
        integrity.first.values.first?.toString().toLowerCase() != 'ok') {
      throw const FormatException('سلامت فایل پایگاه داده تأیید نشد.');
    }
  }
}
