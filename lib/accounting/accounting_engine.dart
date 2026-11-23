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

  /// Validates cheque status transitions before any accounting entry is posted.
  /// A cleared cheque can later be marked bounced, but must not be cancelled:
  /// cancellation is only valid before bank settlement.
  static void validateCheckStatusTransition({
    required String direction,
    required String oldStatus,
    required String nextStatus,
  }) {
    const transitions = <String, Map<String, Set<String>>>{
      'received': {
        'pending': {'deposited', 'cashed', 'bounced', 'cancelled'},
        'deposited': {'cashed', 'bounced', 'cancelled'},
        'cashed': {'bounced'},
      },
      'issued': {
        'pending': {'spent', 'bounced', 'cancelled'},
        'spent': {'bounced'},
      },
    };

    if (!(transitions[direction]?[oldStatus]?.contains(nextStatus) ?? false)) {
      throw StateError(
        'تغییر وضعیت انتخاب‌شده مجاز نیست. چک وصول‌شده فقط در صورت برگشت بانکی قابل اصلاح است و وضعیت‌های نهایی قابل بازگشت نیستند.',
      );
    }
  }



  /// Prevents a return from being posted while its originating cheque can
  /// still settle. A sale return is blocked by received cheques; a purchase
  /// return is blocked by issued cheques. Cancelled, bounced, cashed or spent
  /// cheques do not block the return.
  static Future<void> ensureNoOutstandingChecksForReturn(
    DatabaseExecutor txn, {
    required String originalCategory,
    required int originalSourceId,
  }) async {
    if (!['sales', 'operations'].contains(originalCategory)) {
      throw ArgumentError('نوع سند برای کنترل چک‌های برگشت معتبر نیست.');
    }
    final isSale = originalCategory == 'sales';
    final rows = await txn.query(
      'checks_register',
      columns: ['check_number'],
      where: "source_type = ? AND source_id = ? AND direction = ? AND status IN ('pending','deposited')",
      whereArgs: [
        isSale ? 'sale' : 'purchase',
        originalSourceId.toString(),
        isSale ? 'received' : 'issued',
      ],
      orderBy: 'id ASC',
      limit: 5,
    );
    if (rows.isEmpty) return;
    final numbers = rows
        .map((row) => (row['check_number'] ?? '').toString())
        .where((number) => number.isNotEmpty)
        .join('، ');
    if (isSale) {
      throw StateError(
        'برای برگشت این فروش، ابتدا چک‌های دریافتی در انتظار را باطل یا تعیین‌تکلیف کنید: ' +
            numbers,
      );
    }
    throw StateError(
      'برای برگشت این خرید، ابتدا چک‌های پرداختی در انتظار را لغو یا تعیین‌تکلیف کنید: ' +
          numbers,
    );
  }

  /// Atomically changes a cheque status, posts its accounting consequence,
  /// and appends the immutable status history record.
  ///
  /// The expected status protects against stale UI selections and concurrent
  /// edits. Call this from inside the database transaction that owns the change.
  static Future<void> transitionCheckStatusInTransaction(
    DatabaseExecutor txn, {
    required int checkId,
    required String expectedOldStatus,
    required String nextStatus,
    required DateTime occurredAt,
  }) async {
    final checkRows = await txn.query(
      'checks_register',
      where: 'id = ?',
      whereArgs: [checkId],
      limit: 1,
    );
    if (checkRows.isEmpty) throw StateError('چک موردنظر پیدا نشد.');
    final check = checkRows.first;
    final oldStatus = (check['status'] ?? '').toString();
    if (oldStatus != expectedOldStatus) {
      throw StateError('وضعیت چک تغییر کرده است؛ فهرست را تازه‌سازی کنید.');
    }

    final direction = (check['direction'] ?? '').toString();
    final amount = (check['amount'] as num).toDouble();
    final sourceType = (check['source_type'] ?? '').toString();
    final sourceId = (check['source_id'] ?? '').toString();
    final rawPartyType = (check['party_type'] ?? '').toString();
    final partyType = rawPartyType == 'مشتری'
        ? 'customer'
        : rawPartyType == 'فروشنده'
            ? 'supplier'
            : rawPartyType;
    final partyId = check['party_id'] as int?;

    validateCheckStatusTransition(
      direction: direction,
      oldStatus: oldStatus,
      nextStatus: nextStatus,
    );

    final lines = <JournalLineInput>[];
    Future<int> accountIdFor(String code) => accountId(txn, code);
    final isReceived = direction == 'received';

    if (isReceived && nextStatus == 'cashed') {
      lines.add(JournalLineInput(
        accountId: await accountIdFor('1010'),
        debit: amount,
        memo: 'وصول چک دریافتی شماره ' + (check['check_number'] ?? '').toString(),
      ));
      lines.add(JournalLineInput(
        accountId: await accountIdFor('1020'),
        credit: amount,
        memo: 'انتقال چک دریافتی به بانک',
      ));
    } else if (!isReceived && nextStatus == 'spent') {
      lines.add(JournalLineInput(
        accountId: await accountIdFor('2110'),
        debit: amount,
        partyType: partyType,
        partyId: partyId,
        memo: 'تسویه چک پرداختی شماره ' + (check['check_number'] ?? '').toString(),
      ));
      lines.add(JournalLineInput(
        accountId: await accountIdFor('1010'),
        credit: amount,
        memo: 'کسر وجه بابت چک پرداختی',
      ));
    } else if (nextStatus == 'bounced' || nextStatus == 'cancelled') {
      if (sourceType.isEmpty || sourceId.isEmpty) {
        throw StateError('این چک از نسخهٔ قدیمی است و به سند اولیه متصل نیست؛ برای جلوگیری از ثبت حسابداری اشتباه، ابتدا سوابق آن باید تطبیق داده شود.');
      }
      final origin = await txn.query(
        'journal_entries',
        columns: ['id'],
        where: 'source_type = ? AND source_id = ?',
        whereArgs: [sourceType, sourceId],
        limit: 1,
      );
      if (origin.isEmpty) {
        throw StateError('سند حسابداری اصلی چک پیدا نشد؛ وضعیت تغییر نکرد.');
      }
      final originId = origin.first['id'] as int;
      final originLines = await txn.rawQuery(
        '''SELECT a.code, l.debit, l.credit, l.party_type, l.party_id
           FROM journal_lines l
           JOIN accounts a ON a.id = l.account_id
           WHERE l.entry_id = ?
           ORDER BY l.id''',
        [originId],
      );
      final statusAccount = isReceived
          ? (oldStatus == 'cashed' ? '1010' : '1020')
          : (oldStatus == 'spent' ? '1010' : '2110');

      if (isReceived) {
        var remaining = amount;
        if (sourceType == 'sale') {
          final creditRows = originLines.where((row) =>
            row['code'] == '2010' && (row['credit'] as num).toDouble() > 0).toList();
          for (final row in creditRows) {
            if (remaining <= 0.0001) break;
            final value = (row['credit'] as num).toDouble().clamp(0, remaining).toDouble();
            lines.add(JournalLineInput(
              accountId: await accountIdFor('2010'),
              debit: value,
              partyType: 'customer',
              partyId: partyId,
              memo: 'برگشت اعتبار ناشی از چک برگشتی',
            ));
            remaining -= value;
          }
          if (remaining > 0.0001) {
            final contra = partyType == 'customer' ? '1100' : '1110';
            lines.add(JournalLineInput(
              accountId: await accountIdFor(contra),
              debit: remaining,
              partyType: partyType == 'customer' ? 'customer' : partyType,
              partyId: partyId,
              memo: 'ایجاد مجدد بدهی بابت چک برگشتی',
            ));
          }
        } else {
          var reversed = 0.0;
          for (final row in originLines) {
            final credit = (row['credit'] as num).toDouble();
            final code = (row['code'] ?? '').toString();
            if (credit <= 0 || ['1000','1010','1020','2110'].contains(code)) continue;
            final value = credit.clamp(0, amount - reversed).toDouble();
            if (value <= 0.0001) continue;
            lines.add(JournalLineInput(
              accountId: await accountIdFor(code),
              debit: value,
              partyType: (row['party_type'] ?? '').toString(),
              partyId: row['party_id'] as int?,
              memo: 'برگشت ثبت طرف حساب بابت چک برگشتی',
            ));
            reversed += value;
            if (reversed >= amount - 0.0001) break;
          }
          if (reversed + 0.0001 < amount) {
            final fallback = partyType == 'customer' ? '1100'
                : partyType == 'supplier' ? '1110' : '4000';
            lines.add(JournalLineInput(
              accountId: await accountIdFor(fallback),
              debit: amount - reversed,
              partyType: partyType,
              partyId: partyId,
              memo: 'اصلاح مانده طرف حساب بابت چک برگشتی',
            ));
          }
        }
        lines.add(JournalLineInput(
          accountId: await accountIdFor(statusAccount),
          credit: amount,
          memo: 'خروج چک دریافتی از چرخه وصول',
        ));
      } else {
        var reversed = 0.0;
        final contraRows = <Map<String, Object?>>[];
        if (sourceType == 'purchase') {
          contraRows.add({
            'code': '2000',
            'amount': amount,
            'party_type': 'supplier',
            'party_id': partyId,
          });
        } else {
          for (final row in originLines) {
            final debit = (row['debit'] as num).toDouble();
            final code = (row['code'] ?? '').toString();
            if (debit <= 0 || ['1000','1010','1020','2110','1200'].contains(code)) continue;
            final value = debit.clamp(0, amount - reversed).toDouble();
            if (value <= 0.0001) continue;
            contraRows.add({
              'code': code,
              'amount': value,
              'party_type': row['party_type'],
              'party_id': row['party_id'],
            });
            reversed += value;
            if (reversed >= amount - 0.0001) break;
          }
          if (reversed + 0.0001 < amount) {
            throw StateError('مبلغ ردیف‌های سند اصلی با مبلغ چک برابر نیست؛ وضعیت تغییر نکرد.');
          }
        }
        // An uncashed issued cheque is reclassified back to the original
        // payable/expense. A bounced cheque after clearing also restores cash.
        lines.add(JournalLineInput(
          accountId: await accountIdFor(statusAccount),
          debit: amount,
          partyType: partyType,
          partyId: partyId,
          memo: 'برگشت / ابطال چک پرداختی',
        ));
        for (final row in contraRows) {
          lines.add(JournalLineInput(
            accountId: await accountIdFor(row['code'].toString()),
            credit: (row['amount'] as num).toDouble(),
            partyType: (row['party_type'] ?? '').toString(),
            partyId: row['party_id'] as int?,
            memo: 'بازگشت بدهی بابت چک برگشتی',
          ));
        }
      }
    }

    if (lines.isNotEmpty) {
      await postJournalInTransaction(
        txn,
        entryNumber: 'CHECK-' + checkId.toString() + '-' + nextStatus,
        occurredAt: occurredAt,
        description: 'تغییر وضعیت چک ' + (check['check_number'] ?? '').toString(),
        sourceType: 'check_status',
        sourceId: checkId.toString() + ':' + nextStatus,
        lines: lines,
      );
    }

    await txn.update(
      'checks_register',
      {'status': nextStatus},
      where: 'id = ?',
      whereArgs: [checkId],
    );
    await txn.insert('checks_history', {
      'check_id': checkId,
      'old_status': oldStatus,
      'new_status': nextStatus,
      'occurred_at': occurredAt.toIso8601String(),
      'notes': lines.isEmpty
          ? 'تغییر وضعیت امانی بدون اثر مالی'
          : 'تغییر وضعیت همراه با ثبت دفتر کل',
    });
  }

  /// Parses user-entered amounts that may contain Persian/Arabic digits
  /// and locale-specific grouping or decimal separators.
  /// Builds a non-posting history row for a fully normalized invoice.
  /// Its zero debit/credit keeps invoice visibility separate from balances:
  /// the journal remains the only source of financial movement totals.
  static Map<String, Object?> invoiceHistoryRow({
    required DateTime date,
    required String invoiceNumber,
    required double gross,
    required double discount,
    required double tax,
    required double received,
    required double depositApplied,
    required String paymentMethod,
  }) {
    String amount(double value) => value.toStringAsFixed(0);
    final details = <String>[
      'مبلغ ${amount(gross)}',
      if (discount > 0) 'تخفیف ${amount(discount)}',
      if (tax > 0) 'مالیات ${amount(tax)}',
      if (received > 0) 'دریافتی ${amount(received)}',
      if (depositApplied > 0) 'بیعانه مصرف‌شده ${amount(depositApplied)}',
    ];
    return <String, Object?>{
      'date': date,
      'description': 'خلاصه فاکتور فروش ${invoiceNumber.trim().isEmpty ? 'بدون شماره' : invoiceNumber.trim()} — ${details.join('، ')}',
      'method': paymentMethod,
      'debit': 0.0,
      'credit': 0.0,
      'is_history_only': true,
    };
  }

  /// Maps legacy party operations to the same debit/credit direction used
  /// by historical journal migration. Supplier receipts reduce our receivable
  /// (1110), while payments to suppliers reduce payables or create advances.
  /// Allocates a supplier purchase return against the remaining payable first.
  /// Any excess is either refunded in cash or kept as a supplier receivable.
  static Map<String, double> supplierReturnSettlementAmounts({
    required double returnAmount,
    required double outstandingPayable,
    required bool settleAsCash,
  }) {
    if (!returnAmount.isFinite || returnAmount <= 0 ||
        !outstandingPayable.isFinite || outstandingPayable < 0) {
      throw ArgumentError('مبلغ برگشت یا بدهی فروشنده معتبر نیست.');
    }
    final payableReduction = outstandingPayable.clamp(0.0, returnAmount).toDouble();
    final remainder = (returnAmount - payableReduction).clamp(0.0, returnAmount).toDouble();
    return <String, double>{
      'payable_reduction': payableReduction,
      'cash_refund': settleAsCash ? remainder : 0.0,
      'supplier_receivable': settleAsCash ? 0.0 : remainder,
    };
  }

  static Map<String, double> legacyPartyOperationAmounts({
    required String partyType,
    required String operation,
    required double amount,
    double paid = 0,
  }) {
    if (!amount.isFinite || amount <= 0) {
      return <String, double>{'debit': 0, 'credit': 0};
    }
    if (partyType == 'فروشنده') {
      if (operation == 'خرید کالا') {
        final safePaid = paid.isFinite ? paid.clamp(0.0, amount).toDouble() : 0.0;
        return <String, double>{'debit': safePaid, 'credit': amount};
      }
      final debit = <String>{
        'متفرقه شخص بدهکار',
        'پرداخت وجه',
        'تخفیف گرفتن',
      }.contains(operation) ? amount : 0.0;
      final credit = <String>{
        'متفرقه شخص بستانکار',
        'دریافت وجه',
      }.contains(operation) ? amount : 0.0;
      return <String, double>{'debit': debit, 'credit': credit};
    }
    final debit = <String>{
      'متفرقه شخص بدهکار',
      'پرداخت وجه',
    }.contains(operation) ? amount : 0.0;
    final credit = <String>{
      'متفرقه شخص بستانکار',
      'دریافت وجه',
      'ثبت بیعانه',
      'تخفیف دادن',
    }.contains(operation) ? amount : 0.0;
    return <String, double>{'debit': debit, 'credit': credit};
  }

  static double parseLocalizedAmount(Object? raw) {
    var value = (raw ?? '').toString().trim();
    const persianDigits = '۰۱۲۳۴۵۶۷۸۹';
    const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
    for (var i = 0; i < 10; i++) {
      value = value
          .replaceAll(persianDigits[i], i.toString())
          .replaceAll(arabicDigits[i], i.toString());
    }
    value = value
        .replaceAll('٬', '')
        .replaceAll(',', '')
        .replaceAll('،', '')
        .replaceAll('\u00A0', '')
        .replaceAll(' ', '')
        .replaceAll('٫', '.');
    return double.tryParse(value) ?? 0;
  }

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
  /// Ensures customer deposits are linked to a real customer record so
  /// the credit can be allocated to that customer's future invoices.
  static void validateDepositParty({
    required String partyType,
    required int? partyId,
  }) {
    if (partyType != 'مشتری') {
      throw StateError('بیعانه فقط برای مشتری قابل ثبت است.');
    }
    if (partyId == null || partyId <= 0) {
      throw StateError('برای ثبت بیعانه، ابتدا پرونده مشتری را انتخاب یا ثبت کنید.');
    }
  }

  static Future<List<Map<String, Object?>>> partyLedger(
    DatabaseExecutor db, {
    required String partyType,
    required int partyId,
    DateTime? from,
    DateTime? to,
    List<String> accountCodes = const [],
  }) async {
    final partyWhere = 'l.party_type = ? AND l.party_id = ?';
    final partyArgs = <Object?>[partyType, partyId];
    final codes = accountCodes.map((code) => code.trim()).where((code) => code.isNotEmpty).toList();
    final accountFilter = codes.isEmpty
        ? ''
        : ' AND a.code IN (${List.filled(codes.length, '?').join(',')})';

    // A date-filtered ledger must carry forward the balance accumulated before
    // the selected period; otherwise the first displayed balance is misleading.
    var balance = 0.0;
    if (from != null) {
      // A date-only filter starts at midnight even if the caller supplies a time.
      final fromInclusive = DateTime(from.year, from.month, from.day);
      final openingRows = await db.rawQuery('''
        SELECT COALESCE(SUM(l.debit), 0) AS debit_total,
               COALESCE(SUM(l.credit), 0) AS credit_total
        FROM journal_lines l
        JOIN journal_entries e ON e.id = l.entry_id
        JOIN accounts a ON a.id = l.account_id
        WHERE $partyWhere AND e.occurred_at < ?$accountFilter
      ''', [...partyArgs, fromInclusive.toIso8601String(), ...codes]);
      balance = (openingRows.first['debit_total'] as num).toDouble() -
          (openingRows.first['credit_total'] as num).toDouble();
    }

    final clauses = <String>[partyWhere];
    final args = <Object?>[...partyArgs];
    if (from != null) {
      final fromInclusive = DateTime(from.year, from.month, from.day);
      clauses.add('e.occurred_at >= ?');
      args.add(fromInclusive.toIso8601String());
    }
    if (to != null) {
      // Treat `to` as an inclusive calendar date, regardless of the time
      // component supplied by a date picker or caller.
      final toExclusive = DateTime(to.year, to.month, to.day + 1);
      clauses.add('e.occurred_at < ?');
      args.add(toExclusive.toIso8601String());
    }
    if (codes.isNotEmpty) {
      clauses.add('a.code IN (${List.filled(codes.length, '?').join(',')})');
      args.addAll(codes);
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

  /// Calculates moving weighted-average cost from immutable stock movements.
  /// Product master purchase_price is only a fallback for legacy rows without
  /// movement history and is not allowed to rewrite historical unit costs.
  static Future<double> averageUnitCost(
    DatabaseExecutor db,
    int productId, {
    double fallback = 0,
    DateTime? asOf,
  }) async {
    final rows = await db.rawQuery(
      '''SELECT
           COALESCE(SUM(quantity_delta), 0) AS quantity,
           COALESCE(SUM(CASE WHEN quantity_delta >= 0
             THEN total_cost ELSE -total_cost END), 0) AS value
         FROM stock_movements
         WHERE product_id = ? AND (? IS NULL OR occurred_at <= ?)''',
      [productId, asOf?.toIso8601String(), asOf?.toIso8601String()],
    );
    final quantity = (rows.first['quantity'] as num).toDouble();
    final value = (rows.first['value'] as num).toDouble();
    if (quantity > 0.000001 && value >= 0 && value.isFinite) {
      return value / quantity;
    }
    return fallback.isFinite && fallback >= 0 ? fallback : 0;
  }

  /// Returns the stock balance available at a historical invoice date.
  /// Later purchases are excluded so a backdated sale cannot consume future stock.
  static Future<double> stockQuantityAt(
    DatabaseExecutor db,
    int productId, {
    required DateTime asOf,
  }) async {
    final rows = await db.rawQuery(
      '''SELECT COALESCE(SUM(quantity_delta), 0) AS quantity
         FROM stock_movements
         WHERE product_id = ? AND occurred_at <= ?''',
      [productId, asOf.toIso8601String()],
    );
    return (rows.first['quantity'] as num).toDouble();
  }

  static Future<List<Map<String, Object?>>> stockCardex(
    DatabaseExecutor db, int productId, {DateTime? from, DateTime? to}
  ) async {
    // Opening balance includes every movement strictly before the selected period.
    var openingBalance = 0.0;
    if (from != null) {
      // Preserve the full opening balance before the selected calendar day.
      final fromInclusive = DateTime(from.year, from.month, from.day);
      final openingRows = await db.rawQuery(
        '''SELECT COALESCE(SUM(quantity_delta), 0) AS opening
           FROM stock_movements
           WHERE product_id = ? AND occurred_at < ?''',
        [productId, fromInclusive.toIso8601String()],
      );
      openingBalance = (openingRows.first['opening'] as num).toDouble();
    }
    final clauses = <String>['product_id = ?'];
    final args = <Object?>[productId];
    if (from != null) {
      final fromInclusive = DateTime(from.year, from.month, from.day);
      clauses.add('occurred_at >= ?');
      args.add(fromInclusive.toIso8601String());
    }
    if (to != null) {
      // Include the entire selected calendar day, not the following day.
      final toExclusive = DateTime(to.year, to.month, to.day + 1);
      clauses.add('occurred_at < ?');
      args.add(toExclusive.toIso8601String());
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
