import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import 'app_database.dart';
import 'backup_storage.dart';

/// Local SQLite backup, daily backup and validated restore operations.
class BackupService {
  BackupService(
    this._appDatabase, {
    String? databasePath,
    Directory? backupDirectory,
    Directory? temporaryDirectory,
    DateTime Function()? clock,
    BackupFolderAccess? folderAccess,
    BackupLocationStore? locationStore,
  })  : _databasePathOverride = databasePath,
        _backupDirectoryOverride = backupDirectory,
        _temporaryDirectoryOverride = temporaryDirectory,
        _clock = clock ?? DateTime.now,
        _folderAccess = folderAccess ??
            (Platform.isAndroid ? SafBackupFolderAccess() : null),
        _locationStore = locationStore ?? FileBackupLocationStore();

  final AppDatabase _appDatabase;
  final String? _databasePathOverride;
  final Directory? _backupDirectoryOverride;
  final Directory? _temporaryDirectoryOverride;
  final DateTime Function() _clock;

  final BackupFolderAccess? _folderAccess;
  final BackupLocationStore _locationStore;
  String? lastBackupWarning;

  Future<BackupFolder?> getBackupLocation() => _locationStore.read();

  Future<BackupFolder?> chooseBackupLocation() async {
    final access = _folderAccess;
    if (access == null) {
      throw UnsupportedError('انتخاب پوشهٔ بیرونی پشتیبان‌گیری فقط در اندروید فعال است.');
    }
    final current = await _locationStore.read();
    final selected = await access.pickDirectory(initialUri: current?.uri);
    if (selected == null) return null;
    if (!await access.hasPersistedWritePermission(selected.uri)) {
      throw StateError('مجوز ماندگار خواندن و نوشتن پوشه دریافت نشد؛ پوشه را دوباره انتخاب کنید.');
    }
    await access.verifyWritable(selected.uri);
    await _locationStore.write(selected);
    lastBackupWarning = null;
    return selected;
  }

  Future<void> clearBackupLocation() async {
    await _locationStore.write(null);
    lastBackupWarning = null;
  }

  Future<List<ExternalBackupFile>> listExternalBackups() async {
    final folder = await _locationStore.read();
    final access = _folderAccess;
    if (folder == null || access == null) return <ExternalBackupFile>[];
    try {
      if (!await access.hasPersistedWritePermission(folder.uri)) {
        lastBackupWarning = 'مجوز پوشهٔ بیرونی در دسترس نیست؛ نسخه‌های داخلی همچنان محفوظ‌اند.';
        return <ExternalBackupFile>[];
      }
      return await access.listBackups(folder.uri);
    } catch (error) {
      lastBackupWarning = 'دسترسی به پوشهٔ بیرونی برقرار نیست؛ نسخهٔ داخلی پشتیبان محفوظ است. ($error)';
      return <ExternalBackupFile>[];
    }
  }

  Future<void> _validateExternalBackupReference(
    BackupFolderAccess access,
    BackupFolder folder,
    ExternalBackupFile file,
  ) async {
    if (file.folderUri != folder.uri ||
        !p.basename(file.name).startsWith('khadamat-backup-') ||
        !file.name.endsWith('.db')) {
      throw ArgumentError('فایل انتخاب‌شده متعلق به فهرست پشتیبان‌های معتبر نیست.');
    }
    final currentFiles = await access.listBackups(folder.uri);
    final stillExists = currentFiles.any(
      (candidate) =>
          candidate.uri == file.uri &&
          candidate.folderUri == folder.uri &&
          candidate.name == file.name,
    );
    if (!stillExists) {
      throw StateError('فایل پشتیبان دیگر در پوشهٔ انتخاب‌شده وجود ندارد؛ فهرست را تازه‌سازی کنید.');
    }
  }

  Future<void> deleteExternalBackup(ExternalBackupFile file) async {
    final folder = await _locationStore.read();
    final access = _folderAccess;
    if (folder == null || access == null) {
      throw ArgumentError('پوشهٔ پشتیبان بیرونی انتخاب نشده است.');
    }
    if (!await access.hasPersistedWritePermission(folder.uri)) {
      throw StateError('مجوز حذف از پوشهٔ پشتیبان وجود ندارد؛ پوشه را دوباره انتخاب کنید.');
    }
    await _validateExternalBackupReference(access, folder, file);
    await access.deleteFile(file.uri);
  }

  Future<void> restoreFromExternalBackup(ExternalBackupFile file) async {
    final folder = await _locationStore.read();
    final access = _folderAccess;
    if (folder == null || access == null) {
      throw ArgumentError('پوشهٔ پشتیبان بیرونی انتخاب نشده است.');
    }
    if (!await access.hasPersistedWritePermission(folder.uri)) {
      throw StateError('مجوز پوشهٔ پشتیبان وجود ندارد؛ پوشه را دوباره انتخاب کنید.');
    }
    await _validateExternalBackupReference(access, folder, file);
    final temporaryDirectory = await _temporaryDirectory;
    await temporaryDirectory.create(recursive: true);
    final staged = File(p.join(
      temporaryDirectory.path,
      'external-restore-${_clock().microsecondsSinceEpoch}.db',
    ));
    try {
      await access.copyToLocalFile(file.uri, staged.path);
      await restoreFromPath(staged.path);
    } finally {
      if (await staged.exists()) await staged.delete();
    }
  }

