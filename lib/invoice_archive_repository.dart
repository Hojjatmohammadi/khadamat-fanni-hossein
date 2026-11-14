import 'dart:convert';


import 'app_database.dart';

/// Stores the exact invoice presentation data at issue time.
/// Later edits to shop settings, stamp, signature or customer details do not
/// alter an already archived invoice.
class InvoiceArchiveRepository {
  InvoiceArchiveRepository(this._database);

  final AppDatabase _database;

  Future<int> archive({
    required int businessDocumentId,
    required Map<String, Object?> snapshot,
    required String idempotencyKey,
    int renderVersion = 1,
  }) async {
    if (businessDocumentId <= 0) {
      throw ArgumentError('شناسه فاکتور معتبر نیست');
    }
    if (idempotencyKey.trim().isEmpty) {
      throw ArgumentError('کلید ثبت فاکتور الزامی است');
    }
    if (renderVersion <= 0) {
      throw ArgumentError('نسخه قالب فاکتور معتبر نیست');
    }
    if (snapshot.isEmpty) {
      throw ArgumentError('تصویر ثابت فاکتور نمی‌تواند خالی باشد');
    }

    final encoded = jsonEncode(snapshot);
    final db = await _database.database;
    return db.transaction((txn) async {
      final document = await txn.query(
        'business_documents',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [businessDocumentId],
        limit: 1,
      );
      if (document.isEmpty) {
        throw StateError('فاکتور اصلی پیدا نشد');
      }

      final byKey = await txn.query(
        'invoice_archives',
        where: 'idempotency_key = ?',
        whereArgs: [idempotencyKey],
        limit: 1,
      );
      if (byKey.isNotEmpty) {
        final existing = byKey.single;
        if (existing['business_document_id'] == businessDocumentId &&
            existing['snapshot_json'] == encoded &&
            existing['render_version'] == renderVersion) {
          return existing['id'] as int;
        }
        throw StateError('کلید ثبت فاکتور قبلاً با اطلاعات دیگری استفاده شده است');
      }

      final byDocument = await txn.query(
        'invoice_archives',
        where: 'business_document_id = ?',
        whereArgs: [businessDocumentId],
        limit: 1,
      );
      if (byDocument.isNotEmpty) {
        final existing = byDocument.single;
        if (existing['snapshot_json'] == encoded &&
            existing['render_version'] == renderVersion) {
          return existing['id'] as int;
        }
        throw StateError('برای این فاکتور قبلاً نسخه بایگانی‌شده ثبت شده است');
      }

      return txn.insert('invoice_archives', {
        'business_document_id': businessDocumentId,
        'snapshot_json': encoded,
        'render_version': renderVersion,
        'archived_at': DateTime.now().toIso8601String(),
        'idempotency_key': idempotencyKey,
      });
    });
  }

  Future<Map<String, Object?>?> getArchive(int businessDocumentId) async {
    if (businessDocumentId <= 0) {
      throw ArgumentError('شناسه فاکتور معتبر نیست');
    }
    final db = await _database.database;
    final rows = await db.query(
      'invoice_archives',
      where: 'business_document_id = ?',
      whereArgs: [businessDocumentId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = Map<String, Object?>.from(rows.single);
    final decoded = jsonDecode(row['snapshot_json'] as String);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('ساختار نسخه بایگانی‌شده معتبر نیست');
    }
    row['snapshot'] = decoded;
    return row;
  }

  Future<List<Map<String, Object?>>> getArchives() async {
    final db = await _database.database;
    return db.query('invoice_archives', orderBy: 'archived_at DESC, id DESC');
  }
}
