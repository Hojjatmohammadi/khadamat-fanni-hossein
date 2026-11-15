import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

/// Persists editable shop invoice header settings on this device.
class InvoiceSettingsRepository {
  InvoiceSettingsRepository(this._database);

  final AppDatabase _database;

  static const Map<String, String> defaults = {
    'shopName': 'خدمات فنی حسین',
    'ownerName': 'حجت محمدی',
    'phone': '',
    'postalCode': '',
    'address': '',
    'stampImageBase64': '',
    'signatureImageBase64': '',
    'appLogoBase64': '',
    'currency': 'تومان',
    'vatPercent': '0',
    'defaultDiscount': '0',
    'invoicePrefix': '',
  };

  Future<Map<String, String>> getSettings() async {
    final db = await _database.database;
    final rows = await db.query(
      'invoice_settings',
      where: 'id = 1',
      limit: 1,
    );
    if (rows.isEmpty) return Map<String, String>.from(defaults);

    final decoded = jsonDecode(rows.single['data_json'] as String);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('تنظیمات سربرگ فاکتور معتبر نیست');
    }
    return {
      for (final key in defaults.keys)
        key: decoded[key]?.toString() ?? defaults[key]!,
    };
  }

  Future<void> saveSettings(Map<String, String> settings) async {
    final clean = <String, String>{
      for (final key in defaults.keys)
        key: (settings[key] ?? defaults[key]!).trim(),
    };
    if (clean['shopName']!.isEmpty || clean['ownerName']!.isEmpty) {
      throw ArgumentError('نام فروشگاه و نام مسئول فاکتور الزامی است');
    }
    // Keep each compressed image bounded to avoid oversized SQLite backups.
    for (final key in ['stampImageBase64', 'signatureImageBase64', 'appLogoBase64']) {
      if (clean[key]!.length > 1500000) {
        throw ArgumentError('حجم تصویر لوگو، مهر یا امضا بیش از حد مجاز است');
      }
    }

    final db = await _database.database;
    await db.insert(
      'invoice_settings',
      {
        'id': 1,
        'data_json': jsonEncode(clean),
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
