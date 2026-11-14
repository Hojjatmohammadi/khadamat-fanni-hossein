import 'dart:convert';

import 'app_database.dart';

class ReportRepository {
  ReportRepository(this._database);
  final AppDatabase _database;

  Future<List<Map<String, Object?>>> getTradeDocuments({
    required DateTime from,
    required DateTime to,
    String? type,
  }) async {
    if (to.isBefore(from)) throw ArgumentError('بازه تاریخ نامعتبر است');
    final db = await _database.database;
    final where = <String>['document_date >= ?', 'document_date < ?'];
    final args = <Object?>[
      _date(from),
      _date(to.add(const Duration(days: 1))),
    ];
    if (type != null) {
      where.add('document_type = ?');
      args.add(type);
    } else {
      where.add("document_type IN ('sale','purchase','customer_return','supplier_return')");
    }
    return db.query(
      'business_documents',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'document_date ASC, id ASC',
    );
  }

  Future<List<Map<String, Object?>>> getInventoryMovements({
    required DateTime from,
    required DateTime to,
  }) async {
    if (to.isBefore(from)) throw ArgumentError('بازه تاریخ نامعتبر است');
    final db = await _database.database;
    final movements = await db.query(
      'inventory_movements',
      where: 'occurred_at >= ? AND occurred_at < ?',
      whereArgs: [
        _date(from),
        _date(to.add(const Duration(days: 1))),
      ],
      orderBy: 'occurred_at ASC, id ASC',
    );
    final productRows = await db.query('products');
    final names = <int, String>{};
    for (final row in productRows) {
      final id = row['id'] as int;
      final data = row['data_json']?.toString() ?? '{}';
      // Product display names are stored in the JSON payload; avoid assuming
      // one legacy field name across imported records.
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) {
          names[id] = (decoded['نام کالا'] ?? decoded['نام'] ?? decoded['name'] ?? 'کالای $id').toString();
        }
      } catch (_) {}
    }
    return movements.map((row) => <String, Object?>{
      ...row,
      'product_name': names[row['product_id']] ?? 'کالای ${row['product_id']}',
    }).toList();
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