  Future<void> _copyToSelectedFolder(File backup) async {
    lastBackupWarning = null;
    try {
      final folder = await _locationStore.read();
      final access = _folderAccess;
      if (folder == null || access == null) return;
      if (!await access.hasPersistedWritePermission(folder.uri)) {
        lastBackupWarning =
            'مجوز پوشهٔ بیرونی لغو شده است؛ نسخه در حافظهٔ داخلی ذخیره شد. پوشه را دوباره انتخاب کنید.';
        return;
      }
      await access.copyLocalFile(backup, folder.uri);
    } catch (error) {
      // An unavailable location preference must never invalidate the local snapshot.
      lastBackupWarning =
          'ذخیره در پوشهٔ بیرونی انجام نشد؛ نسخهٔ داخلی محفوظ است. ($error)';
    }
  }


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
        await _copyToSelectedFolder(dailyFile);
        return null;
      } catch (_) {
        await dailyFile.delete();
      }
    }

    return createBackup(daily: true);
  }

  /// Makes a consistent on-disk copy after checking that SQLite can checkpoint.
  Future<File> createBackup({bool daily = false, bool emergency = false}) async {
    if (daily && emergency) {
      throw ArgumentError('پشتیبان روزانه و اضطراری نمی‌توانند هم‌زمان انتخاب شوند.');
    }
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
          : emergency
              ? 'khadamat-backup-emergency-${_dateStamp(now)}-${_timeStamp(now)}-'
                  '${now.microsecondsSinceEpoch % 1000000}.db'
              : 'khadamat-backup-${_dateStamp(now)}-${_timeStamp(now)}-'
                  '${now.microsecondsSinceEpoch % 1000000}.db';
      destination = File(p.join(directory.path, fileName));

      await source.copy(destination.path);
      await _validateBackupFile(destination);
      await _applyRetention();
      await _copyToSelectedFolder(destination);
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

  /// Returns false when the user cancels the file picker; true only after restore succeeds.
  Future<bool> restoreFromFile() async {
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['db', 'sqlite', 'sqlite3'],
      allowMultiple: false,
      withData: false,
    );
    if (selection == null || selection.files.isEmpty) return false;
    final selectedPath = selection.files.single.path;
    if (selectedPath == null) {
      throw StateError('دسترسی به فایل انتخاب‌شده ممکن نیست.');
    }
    await restoreFromPath(selectedPath);
    return true;
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

    // Stage the selected backup before creating the emergency copy. Retention
    // may remove the oldest item from the backup folder; staging first ensures
    // it cannot delete the very file the user selected for restoration.
    try {
      await selected.copy(staged.path);
      await _validateBackupFile(staged);

      // Keep a separately listed, validated emergency copy before replacing
      // the live database. The rollback file below protects the swap itself;
      // this backup remains available after a successful restore.
      await createBackup(emergency: true);
    } catch (_) {
      if (await staged.exists()) await staged.delete();
      rethrow;
    }

    try {
      final activeDb = await _appDatabase.database;
      final checkpoint = await activeDb.rawQuery('PRAGMA wal_checkpoint(FULL)');
      if (checkpoint.isNotEmpty) {
        final busy = checkpoint.first['busy'];
        if (busy is num && busy != 0) {
          throw StateError(
            'پایگاه داده در حال استفاده است؛ بازیابی انجام نشد. دوباره تلاش کنید.',
          );
        }
      }
    } catch (_) {
      if (await staged.exists()) await staged.delete();
      rethrow;
    }

    await _appDatabase.close();
    try {
      await _removeSidecars(targetPath);
      if (await target.exists()) {
        if (await rollback.exists()) await rollback.delete();
        await target.copy(rollback.path);
        hadOriginal = true;
      }

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
      if (version >= 11) required.add('invoice_archives');
      if (version >= 12) required.add('invoice_settings');
      if (version >= 13) {
        required.addAll([
          'loan_records',
          'loan_installments',
          'loan_transactions',
        ]);
      }
      if (version >= 14) required.add('party_roles');
      if (version >= 15) required.add('invoice_payment_allocations');

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

    final foreignKeyErrors = await db.rawQuery('PRAGMA foreign_key_check');
    if (foreignKeyErrors.isNotEmpty) {
      throw const FormatException(
        'ارتباط بین اطلاعات فایل پشتیبان ناقص است؛ بازیابی انجام نشد.',
      );
    }
  }
}
