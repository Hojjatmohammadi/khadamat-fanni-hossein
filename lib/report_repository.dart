import 'dart:convert';

import 'app_database.dart';
import 'localized_number.dart';

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
    // Calculate the running balance over the complete ledger first, then
    // apply the requested date range. This keeps the opening balance before
    // the report period and makes every Kardex row's balance accurate.
    final movements = await db.rawQuery('''
      WITH ledger AS (
        SELECT m.*,
          SUM(m.quantity_delta) OVER (
            PARTITION BY m.product_id
            ORDER BY m.occurred_at ASC, m.id ASC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
          ) AS balance_after
        FROM inventory_movements m
      )
      SELECT * FROM ledger
      WHERE occurred_at >= ? AND occurred_at < ?
      ORDER BY occurred_at ASC, id ASC
    ''', [
      _date(from),
      _date(to.add(const Duration(days: 1))),
    ]);
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
    return movements.map((row) {
      String? adjustmentReason;
      double? countedQuantity;
      if (row['movement_type'] == 'adjustment' &&
          row['reference_type'] == 'stock_count') {
        try {
          final reference = jsonDecode(row['reference_id']?.toString() ?? '{}');
          if (reference is Map) {
            adjustmentReason = reference['reason']?.toString();
            final counted = reference['countedQuantity'];
            if (counted is num) {
              countedQuantity = counted.toDouble();
            } else if (counted != null) {
              countedQuantity = double.tryParse(counted.toString());
            }
          }
        } catch (_) {
          // Keep legacy or malformed adjustment references visible.
        }
      }
      return <String, Object?>{
        ...row,
        'product_name': names[row['product_id']] ?? 'کالای ${row['product_id']}',
        'adjustment_reason': adjustmentReason,
        'counted_quantity': countedQuantity,
      };
    }).toList();
  }


  /// Current catalogue prices and ledger-derived stock balances.
  /// The quantity comes from immutable inventory movements, never legacy JSON.
  Future<List<Map<String, Object?>>> getStockPriceList() async {
    final db = await _database.database;
    final rows = await db.rawQuery('''
      SELECT p.id AS product_id, p.data_json,
        COALESCE(SUM(m.quantity_delta), 0) AS stock_quantity,
        COALESCE(SUM(CASE
          WHEN m.quantity_delta > 0 THEN m.total_cost
          WHEN m.quantity_delta < 0 THEN -m.total_cost
          ELSE 0
        END), 0) AS stock_value
      FROM products p
      LEFT JOIN inventory_movements m ON m.product_id = p.id
      GROUP BY p.id, p.data_json
      ORDER BY p.id ASC
    ''');

    int amount(Object? value) =>
        LocalizedNumber.tryParseDouble(value?.toString() ?? '')?.round() ?? 0;

    return rows.map((row) {
      Map<String, Object?> data = const {};
      try {
        final decoded = jsonDecode(row['data_json']?.toString() ?? '{}');
        if (decoded is Map) {
          data = Map<String, Object?>.from(decoded);
        }
      } catch (_) {
        // Keep malformed legacy rows visible with their database ID.
      }
      final id = (row['product_id'] as num).toInt();
      return <String, Object?>{
        'product_id': id,
        'product_name': (data['نام کالا'] ?? data['نام'] ?? data['name'] ?? 'کالای $id').toString(),
        'product_code': (data['کد کالا'] ?? data['کد'] ?? '').toString(),
        'category': (data['گروه اصلی'] ?? data['دسته‌بندی'] ?? '').toString(),
        'stock_quantity': (row['stock_quantity'] as num).toDouble(),
        // Value uses signed historical movement costs, not the mutable catalogue price.
        'stock_value': (row['stock_value'] as num).round(),
        'purchase_price': amount(
          data['قیمت خرید هر واحد'] ?? data['بهای تمام‌شده هر واحد'],
        ),
        'sale_price': amount(data['قیمت فروش']),
      };
    }).toList(growable: false);
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

  /// Net quantity and revenue for each item, with customer returns
  /// deducted from sales during the selected inclusive date range.
  Future<List<Map<String, Object?>>> getItemSales({
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
          THEN l.quantity ELSE -l.quantity END) AS net_quantity
      FROM business_document_lines l
      JOIN business_documents d ON d.id = l.document_id
      WHERE d.document_type IN ('sale', 'customer_return')
        AND d.document_date >= ? AND d.document_date < ?
      GROUP BY l.product_id, l.product_name
      ORDER BY net_revenue DESC, l.product_name COLLATE NOCASE
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
      WITH line_totals AS (
        SELECT l.document_id, d.document_type, l.product_id, l.product_name,
          SUM(l.line_total) AS line_total,
          SUM(l.quantity) AS quantity,
          SUM(l.quantity * l.unit_cost) AS fallback_cost
        FROM business_document_lines l
        JOIN business_documents d ON d.id = l.document_id
        WHERE d.document_type IN ('sale', 'customer_return')
          AND d.document_date >= ? AND d.document_date < ?
        GROUP BY l.document_id, d.document_type, l.product_id, l.product_name
      ),
      movement_totals AS (
        SELECT reference_id, product_id, movement_type,
          SUM(total_cost) AS exact_cost
        FROM inventory_movements
        WHERE movement_type IN ('sale', 'customer_return')
        GROUP BY reference_id, product_id, movement_type
      ),
      item_totals AS (
        SELECT lt.product_id, lt.product_name,
          SUM(CASE WHEN lt.document_type = 'sale'
            THEN lt.line_total ELSE -lt.line_total END) AS net_revenue,
          SUM(CASE
            WHEN lt.document_type = 'sale'
              THEN COALESCE(sale_movement.exact_cost, lt.fallback_cost)
            ELSE -COALESCE(return_movement.exact_cost, lt.fallback_cost)
          END) AS net_cost,
          SUM(CASE WHEN lt.document_type = 'sale'
            THEN lt.quantity ELSE -lt.quantity END) AS net_quantity
        FROM line_totals lt
        LEFT JOIN movement_totals sale_movement
          ON sale_movement.reference_id = CAST(lt.document_id AS TEXT)
          AND sale_movement.product_id = lt.product_id
          AND sale_movement.movement_type = 'sale'
        LEFT JOIN movement_totals return_movement
          ON return_movement.reference_id = CAST(lt.document_id AS TEXT)
          AND return_movement.product_id = lt.product_id
          AND return_movement.movement_type = 'customer_return'
        GROUP BY lt.product_id, lt.product_name
      )
      SELECT product_id, product_name, net_revenue, net_cost,
        net_revenue - net_cost AS gross_profit, net_quantity
      FROM item_totals
      ORDER BY gross_profit DESC, product_name COLLATE NOCASE
    ''', [
      _date(from),
      _date(to.add(const Duration(days: 1))),
    ]);
  }

  /// Posted expense entries, grouped by journal entry and expense account.
  /// The report reads only the expense side of the journal, never cash/bank
  /// credits, so paying an expense cannot be counted as a second expense.
  Future<List<Map<String, Object?>>> getExpenses({
    required DateTime from,
    required DateTime to,
  }) async {
    if (to.isBefore(from)) throw ArgumentError('بازه تاریخ نامعتبر است');
    final db = await _database.database;
    return db.rawQuery('''
      SELECT e.id AS journal_entry_id, e.entry_date, e.description,
        l.account_code, a.name AS account_name,
        l.debit - l.credit AS amount, l.memo
      FROM journal_entries e
      JOIN journal_lines l ON l.journal_entry_id = e.id
      JOIN accounts a ON a.code = l.account_code
      WHERE e.reference_type = 'expense'
        AND e.entry_date >= ? AND e.entry_date < ?
        AND a.account_type = 'expense'
      ORDER BY e.entry_date ASC, e.id ASC, l.line_no ASC
    ''', [
      _date(from),
      _date(to.add(const Duration(days: 1))),
    ]);
  }

  /// Labour revenue for repair services, excluding later customer receipts.
  /// Only the 4100 income credit is reported, so settlements do not duplicate
  /// revenue already recognized when the repair service was recorded.
  Future<List<Map<String, Object?>>> getRepairServiceRevenue({
    required DateTime from,
    required DateTime to,
  }) async {
    if (to.isBefore(from)) throw ArgumentError('بازه تاریخ نامعتبر است');
    final db = await _database.database;
    return db.rawQuery('''
      SELECT e.id AS journal_entry_id, e.entry_date, e.description,
        l.account_code, a.name AS account_name,
        l.credit - l.debit AS amount, l.party_id, l.memo
      FROM journal_entries e
      JOIN journal_lines l ON l.journal_entry_id = e.id
      JOIN accounts a ON a.code = l.account_code
      WHERE e.reference_type = 'repair_service'
        AND l.account_code = '4100'
        AND e.entry_date >= ? AND e.entry_date < ?
      ORDER BY e.entry_date ASC, e.id ASC
    ''', [
      _date(from),
      _date(to.add(const Duration(days: 1))),
    ]);
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
