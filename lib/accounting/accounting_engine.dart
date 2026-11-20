import 'package:sqflite/sqflite.dart';

/// Accounting foundation: immutable, balanced journal entries, party ledgers,
/// trial balance, inventory movements and check register.
class JournalLineInput {
  final int accountId;
  final double debit;
  final double credit;
  final String partyType;
  final int? partyId;
  final String memo;

  const JournalLineInput({
    required this.accountId,
    this.debit = 0,
    this.credit = 0,
    this.partyType = '',
    this.partyId,
    this.memo = '',
  });
}

class AccountingEngine {
  AccountingEngine._();

  static const defaultAccounts = <Map<String, String>>[
    {'code':'1000','name':'صندوق','type':'asset'},
    {'code':'1010','name':'بانک','type':'asset'},
    {'code':'1020','name':'چک‌های دریافتنی','type':'asset'},
    {'code':'1100','name':'حساب‌های دریافتنی مشتریان','type':'asset'},
    {'code':'1110','name':'دریافتنی از فروشندگان و سایر اشخاص','type':'asset'},
    {'code':'1200','name':'موجودی کالا','type':'asset'},
    {'code':'2000','name':'حساب‌های پرداختنی فروشندگان','type':'liability'},
    {'code':'2010','name':'اعتبار و بستانکاری مشتریان','type':'liability'},
    {'code':'2110','name':'چک‌های پرداختنی','type':'liability'},
    {'code':'3000','name':'سرمایه','type':'equity'},
    {'code':'4000','name':'فروش کالا','type':'income'},
    {'code':'4010','name':'درآمد اجرت تعمیر','type':'income'},
    {'code':'4100','name':'برگشت از فروش','type':'income'},
    {'code':'4110','name':'تخفیفات فروش','type':'income'},
    {'code':'2200','name':'مالیات بر ارزش افزوده پرداختنی','type':'liability'},
    {'code':'5000','name':'بهای تمام‌شده کالای فروش‌رفته','type':'expense'},
    {'code':'6000','name':'هزینه‌های جاری','type':'expense'},
    {'code':'6010','name':'هزینه حمل و خرید','type':'expense'},
  ];

