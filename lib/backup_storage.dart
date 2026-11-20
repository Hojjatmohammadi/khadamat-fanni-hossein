import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:saf/saf.dart';

class BackupFolder {
  const BackupFolder({required this.uri, required this.name});
  final String uri;
  final String name;
}

class ExternalBackupFile {
  const ExternalBackupFile({
    required this.uri,
    required this.folderUri,
    required this.name,
    required this.length,
    required this.lastModified,
  });
  final String uri;
  final String folderUri;
  final String name;
  final int length;
  final int lastModified;
}

abstract interface class BackupFolderAccess {
  Future<BackupFolder?> pickDirectory({String? initialUri});
  Future<bool> hasPersistedWritePermission(String uri);
  Future<void> verifyWritable(String uri);
  Future<void> copyLocalFile(File source, String destinationUri);
  Future<List<ExternalBackupFile>> listBackups(String folderUri);
  Future<void> copyToLocalFile(String sourceUri, String destinationPath);
  Future<void> deleteFile(String uri);
}

class SafBackupFolderAccess implements BackupFolderAccess {
  SafBackupFolderAccess({Saf? saf}) : _saf = saf ?? Saf();
  final Saf _saf;

  @override
  Future<BackupFolder?> pickDirectory({String? initialUri}) async {
    final selected = await _saf.pickDirectory(initialUri: initialUri);
    if (selected == null) return null;
    return BackupFolder(uri: selected.uri, name: selected.name);
  }

  @override
  Future<bool> hasPersistedWritePermission(String uri) async {
    final grants = await _saf.persistedPermissions();
    return grants.any((grant) => grant.uri == uri && grant.read && grant.write);
  }

  @override
  Future<void> verifyWritable(String uri) async {
    final name = '.khadamat-backup-check-${DateTime.now().microsecondsSinceEpoch}.tmp';
    final probe = await _saf.writeFileBytes(
      uri, name, 'text/plain', Uint8List.fromList(utf8.encode('backup access check')),
    );
    await _saf.delete(probe.uri);
  }

  @override
  Future<void> copyLocalFile(File source, String destinationUri) async {
    await _saf.pasteLocalFile(
      source.path, destinationUri, p.basename(source.path),
      'application/x-sqlite3', overwrite: true,
    );
  }

  @override
  Future<List<ExternalBackupFile>> listBackups(String folderUri) async {
    final documents = await _saf.list(folderUri);
    final files = documents
        .where((d) => !d.isDir &&
            d.name.startsWith('khadamat-backup-') && d.name.endsWith('.db'))
        .map((d) => ExternalBackupFile(
              uri: d.uri,
              folderUri: folderUri,
              name: d.name,
              length: d.length,
              lastModified: d.lastModified,
            ))
        .toList();
    files.sort((a, b) => b.lastModified.compareTo(a.lastModified));
    return files;
  }

  @override
  Future<void> copyToLocalFile(String sourceUri, String destinationPath) =>
      _saf.copyToLocalFile(sourceUri, destinationPath);

  @override
  Future<void> deleteFile(String uri) => _saf.delete(uri);
}

abstract interface class BackupLocationStore {
  Future<BackupFolder?> read();
  Future<void> write(BackupFolder? folder);
}

class FileBackupLocationStore implements BackupLocationStore {
  FileBackupLocationStore({File? file}) : _fileOverride = file;
  final File? _fileOverride;

  Future<File> get _file async {
    final override = _fileOverride;
    if (override != null) return override;
    final directory = await getApplicationSupportDirectory();
    return File(p.join(directory.path, 'backup_location.json'));
  }

  @override
  Future<BackupFolder?> read() async {
    final file = await _file;
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      final uri = decoded['uri']?.toString() ?? '';
      final name = decoded['name']?.toString() ?? '';
      if (uri.isEmpty || name.isEmpty) return null;
      return BackupFolder(uri: uri, name: name);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(BackupFolder? folder) async {
    final file = await _file;
    if (folder == null) {
      if (await file.exists()) await file.delete();
      return;
    }
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({'uri': folder.uri, 'name': folder.name}),
      flush: true,
    );
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }
}
