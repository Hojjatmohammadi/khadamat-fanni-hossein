import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:khadamat_fanni_hosein/app_database.dart';
import 'package:khadamat_fanni_hosein/invoice_settings_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late AppDatabase database;
  late InvoiceSettingsRepository settings;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('khadamat_invoice_settings_');
    database = AppDatabase(databasePath: '${tempDir.path}/settings.db');
    settings = InvoiceSettingsRepository(database);
  });

  tearDown(() async {
    await database.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('returns editable shop header defaults for a new installation', () async {
    final value = await settings.getSettings();
    expect(value['shopName'], 'خدمات فنی حسین');
    expect(value['ownerName'], 'حجت محمدی');
    expect(value['stampImageBase64'], '');
    expect(value['signatureImageBase64'], '');
  });

  test('persists shop details, stamp and signature locally', () async {
    final value = await settings.getSettings();
    value.addAll({
      'shopName': 'خدمات فنی حسین شعبه اصلی',
      'ownerName': 'حجت محمدی',
      'phone': '09155637505',
      'postalCode': '1234567890',
      'address': 'عشق آباد',
      'stampImageBase64': 'compressed-stamp-data',
      'signatureImageBase64': 'compressed-signature-data',
    });

    await settings.saveSettings(value);
    expect(await settings.getSettings(), value);
  });

  test('requires shop and owner names', () async {
    await expectLater(
      settings.saveSettings({
        ...InvoiceSettingsRepository.defaults,
        'shopName': ' ',
      }),
      throwsArgumentError,
    );
  });

  test('limits stored image size', () async {
    await expectLater(
      settings.saveSettings({
        ...InvoiceSettingsRepository.defaults,
        'stampImageBase64': List<String>.filled(1500001, 'x').join(),
      }),
      throwsArgumentError,
    );
  });
}