  static Future<void> createTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        type TEXT NOT NULL CHECK(type IN ('asset','liability','equity','income','expense')),
        is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0,1)),
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS journal_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entry_number TEXT NOT NULL UNIQUE,
        occurred_at TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        source_type TEXT NOT NULL DEFAULT 'manual',
        source_id TEXT,
        reversal_of INTEGER,
        created_at TEXT NOT NULL,
        FOREIGN KEY(reversal_of) REFERENCES journal_entries(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS journal_lines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entry_id INTEGER NOT NULL,
        account_id INTEGER NOT NULL,
        debit REAL NOT NULL DEFAULT 0 CHECK(debit >= 0),
        credit REAL NOT NULL DEFAULT 0 CHECK(credit >= 0),
        party_type TEXT NOT NULL DEFAULT '',
        party_id INTEGER,
        memo TEXT NOT NULL DEFAULT '',
        CHECK((debit > 0 AND credit = 0) OR (credit > 0 AND debit = 0)),
        FOREIGN KEY(entry_id) REFERENCES journal_entries(id) ON DELETE RESTRICT,
        FOREIGN KEY(account_id) REFERENCES accounts(id) ON DELETE RESTRICT
      )
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS journal_source_unique
      ON journal_entries(source_type, source_id) WHERE source_id IS NOT NULL
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS journal_date_idx ON journal_entries(occurred_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS journal_lines_account_idx ON journal_lines(account_id, entry_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS journal_lines_party_idx ON journal_lines(party_type, party_id, entry_id)');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS stock_movements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        movement_type TEXT NOT NULL,
        quantity_delta REAL NOT NULL CHECK(quantity_delta != 0),
        unit_cost REAL NOT NULL DEFAULT 0 CHECK(unit_cost >= 0),
        total_cost REAL NOT NULL DEFAULT 0 CHECK(total_cost >= 0),
        reference_type TEXT NOT NULL DEFAULT '',
        reference_id TEXT,
        occurred_at TEXT NOT NULL,
        notes TEXT NOT NULL DEFAULT '',
        FOREIGN KEY(product_id) REFERENCES products(id) ON DELETE RESTRICT
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS stock_movements_product_date_idx ON stock_movements(product_id, occurred_at, id)');
    await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS stock_movement_reference_unique ON stock_movements(reference_type, reference_id, product_id) WHERE reference_id IS NOT NULL');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS checks_register (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        check_number TEXT NOT NULL,
        direction TEXT NOT NULL CHECK(direction IN ('received','issued')),
        party_type TEXT NOT NULL DEFAULT '',
        party_id INTEGER,
        party_name_snapshot TEXT NOT NULL DEFAULT '',
        amount REAL NOT NULL CHECK(amount > 0),
        issue_date TEXT NOT NULL,
        due_date TEXT NOT NULL,
        status TEXT NOT NULL CHECK(status IN ('pending','deposited','cashed','spent','bounced','cancelled')),
        bank_name TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '',
        source_type TEXT NOT NULL DEFAULT '',
        source_id TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS checks_due_status_idx ON checks_register(due_date, status)');
    await db.execute('CREATE INDEX IF NOT EXISTS checks_party_idx ON checks_register(party_type, party_id)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS checks_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        check_id INTEGER NOT NULL,
        old_status TEXT NOT NULL DEFAULT '',
        new_status TEXT NOT NULL,
        occurred_at TEXT NOT NULL,
        notes TEXT NOT NULL DEFAULT '',
        FOREIGN KEY(check_id) REFERENCES checks_register(id) ON DELETE RESTRICT
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS checks_history_check_idx ON checks_history(check_id, occurred_at, id)');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS document_returns (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        original_category TEXT NOT NULL CHECK(original_category IN ('sales','operations')),
        original_source_id INTEGER NOT NULL,
        product_id INTEGER,
        line_index INTEGER NOT NULL DEFAULT 0,
        quantity REAL NOT NULL DEFAULT 0 CHECK(quantity >= 0),
        amount REAL NOT NULL CHECK(amount > 0),
        reason TEXT NOT NULL DEFAULT '',
        occurred_at TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY(product_id) REFERENCES products(id) ON DELETE RESTRICT
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS document_returns_source_idx ON document_returns(original_category, original_source_id, occurred_at)');
  }

  /// Adds invoice-line identity for installations created before schema v12.
  static Future<void> ensureReturnLineIndexColumn(DatabaseExecutor db) async {
    final columns = await db.rawQuery('PRAGMA table_info(document_returns)');
    final names = columns.map((row) => row['name'].toString()).toSet();
    if (!names.contains('line_index')) {
      await db.execute('ALTER TABLE document_returns ADD COLUMN line_index INTEGER NOT NULL DEFAULT 0');
    }
  }

  static Future<void> ensureDefaultAccounts(DatabaseExecutor db) async {
    final now = DateTime.now().toIso8601String();
    for (final account in defaultAccounts) {
      await db.insert('accounts', {
        ...account,
        'created_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  /// Posts a permanent double-entry document. Source identity prevents the
  /// same invoice/payment from being posted twice.
  static Future<int> accountId(DatabaseExecutor db, String code) async {
    final rows = await db.query('accounts', columns: ['id'], where: 'code = ? AND is_active = 1', whereArgs: [code], limit: 1);
    if (rows.isEmpty) throw StateError('حساب با کد ' + code + ' در دفتر کل تعریف نشده است.');
    return rows.first['id'] as int;
  }

  static Future<int> postJournal(
    Database db, {
    required String entryNumber,
    required DateTime occurredAt,
    required String description,
    required String sourceType,
    String? sourceId,
    required List<JournalLineInput> lines,
    int? reversalOf,
  }) {
    return db.transaction((txn) => postJournalInTransaction(
      txn,
      entryNumber: entryNumber,
      occurredAt: occurredAt,
      description: description,
      sourceType: sourceType,
      sourceId: sourceId,
      lines: lines,
      reversalOf: reversalOf,
    ));
  }

  /// Posts a balanced immutable entry inside an existing SQLite transaction.
  /// This lets stock, invoice and ledger changes either all commit or all roll back.
  static Future<int> postJournalInTransaction(
    DatabaseExecutor db, {
    required String entryNumber,
    required DateTime occurredAt,
    required String description,
    required String sourceType,
    String? sourceId,
    required List<JournalLineInput> lines,
    int? reversalOf,
  }) async {
    if (entryNumber.trim().isEmpty || sourceType.trim().isEmpty || lines.length < 2) {
      throw ArgumentError('شماره سند، نوع سند و حداقل دو ردیف حسابداری لازم است.');
    }
    var debitTotal = 0.0;
    var creditTotal = 0.0;
    for (final line in lines) {
      if (!line.debit.isFinite || !line.credit.isFinite ||
          line.debit < 0 || line.credit < 0 ||
          (line.debit > 0 && line.credit > 0) ||
          (line.debit == 0 && line.credit == 0)) {
        throw ArgumentError('مبلغ بدهکار یا بستانکار هر ردیف نامعتبر است.');
      }
      debitTotal += line.debit;
      creditTotal += line.credit;
    }
    if ((debitTotal - creditTotal).abs() > 0.01) {
      throw StateError('سند حسابداری تراز نیست؛ جمع بدهکار و بستانکار باید برابر باشد.');
    }
    for (final line in lines) {
      final account = await db.query('accounts', columns: ['id','is_active'],
        where: 'id = ?', whereArgs: [line.accountId], limit: 1);
      if (account.isEmpty || account.first['is_active'] != 1) {
        throw StateError('حساب انتخاب‌شده وجود ندارد یا غیرفعال است.');
      }
    }
    final entryId = await db.insert('journal_entries', {
      'entry_number': entryNumber.trim(),
      'occurred_at': occurredAt.toIso8601String(),
      'description': description.trim(),
      'source_type': sourceType,
      'source_id': sourceId,
      'reversal_of': reversalOf,
      'created_at': DateTime.now().toIso8601String(),
    });
    for (final line in lines) {
      await db.insert('journal_lines', {
        'entry_id': entryId,
        'account_id': line.accountId,
        'debit': line.debit,
        'credit': line.credit,
        'party_type': line.partyType,
        'party_id': line.partyId,
        'memo': line.memo,
      });
    }
    return entryId;
  }

  /// Returns chronological party activity with a running debit-minus-credit balance.
  static Future<List<Map<String, Object?>>> partyLedger(
    DatabaseExecutor db, {
    required String partyType,
    required int partyId,
    DateTime? from,
    DateTime? to,
  }) async {
    final partyWhere = 'l.party_type = ? AND l.party_id = ?';
    final partyArgs = <Object?>[partyType, partyId];

    // A date-filtered ledger must carry forward the balance accumulated before
    // the selected period; otherwise the first displayed balance is misleading.
    var balance = 0.0;
    if (from != null) {
      final openingRows = await db.rawQuery('''
        SELECT COALESCE(SUM(l.debit), 0) AS debit_total,
               COALESCE(SUM(l.credit), 0) AS credit_total
        FROM journal_lines l
        JOIN journal_entries e ON e.id = l.entry_id
        WHERE $partyWhere AND e.occurred_at < ?
      ''', [...partyArgs, from.toIso8601String()]);
      balance = (openingRows.first['debit_total'] as num).toDouble() -
          (openingRows.first['credit_total'] as num).toDouble();
    }

    final clauses = <String>[partyWhere];
    final args = <Object?>[...partyArgs];
    if (from != null) {
      clauses.add('e.occurred_at >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      clauses.add('e.occurred_at < ?');
      args.add(to.add(const Duration(days: 1)).toIso8601String());
    }
    final rows = await db.rawQuery('''
      SELECT e.id AS entry_id, e.entry_number, e.occurred_at, e.description,
             l.debit, l.credit, l.memo, a.code AS account_code, a.name AS account_name
      FROM journal_lines l
      JOIN journal_entries e ON e.id = l.entry_id
      JOIN accounts a ON a.id = l.account_id
      WHERE ${clauses.join(' AND ')}
      ORDER BY e.occurred_at ASC, e.id ASC, l.id ASC
    ''', args);
    return rows.map((row) {
      balance += (row['debit'] as num).toDouble() - (row['credit'] as num).toDouble();
      return <String, Object?>{...row, 'running_balance': balance};
    }).toList();
  }

  static Future<List<Map<String, Object?>>> trialBalance(DatabaseExecutor db) async {
    return db.rawQuery('''
      SELECT a.id, a.code, a.name, a.type,
             COALESCE(SUM(l.debit), 0) AS debit_total,
             COALESCE(SUM(l.credit), 0) AS credit_total,
             COALESCE(SUM(l.debit), 0) - COALESCE(SUM(l.credit), 0) AS net_balance
      FROM accounts a
      LEFT JOIN journal_lines l ON l.account_id = a.id
      WHERE a.is_active = 1
      GROUP BY a.id, a.code, a.name, a.type
      ORDER BY a.code
    ''');
  }

  /// Adds an inventory movement and updates the normalized product quantity
  /// in the same transaction. Negative stock is rejected unless explicitly allowed.
  static Future<int> recordStockMovement(
    Database db, {
    required int productId,
    required String movementType,
    required double quantityDelta,
    double unitCost = 0,
    String referenceType = '',
    String? referenceId,
    String notes = '',
    bool allowNegative = false,
    DateTime? occurredAt,
  }) {
    return db.transaction((txn) => recordStockMovementInTransaction(
      txn,
      productId: productId,
      movementType: movementType,
      quantityDelta: quantityDelta,
      unitCost: unitCost,
      referenceType: referenceType,
      referenceId: referenceId,
      notes: notes,
      allowNegative: allowNegative,
      occurredAt: occurredAt,
    ));
  }

  /// Applies a stock movement inside the caller's transaction.
  static Future<int> recordStockMovementInTransaction(
    DatabaseExecutor txn, {
    required int productId,
    required String movementType,
    required double quantityDelta,
    double unitCost = 0,
    String referenceType = '',
    String? referenceId,
    String notes = '',
    bool allowNegative = false,
    DateTime? occurredAt,
  }) async {
    if (!quantityDelta.isFinite || !unitCost.isFinite ||
        quantityDelta == 0 || unitCost < 0) {
      throw ArgumentError('مقدار گردش باید غیرصفر و بهای واحد نامنفی باشد.');
    }
    final products = await txn.query('products', columns: ['quantity'],
      where: 'id = ?', whereArgs: [productId], limit: 1);
    if (products.isEmpty) throw StateError('کالای موردنظر پیدا نشد.');
    final current = (products.first['quantity'] as num).toDouble();
    final next = current + quantityDelta;
    if (!allowNegative && next < -0.000001) {
      throw StateError('موجودی کافی نیست؛ ثبت خروجی بیشتر از موجودی مجاز نیست.');
    }
    final id = await txn.insert('stock_movements', {
      'product_id': productId,
      'movement_type': movementType,
      'quantity_delta': quantityDelta,
      'unit_cost': unitCost,
      'total_cost': quantityDelta.abs() * unitCost,
      'reference_type': referenceType,
      'reference_id': referenceId,
      'occurred_at': (occurredAt ?? DateTime.now()).toIso8601String(),
      'notes': notes,
    });
    await txn.update('products', {'quantity': next}, where: 'id = ?', whereArgs: [productId]);
    return id;
  }

  /// Posts a sales invoice, its customer balance and stock/COGS movements
  /// atomically. Each product is aggregated so repeated invoice lines cannot
  /// violate the unique movement reference or decrement stock twice.
  static Future<void> postSaleInTransaction(
    DatabaseExecutor txn, {
    required String entryNumber,
    required String sourceId,
    required DateTime occurredAt,
    required double gross,
    required double discount,
    required double tax,
    required double depositApplied,
    required double received,
    required String paymentMethod,
    required int? customerId,
    required String customerName,
    required List<Map<String, Object?>> productLines,
    int? linkedRepairSourceId,
  }) async {
    final values = [gross, discount, tax, depositApplied, received];
    if (values.any((value) => !value.isFinite || value < 0) ||
        gross <= 0 || discount > gross) {
      throw ArgumentError('مبالغ فاکتور فروش معتبر نیستند.');
    }
    final net = gross - discount + tax;
    if (net <= 0 || depositApplied > net + 0.01) {
      throw ArgumentError('مبلغ نهایی یا بیعانه تخصیص‌یافته معتبر نیست.');
    }

    final receivableAccount = await accountId(txn, '1100');
    final customerCreditAccount = await accountId(txn, '2010');
    final customerHasOpenBalance =
        (net - depositApplied - received).abs() > 0.01;
    if (customerId == null && customerHasOpenBalance) {
      throw StateError(
        'برای فاکتور دارای مانده بدهی یا بستانکاری، ابتدا پرونده مشتری را انتخاب کنید.',
      );
    }
    if (customerId != null) {
      final customer = await txn.query(
        'customers',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [customerId],
        limit: 1,
      );
      if (customer.isEmpty) {
        throw StateError('پرونده مشتری انتخاب‌شده دیگر وجود ندارد؛ مشتری را دوباره انتخاب کنید.');
      }
    }

    if (depositApplied > 0 && customerId == null) {
      throw StateError('برای مصرف بیعانه، پرونده مشتری باید مشخص باشد.');
    }
    var availableCredit = 0.0;
    if (depositApplied > 0) {
      final creditRows = await txn.rawQuery(
        '''SELECT COALESCE(SUM(credit - debit), 0) AS available
           FROM journal_lines
           WHERE account_id = ? AND party_type = 'customer' AND party_id = ?''',
        [customerCreditAccount, customerId],
      );
      availableCredit = (creditRows.first['available'] as num).toDouble()
          .clamp(0, double.infinity).toDouble();
      if (depositApplied > availableCredit + 0.01) {
        throw StateError('اعتبار یا بیعانه قابل استفاده مشتری کافی نیست.');
      }
    }

    // Split product and service revenue from the invoice's line snapshots.
    // This is required to avoid recognizing repair labor twice when the repair
    // intake already posted that labor to the customer's receivable.
    var productRevenue = 0.0;
    var serviceRevenue = 0.0;
    var explicitLineTotals = false;
    var missingLineTotals = false;
    var computedLineRevenue = 0.0;
    final quantitiesByProduct = <int, double>{};
    for (final line in productLines) {
      final productId = int.tryParse((line['product_id'] ?? '').toString());
      final quantityValue = line['quantity'];
      final quantity = quantityValue is num
          ? quantityValue.toDouble()
          : double.tryParse((quantityValue ?? '').toString()) ?? 0;
      if (productId != null) {
        if (!quantity.isFinite || quantity <= 0) {
          throw ArgumentError('تعداد کالای فاکتور معتبر نیست.');
        }
        quantitiesByProduct.update(
          productId,
          (current) => current + quantity,
          ifAbsent: () => quantity,
        );
      }

      final rawLineTotal = line['line_total'];
      if (rawLineTotal == null || rawLineTotal.toString().trim().isEmpty) {
        missingLineTotals = true;
        continue;
      }
      explicitLineTotals = true;
      final lineTotal = rawLineTotal is num
          ? rawLineTotal.toDouble()
          : double.tryParse(rawLineTotal.toString()) ?? double.nan;
      if (!lineTotal.isFinite || lineTotal < 0) {
        throw ArgumentError('مبلغ یکی از ردیف‌های فاکتور معتبر نیست.');
      }
      computedLineRevenue += lineTotal;
      if (productId == null) {
        serviceRevenue += lineTotal;
      } else {
        productRevenue += lineTotal;
      }
    }

    if (productLines.isEmpty) {
      serviceRevenue = gross;
    } else if (missingLineTotals) {
      if (explicitLineTotals || productLines.length != 1) {
        throw StateError('مبلغ ردیف‌های فاکتور برای ثبت حسابداری کامل نیست.');
      }
      final onlyProductId = int.tryParse(
        (productLines.single['product_id'] ?? '').toString(),
      );
      if (onlyProductId == null) {
        serviceRevenue = gross;
      } else {
        productRevenue = gross;
      }
    } else if ((computedLineRevenue - gross).abs() > 0.02) {
      throw StateError('جمع ردیف‌های فاکتور با مبلغ کل برابر نیست.');
    }

    var linkedRepairWageToClear = 0.0;
    if (linkedRepairSourceId != null) {
      final repairRows = await txn.query(
        'repairs',
        columns: ['customer_id', 'labor_cost'],
        where: 'legacy_source_id = ?',
        whereArgs: [linkedRepairSourceId],
        limit: 1,
      );
      if (repairRows.isEmpty) {
        throw StateError('پذیرش تعمیر مرتبط با فاکتور پیدا نشد.');
      }
      final repairCustomerId = repairRows.first['customer_id'] as int?;
      final repairWage = (repairRows.first['labor_cost'] as num).toDouble();
      if (repairWage > 0.01) {
        if (customerId == null || repairCustomerId != customerId) {
          throw StateError('پذیرش تعمیر و فاکتور باید به پرونده یکسان مشتری متصل باشند.');
        }
        if (serviceRevenue + 0.01 < repairWage) {
          throw StateError('مبلغ ردیف‌های خدمت فاکتور باید اجرت پذیرش تعمیر را پوشش دهد.');
        }
        final repairJournal = await txn.query(
          'journal_entries',
          columns: ['id'],
          where: "source_type = 'repair' AND source_id = ?",
          whereArgs: [linkedRepairSourceId.toString()],
          limit: 1,
        );
        if (repairJournal.isEmpty) {
          throw StateError('سند اجرت پذیرش تعمیر در دفتر کل پیدا نشد.');
        }
        linkedRepairWageToClear = repairWage;
      }
    }

    final paymentAccountCode = paymentMethod == 'چک'
        ? '1020'
        : (paymentMethod.contains('کارت') || paymentMethod.contains('حواله'))
            ? '1010'
            : '1000';
    final lines = <JournalLineInput>[];
    if (productRevenue > 0.001) {
      lines.add(JournalLineInput(
        accountId: await accountId(txn, '4000'),
        credit: productRevenue,
        memo: 'فروش قطعات فاکتور ' + entryNumber,
      ));
    }
    final newServiceRevenue = serviceRevenue - linkedRepairWageToClear;
    if (newServiceRevenue > 0.001) {
      lines.add(JournalLineInput(
        accountId: await accountId(txn, '4010'),
        credit: newServiceRevenue,
        memo: 'درآمد خدمات جدید فاکتور ' + entryNumber,
      ));
    }
    if (linkedRepairWageToClear > 0.001) {
      lines.add(JournalLineInput(
        accountId: receivableAccount,
        credit: linkedRepairWageToClear,
        partyType: 'customer',
        partyId: customerId,
        memo: 'تسویه دریافتنی اجرت پذیرش تعمیر ' + linkedRepairSourceId.toString(),
      ));
    }
    if (discount > 0) {
      lines.add(JournalLineInput(
        accountId: await accountId(txn, '4110'),
        debit: discount,
        memo: 'تخفیف فاکتور ' + entryNumber,
      ));
    }
    if (tax > 0) {
      lines.add(JournalLineInput(
        accountId: await accountId(txn, '2200'),
        credit: tax,
        memo: 'مالیات ارزش افزوده فاکتور ' + entryNumber,
      ));
    }
    if (depositApplied > 0) {
      lines.add(JournalLineInput(
        accountId: customerCreditAccount,
        debit: depositApplied,
        partyType: 'customer',
        partyId: customerId,
        memo: 'مصرف بیعانه قبلی مشتری ' + customerName,
      ));
    }
    if (received > 0) {
      lines.add(JournalLineInput(
        accountId: await accountId(txn, paymentAccountCode),
        debit: received,
        memo: 'دریافت بابت فاکتور ' + entryNumber,
      ));
    }
    final remaining = net - depositApplied - received;
    if (remaining > 0.01) {
      lines.add(JournalLineInput(
        accountId: receivableAccount,
        debit: remaining,
        partyType: customerId == null ? '' : 'customer',
        partyId: customerId,
        memo: 'مانده دریافتنی فاکتور ' + entryNumber,
      ));
    } else if (remaining < -0.01) {
      lines.add(JournalLineInput(
        accountId: customerCreditAccount,
        credit: -remaining,
        partyType: customerId == null ? '' : 'customer',
        partyId: customerId,
        memo: 'اعتبار مازاد پرداخت مشتری در فاکتور ' + entryNumber,
      ));
    }

    var totalCostOfGoods = 0.0;
    for (final entry in quantitiesByProduct.entries) {
      final productRows = await txn.query(
        'products',
        columns: ['purchase_price'],
        where: 'id = ?',
        whereArgs: [entry.key],
        limit: 1,
      );
      if (productRows.isEmpty) throw StateError('کالای فاکتور در انبار پیدا نشد.');
      final fallback = (productRows.first['purchase_price'] as num).toDouble();
      final unitCost = await averageUnitCost(txn, entry.key, fallback: fallback);
      await recordStockMovementInTransaction(
        txn,
        productId: entry.key,
        movementType: 'sale',
        quantityDelta: -entry.value,
        unitCost: unitCost,
        referenceType: 'sale',
        referenceId: sourceId,
        notes: 'خروج کالا بابت فاکتور ' + entryNumber,
        occurredAt: occurredAt,
      );
      totalCostOfGoods += unitCost * entry.value;
    }
    if (totalCostOfGoods > 0.001) {
      lines.add(JournalLineInput(
        accountId: await accountId(txn, '5000'),
        debit: totalCostOfGoods,
        memo: 'بهای تمام‌شده فروش ' + entryNumber,
      ));
      lines.add(JournalLineInput(
        accountId: await accountId(txn, '1200'),
        credit: totalCostOfGoods,
        memo: 'خروج بهای موجودی بابت فروش ' + entryNumber,
      ));
    }

    await postJournalInTransaction(
      txn,
      entryNumber: 'SALE-' + sourceId,
      occurredAt: occurredAt,
      description: 'ثبت فاکتور فروش ' + entryNumber,
      sourceType: 'sale',
      sourceId: sourceId,
      lines: lines,
    );
  }

  /// Calculates moving weighted-average cost from immutable stock movements.
  /// Product master purchase_price is only a fallback for legacy rows without
  /// movement history and is not allowed to rewrite historical unit costs.
  static Future<double> averageUnitCost(
    DatabaseExecutor db,
    int productId, {
    double fallback = 0,
  }) async {
    final rows = await db.rawQuery(
      '''SELECT
           COALESCE(SUM(quantity_delta), 0) AS quantity,
           COALESCE(SUM(CASE WHEN quantity_delta >= 0
             THEN total_cost ELSE -total_cost END), 0) AS value
         FROM stock_movements
         WHERE product_id = ?''',
      [productId],
    );
    final quantity = (rows.first['quantity'] as num).toDouble();
    final value = (rows.first['value'] as num).toDouble();
    if (quantity > 0.000001 && value >= 0 && value.isFinite) {
      return value / quantity;
    }
    return fallback.isFinite && fallback >= 0 ? fallback : 0;
  }

  static Future<List<Map<String, Object?>>> stockCardex(
    DatabaseExecutor db, int productId, {DateTime? from, DateTime? to}
  ) async {
    // Opening balance includes every movement strictly before the selected period.
    var openingBalance = 0.0;
    if (from != null) {
      final openingRows = await db.rawQuery(
        '''SELECT COALESCE(SUM(quantity_delta), 0) AS opening
           FROM stock_movements
           WHERE product_id = ? AND occurred_at < ?''',
        [productId, from.toIso8601String()],
      );
      openingBalance = (openingRows.first['opening'] as num).toDouble();
    }
    final clauses = <String>['product_id = ?'];
    final args = <Object?>[productId];
    if (from != null) {
      clauses.add('occurred_at >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      clauses.add('occurred_at < ?');
      args.add(to.add(const Duration(days: 1)).toIso8601String());
    }
    final rows = await db.query(
      'stock_movements',
      where: clauses.join(' AND '),
      whereArgs: args,
      orderBy: 'occurred_at ASC, id ASC',
    );
    var balance = openingBalance;
    return rows.map((row) {
      balance += (row['quantity_delta'] as num).toDouble();
      return <String, Object?>{
        ...row,
        'opening_quantity': openingBalance,
        'running_quantity': balance,
      };
    }).toList();
  }
}
