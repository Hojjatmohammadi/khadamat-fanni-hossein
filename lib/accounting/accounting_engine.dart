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
    final clauses = <String>['l.party_type = ?', 'l.party_id = ?'];
    final args = <Object?>[partyType, partyId];
    if (from != null) { clauses.add('e.occurred_at >= ?'); args.add(from.toIso8601String()); }
    if (to != null) { clauses.add('e.occurred_at < ?'); args.add(to.add(const Duration(days: 1)).toIso8601String()); }
    final rows = await db.rawQuery('''
      SELECT e.id AS entry_id, e.entry_number, e.occurred_at, e.description,
             l.debit, l.credit, l.memo, a.code AS account_code, a.name AS account_name
      FROM journal_lines l
      JOIN journal_entries e ON e.id = l.entry_id
      JOIN accounts a ON a.id = l.account_id
      WHERE ${clauses.join(' AND ')}
      ORDER BY e.occurred_at ASC, e.id ASC, l.id ASC
    ''', args);
    var balance = 0.0;
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
