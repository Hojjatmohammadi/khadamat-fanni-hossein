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


  /// Profit and loss balances derived from posted double-entry journal lines.
  /// Reversal entries are naturally included as they carry opposite postings.
  Future<List<Map<String, Object?>>> getProfitAndLoss({
    required DateTime from,
    required DateTime to,
  }) async {
    if (to.isBefore(from)) throw ArgumentError('بازه تاریخ نامعتبر است');
    final db = await _database.database;
    return db.rawQuery('''
      SELECT a.code AS account_code, a.name AS account_name,
        a.account_type AS account_type,
        COALESCE(SUM(l.debit), 0) AS total_debit,
        COALESCE(SUM(l.credit), 0) AS total_credit,
        CASE WHEN a.account_type = 'income'
          THEN COALESCE(SUM(l.credit - l.debit), 0)
          ELSE COALESCE(SUM(l.debit - l.credit), 0)
        END AS balance
      FROM accounts a
      LEFT JOIN journal_entries e ON e.entry_date >= ? AND e.entry_date < ?
      LEFT JOIN journal_lines l ON l.journal_entry_id = e.id
        AND l.account_code = a.code
      WHERE a.account_type IN ('income', 'expense')
      GROUP BY a.code, a.name, a.account_type
      HAVING total_debit != 0 OR total_credit != 0
      ORDER BY a.account_type, a.code
    ''', [
      _date(from),
      _date(to.add(const Duration(days: 1))),
    ]);
  }

  /// Net sales margin by item: sales less customer returns, minus the
  /// corresponding cost of goods sold. Supplier returns do not affect sales.
  Future<List<Map<String, Object?>>> getItemProfit({
    required DateTime from,
    required DateTime to,
  }) async {
    if (to.isBefore(from)) throw ArgumentError('بازه تاریخ نامعتبر است');
    final db = await _database.database;
    return db.rawQuery('''
      SELECT l.product_id,
        l.product_name,
        SUM(CASE WHEN d.document_type = 'sale'
          THEN l.line_total ELSE -l.line_total END) AS net_revenue,
        SUM(CASE WHEN d.document_type = 'sale'
          THEN l.quantity * l.unit_cost
          ELSE -l.quantity * l.unit_cost END) AS net_cost,
        SUM(CASE WHEN d.document_type = 'sale'
          THEN l.line_total - (l.quantity * l.unit_cost)
          ELSE -(l.line_total - (l.quantity * l.unit_cost)) END) AS gross_profit,
        SUM(CASE WHEN d.document_type = 'sale'
          THEN l.quantity ELSE -l.quantity END) AS net_quantity
      FROM business_document_lines l
      JOIN business_documents d ON d.id = l.document_id
      WHERE d.document_type IN ('sale', 'customer_return')
        AND d.document_date >= ? AND d.document_date < ?
      GROUP BY l.product_id, l.product_name
      ORDER BY gross_profit DESC, l.product_name COLLATE NOCASE
    ''', [
      _date(from),
      _date(to.add(const Duration(days: 1))),
    ]);
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
