import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:khadamat_fanni_hosein/app_database.dart';
import 'package:khadamat_fanni_hosein/backup_page.dart';
import 'package:khadamat_fanni_hosein/backup_service.dart';
import 'package:khadamat_fanni_hosein/backup_storage.dart';

void main() {
  testWidgets('backup page refreshes app state after a successful restore',
      (tester) async {
    final service = _FakeBackupService();
    var refreshCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BackupPage(
            service: service,
            onRestored: () async { refreshCount++; },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('بازیابی از فایل پشتیبان'));
    await tester.pumpAndSettle();
    expect(find.text('بازیابی نسخه پشتیبان'), findsOneWidget);

    await tester.tap(find.text('بله، بازیابی کن'));
    await tester.pumpAndSettle();

    expect(service.restoreCalled, isTrue);
    expect(refreshCount, 1);
    final successMessage =
        find.text('بازیابی انجام شد و اطلاعات برنامه تازه‌سازی شد.');
    await tester.scrollUntilVisible(successMessage, 240);
    expect(successMessage, findsOneWidget);
  });

  testWidgets('cancelling restore does not refresh app state', (tester) async {
    final service = _FakeBackupService();
    var refreshCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BackupPage(
            service: service,
            onRestored: () async { refreshCount++; },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('بازیابی از فایل پشتیبان'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('انصراف'));
    await tester.pumpAndSettle();

    expect(service.restoreCalled, isFalse);
    expect(refreshCount, 0);
  });
}

class _FakeBackupService extends BackupService {
  _FakeBackupService()
      : super(AppDatabase(databasePath: 'unused-backup-page-test.db'));

  bool restoreCalled = false;

  @override
  Future<void> restoreFromFile() async {
    restoreCalled = true;
  }

  @override
  Future<List<File>> listBackups() async => <File>[];

  @override
  Future<BackupFolder?> getBackupLocation() async => null;

  @override
  Future<List<ExternalBackupFile>> listExternalBackups() async =>
      <ExternalBackupFile>[];
}
