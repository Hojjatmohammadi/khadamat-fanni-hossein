import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

/// A single side of a double-entry journal line. Amounts are whole Tomans.
class JournalLineDraft {
  const JournalLineDraft({
    required this.accountCode,
    this.debit = 0,
    this.credit = 0,
    this.partyId,
    this.memo,
  });

  final String accountCode;
  final int debit;
  final int credit;
  final String? partyId;
  final String? memo;

  Map<String, Object?> toJson() => {
        'accountCode': accountCode,
        'debit': debit,
        'credit': credit,
        'partyId': partyId,
        'memo': memo,
      };
}

/// A posted journal entry. Entries are immutable; corrections use reversals.
class JournalEntryDraft {
  const JournalEntryDraft({
    required this.entryDate,
    required this.description,
    required this.idempotencyKey,
    required this.lines,
    this.referenceType,
    this.referenceId,
    this.reversalOfId,
  });

  final String entryDate;
  final String description;
  final String idempotencyKey;
  final List<JournalLineDraft> lines;
  final String? referenceType;
  final String? referenceId;
  final int? reversalOfId;

  Map<String, Object?> toPayload() => {
        'entryDate': entryDate,
        'description': description,
        'idempotencyKey': idempotencyKey,
        'referenceType': referenceType,
        'referenceId': referenceId,
        'reversalOfId': reversalOfId,
        'lines': lines.map((line) => line.toJson()).toList(),
      };
}

/// A signed inventory quantity change. Positive means stock in; negative means
/// stock out. A journal entry can be posted in the same SQLite transaction.
class StockMovementDraft {
  const StockMovementDraft({
    required this.productId,
    required this.movementType,
    required this.quantityDelta,
    required this.unitCost,
    required this.occurredAt,
    required this.idempotencyKey,
    this.referenceType,
    this.referenceId,
    this.journalEntry,
    this.allowNegativeStock = false,
  });

  final int productId;
  final String movementType;
  final double quantityDelta;
  final int unitCost;
  final String occurredAt;
  final String idempotencyKey;
  final String? referenceType;
  final String? referenceId;
  final JournalEntryDraft? journalEntry;
  final bool allowNegativeStock;

  Map<String, Object?> toPayload() => {
        'productId': productId,
        'movementType': movementType,
        'quantityDelta': quantityDelta,
        'unitCost': unitCost,
        'occurredAt': occurredAt,
        'referenceType': referenceType,
        'referenceId': referenceId,
        'journalEntry': journalEntry?.toPayload(),
        'allowNegativeStock': allowNegativeStock,
      };
}

class AccountingRepository {
  AccountingRepository(this._database);

  final AppDatabase _database;

  static const Set<String> _movementTypes = {
    'opening_balance',
    'purchase',
    'sale',
    'repair_consumption',
    'customer_return',
    'supplier_return',
    'adjustment',
  };

  Future<int> postJournalEntry(JournalEntryDraft draft) async {
    final db = await _database.database;
    return db.transaction((txn) => _postJournalEntry(txn, draft));
  }

  Future<int> _postJournalEntry(
    DatabaseExecutor txn,
    JournalEntryDraft draft,
  ) async {
    _validateJournalDraft(draft);
    final payloadJson = jsonEncode(draft.toPayload());

    final previous = await txn.query(
      'journal_entries',
      where: 'idempotency_key = ?',
      whereArgs: [draft.idempotencyKey],
      limit: 1,
    );
    if (previous.isNotEmpty) {
      if (previous.single['payload_json'] != payloadJson) {
        throw StateError('کلید جلوگیری از ثبت تکراری با اطلاعات دیگری استفاده شده است');
      }
      return previous.single['id'] as int;
    }

    final accountRows = await txn.query(
      'accounts',
      columns: ['code'],
      where: 'code IN (' + List.filled(draft.lines.length, '?').join(',') + ')',
      whereArgs: draft.lines.map((line) => line.accountCode).toList(),
    );
    final availableAccounts = accountRows.map((row) => row['code']).toSet();
    for (final line in draft.lines) {
      if (!availableAccounts.contains(line.accountCode)) {
        throw ArgumentError('کد حساب تعریف نشده است: ' + line.accountCode);
      }
    }

    final now = DateTime.now().toIso8601String();
    final entryId = await txn.insert('journal_entries', {
      'entry_date': draft.entryDate,
      'description': draft.description.trim(),
      'reference_type': draft.referenceType,
      'reference_id': draft.referenceId,
      'idempotency_key': draft.idempotencyKey,
      'payload_json': payloadJson,
      'reversal_of_id': draft.reversalOfId,
      'created_at': now,
    });

    for (var i = 0; i < draft.lines.length; i++) {
      final line = draft.lines[i];
      await txn.insert('journal_lines', {
        'journal_entry_id': entryId,
        'line_no': i + 1,
        'account_code': line.accountCode,
        'debit': line.debit,
        'credit': line.credit,
        'party_id': line.partyId,
        'memo': line.memo,
      });
    }
    return entryId;
  }

  void _validateJournalDraft(JournalEntryDraft draft) {
    if (draft.idempotencyKey.trim().isEmpty) {
      throw ArgumentError('کلید یکتای ثبت حسابداری الزامی است');
    }
    if (draft.description.trim().isEmpty) {
      throw ArgumentError('شرح سند حسابداری الزامی است');
    }
    if (DateTime.tryParse(draft.entryDate) == null) {
      throw ArgumentError('تاریخ سند حسابداری معتبر نیست');
    }
    if (draft.lines.length < 2) {
      throw ArgumentError('سند حسابداری باید حداقل دو سطر داشته باشد');
    }

    var totalDebit = 0;
    var totalCredit = 0;
    for (final line in draft.lines) {
      if (line.accountCode.trim().isEmpty || line.debit < 0 || line.credit < 0) {
        throw ArgumentError('اطلاعات سطر سند حسابداری معتبر نیست');
      }
      final hasDebit = line.debit > 0;
      final hasCredit = line.credit > 0;
      if (hasDebit == hasCredit) {
        throw ArgumentError('هر سطر باید فقط بدهکار یا فقط بستانکار باشد');
      }
      totalDebit += line.debit;
      totalCredit += line.credit;
    }
    if (totalDebit <= 0 || totalDebit != totalCredit) {
      throw StateError('جمع بدهکار و بستانکار سند باید برابر و بیشتر از صفر باشد');
    }
  }

  /// Creates an equal-and-opposite entry. The original entry is never edited.
  Future<int> reverseJournalEntry({
    required int journalEntryId,
    required String reversalDate,
    required String reason,
    required String idempotencyKey,
  }) async {
    final db = await _database.database;
    return db.transaction((txn) => reverseJournalEntryInTransaction(
          txn,
          journalEntryId: journalEntryId,
          reversalDate: reversalDate,
          reason: reason,
          idempotencyKey: idempotencyKey,
        ));
  }

  Future<int> reverseJournalEntryInTransaction(
    DatabaseExecutor txn, {
    required int journalEntryId,
    required String reversalDate,
    required String reason,
    required String idempotencyKey,
  }) async {
    if (DateTime.tryParse(reversalDate) == null) {
      throw ArgumentError('تاریخ برگشت سند معتبر نیست');
    }
    if (reason.trim().isEmpty || idempotencyKey.trim().isEmpty) {
      throw ArgumentError('شرح برگشت و کلید یکتا الزامی است');
    }

    final existingReversal = await txn.query(
      'journal_entries',
      columns: ['id'],
      where: 'reversal_of_id = ?',
      whereArgs: [journalEntryId],
      limit: 1,
    );
    if (existingReversal.isNotEmpty) {
      return existingReversal.single['id'] as int;
    }

    final originals = await txn.query(
      'journal_entries',
      where: 'id = ?',
      whereArgs: [journalEntryId],
      limit: 1,
    );
    if (originals.isEmpty) {
      throw StateError('سند حسابداری موردنظر پیدا نشد');
    }
    if (originals.single['reversal_of_id'] != null) {
      throw StateError('سند برگشت را نمی‌توان دوباره برگشت زد');
    }

    final originalLines = await txn.query(
      'journal_lines',
      where: 'journal_entry_id = ?',
      whereArgs: [journalEntryId],
      orderBy: 'line_no ASC',
    );
    final lines = originalLines.map((line) {
      return JournalLineDraft(
        accountCode: line['account_code'] as String,
        debit: line['credit'] as int,
        credit: line['debit'] as int,
        partyId: line['party_id'] as String?,
        memo: line['memo'] as String?,
      );
    }).toList();

    final draft = JournalEntryDraft(
      entryDate: reversalDate,
      description: 'برگشت سند ' + journalEntryId.toString() + ': ' + reason.trim(),
      idempotencyKey: idempotencyKey,
      referenceType: 'journal_reversal',
      referenceId: journalEntryId.toString(),
      reversalOfId: journalEntryId,
      lines: lines,
    );
    return _postJournalEntry(txn, draft);
  }

  Future<List<Map<String, Object?>>> getTrialBalance({
    String? fromDate,
    String? toDate,
  }) async {
    final db = await _database.database;
    final filters = <String>[];
    final args = <Object?>[];
    if (fromDate != null) { filters.add('e.entry_date >= ?'); args.add(fromDate); }
    if (toDate != null) { filters.add('e.entry_date < ?'); args.add(DateTime.parse(toDate).add(const Duration(days: 1)).toIso8601String().substring(0, 10)); }
    final dateJoin = filters.isEmpty ? '' : ' AND ${filters.join(' AND ')}';
    final rows = await db.rawQuery('''
      SELECT a.code AS account_code, a.name AS account_name,
        a.account_type AS account_type,
        COALESCE(SUM(CASE WHEN e.id IS NOT NULL THEN l.debit ELSE 0 END), 0) AS total_debit,
        COALESCE(SUM(CASE WHEN e.id IS NOT NULL THEN l.credit ELSE 0 END), 0) AS total_credit
      FROM accounts a
      LEFT JOIN journal_lines l ON l.account_code = a.code
      LEFT JOIN journal_entries e ON e.id = l.journal_entry_id$dateJoin
      GROUP BY a.code, a.name, a.account_type
      ORDER BY a.code
    ''', args);
    return rows.map((row) {
      final debit = (row['total_debit'] as num).toInt();
      final credit = (row['total_credit'] as num).toInt();
      return <String, Object?>{
        ...row,
        'balance_debit_minus_credit': debit - credit,
      };
    }).toList();
  }

  Future<int> postJournalEntryInTransaction(
    DatabaseExecutor txn,
    JournalEntryDraft draft,
  ) {
    return _postJournalEntry(txn, draft);
  }

  Future<int> recordStockMovement(StockMovementDraft draft) async {
    final db = await _database.database;
    return db.transaction((txn) => recordStockMovementInTransaction(txn, draft));
  }

  Future<int> recordStockMovementInTransaction(
    DatabaseExecutor txn,
    StockMovementDraft draft,
  ) async {
    if (draft.productId <= 0 ||
        !_movementTypes.contains(draft.movementType) ||
        !draft.quantityDelta.isFinite ||
        draft.quantityDelta == 0 ||
        draft.unitCost < 0 ||
        draft.idempotencyKey.trim().isEmpty ||
        DateTime.tryParse(draft.occurredAt) == null) {
      throw ArgumentError('اطلاعات گردش انبار معتبر نیست');
    }
    if (draft.movementType == 'sale' ||
        draft.movementType == 'repair_consumption' ||
        draft.movementType == 'supplier_return') {
      if (draft.quantityDelta >= 0) {
        throw ArgumentError('مقدار خروج از انبار باید منفی باشد');
      }
    }
    if (draft.movementType == 'purchase' ||
        draft.movementType == 'customer_return' ||
        draft.movementType == 'opening_balance') {
      if (draft.quantityDelta <= 0) {
        throw ArgumentError('مقدار ورود به انبار باید مثبت باشد');
      }
    }

    final payloadJson = jsonEncode(draft.toPayload());
    final duplicate = await txn.query(
      'inventory_movements',
      where: 'idempotency_key = ?',
      whereArgs: [draft.idempotencyKey],
      limit: 1,
    );
    if (duplicate.isNotEmpty) {
      if (duplicate.single['payload_json'] != payloadJson) {
        throw StateError('کلید جلوگیری از ثبت تکراری برای گردش دیگری استفاده شده است');
      }
      return duplicate.single['id'] as int;
    }

    final product = await txn.query(
      'products',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [draft.productId],
      limit: 1,
    );
    if (product.isEmpty) {
      throw StateError('کالای مربوط به گردش انبار پیدا نشد');
    }

    final stockRows = await txn.rawQuery(
      'SELECT COALESCE(SUM(quantity_delta), 0) AS quantity '
      'FROM inventory_movements WHERE product_id = ?',
      [draft.productId],
    );
    final currentQuantity = (stockRows.single['quantity'] as num).toDouble();
    final nextQuantity = currentQuantity + draft.quantityDelta;
    if (!draft.allowNegativeStock && nextQuantity < -0.0000001) {
      throw StateError('موجودی کافی نیست؛ موجودی فعلی: ' + currentQuantity.toString());
    }

    int? journalEntryId;
    if (draft.journalEntry != null) {
      journalEntryId = await _postJournalEntry(txn, draft.journalEntry!);
    }

    final now = DateTime.now().toIso8601String();
    return txn.insert('inventory_movements', {
      'product_id': draft.productId,
      'movement_type': draft.movementType,
      'quantity_delta': draft.quantityDelta,
      'unit_cost': draft.unitCost,
      'total_cost': (draft.quantityDelta.abs() * draft.unitCost).round(),
      'occurred_at': draft.occurredAt,
      'reference_type': draft.referenceType,
      'reference_id': draft.referenceId,
      'idempotency_key': draft.idempotencyKey,
      'payload_json': payloadJson,
      'journal_entry_id': journalEntryId,
      'created_at': now,
    });
  }

  Future<double> getStockOnHand(int productId) {
    return _database.getStockOnHand(productId);
  }

  Future<List<Map<String, Object?>>> getStockMovements(int productId) async {
    final db = await _database.database;
    return db.query(
      'inventory_movements',
      where: 'product_id = ?',
      whereArgs: [productId],
      orderBy: 'occurred_at ASC, id ASC',
    );
  }

  /// Expense is posted immediately as a balanced, immutable journal entry.
  Future<int> recordExpense({
    required String expenseDate,
    required String description,
    required int amount,
    required String expenseAccountCode,
    required String cashAccountCode,
    required String idempotencyKey,
  }) async {
    if (DateTime.tryParse(expenseDate) == null ||
        description.trim().isEmpty ||
        amount <= 0 ||
        idempotencyKey.trim().isEmpty) {
      throw ArgumentError('تاریخ، شرح، مبلغ و شناسه یکتای هزینه الزامی است');
    }
    final db = await _database.database;
    final accounts = await db.query('accounts',
      columns: ['code', 'account_type'],
      where: 'code IN (?, ?)',
      whereArgs: [expenseAccountCode, cashAccountCode]);
    if (accounts.length != 2 ||
        !accounts.any((a) => a['code'] == expenseAccountCode && a['account_type'] == 'expense') ||
        !accounts.any((a) => a['code'] == cashAccountCode && a['account_type'] == 'asset' &&
          (cashAccountCode == '1000' || cashAccountCode == '1010'))) {
      throw ArgumentError('حساب هزینه یا صندوق/بانک معتبر نیست');
    }
    return postJournalEntry(JournalEntryDraft(
      entryDate: expenseDate,
      description: 'هزینه: ${description.trim()}',
      idempotencyKey: idempotencyKey,
      referenceType: 'expense',
      referenceId: idempotencyKey,
      lines: [
        JournalLineDraft(accountCode: expenseAccountCode, debit: amount, memo: description.trim()),
        JournalLineDraft(accountCode: cashAccountCode, credit: amount, memo: description.trim()),
      ],
    ));
  }


  /// Snapshot the difference between the bank statement and the book balance.
  /// A positive difference means the statement balance is higher than the books.
  Future<int> createBankReconciliation({
    required String accountCode,
    required String statementDate,
    required int statementBalance,
    String? note,
    required String idempotencyKey,
  }) async {
    final parsedDate = DateTime.tryParse(statementDate);
    if (parsedDate == null ||
        parsedDate.toIso8601String().substring(0, 10) != statementDate ||
        statementBalance < 0 ||
        idempotencyKey.trim().isEmpty) {
      throw ArgumentError('تاریخ، مانده صورت‌حساب و شناسه تطبیق معتبر نیست');
    }
    if (accountCode != '1000' && accountCode != '1010') {
      throw ArgumentError('تطبیق فقط برای حساب صندوق یا بانک امکان‌پذیر است');
    }
    final db = await _database.database;
    final account = await db.query('accounts',
      columns: ['code', 'account_type'],
      where: 'code = ?', whereArgs: [accountCode], limit: 1);
    if (account.isEmpty || account.single['account_type'] != 'asset') {
      throw ArgumentError('حساب صندوق یا بانک معتبر نیست');
    }
    final balanceRows = await db.rawQuery('''
      SELECT COALESCE(SUM(l.debit), 0) AS debit,
        COALESCE(SUM(l.credit), 0) AS credit
      FROM journal_lines l
      JOIN journal_entries e ON e.id = l.journal_entry_id
      WHERE l.account_code = ? AND e.entry_date <= ?
    ''', [accountCode, statementDate]);
    final bookBalance = (balanceRows.single['debit'] as num).toInt() -
        (balanceRows.single['credit'] as num).toInt();
    final difference = statementBalance - bookBalance;
    final payload = jsonEncode({
      'accountCode': accountCode,
      'statementDate': statementDate,
      'statementBalance': statementBalance,
      'bookBalance': bookBalance,
      'difference': difference,
      'note': note?.trim(),
      'idempotencyKey': idempotencyKey,
    });
    return db.transaction((txn) async {
      final duplicate = await txn.query('bank_reconciliations',
        where: 'idempotency_key = ?', whereArgs: [idempotencyKey], limit: 1);
      if (duplicate.isNotEmpty) {
        if (duplicate.single['payload_json'] == payload) {
          return duplicate.single['id'] as int;
        }
        throw StateError('شناسه تطبیق قبلاً برای اطلاعات دیگری استفاده شده است');
      }
      return txn.insert('bank_reconciliations', {
        'account_code': accountCode,
        'statement_date': statementDate,
        'statement_balance': statementBalance,
        'book_balance': bookBalance,
        'difference': difference,
        'note': note?.trim(),
        'idempotency_key': idempotencyKey,
        'payload_json': payload,
        'created_at': DateTime.now().toIso8601String(),
      });
    });
  }

  Future<List<Map<String, Object?>>> getBankReconciliations({
    String? accountCode,
  }) async {
    final db = await _database.database;
    return db.query('bank_reconciliations',
      where: accountCode == null ? null : 'account_code = ?',
      whereArgs: accountCode == null ? null : [accountCode],
      orderBy: 'statement_date DESC, id DESC');
  }

  Future<List<Map<String, Object?>>> getAccounts() async {
    final db = await _database.database;
    return db.query('accounts', orderBy: 'code ASC');
  }

  Future<List<Map<String, Object?>>> getJournalEntries({
    String? fromDate,
    String? toDate,
  }) async {
    final db = await _database.database;
    final clauses = <String>[];
    final args = <Object?>[];
    if (fromDate != null) { clauses.add('entry_date >= ?'); args.add(fromDate); }
    if (toDate != null) {
      clauses.add('entry_date < ?');
      args.add(DateTime.parse(toDate).add(const Duration(days: 1)).toIso8601String().substring(0, 10));
    }
    final entries = await db.query('journal_entries',
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'entry_date DESC, id DESC');
    final result = <Map<String, Object?>>[];
    for (final entry in entries) {
      final lines = await db.rawQuery('''
        SELECT l.*, a.name AS account_name
        FROM journal_lines l JOIN accounts a ON a.code = l.account_code
        WHERE l.journal_entry_id = ? ORDER BY l.line_no ASC
      ''', [entry['id']]);
      result.add({...entry, 'lines': lines});
    }
    return result;
  }

  Future<Map<String, Object?>> getAccountLedger(
    String accountCode, {String? fromDate, String? toDate}) async {
    final db = await _database.database;
    final accounts = await db.query('accounts', where: 'code = ?', whereArgs: [accountCode], limit: 1);
    if (accounts.isEmpty) throw StateError('حساب پیدا نشد');
    final before = fromDate == null ? <Map<String, Object?>>[] : await db.rawQuery('''
      SELECT COALESCE(SUM(l.debit),0) AS debit, COALESCE(SUM(l.credit),0) AS credit
      FROM journal_lines l JOIN journal_entries e ON e.id=l.journal_entry_id
      WHERE l.account_code=? AND e.entry_date < ?
    ''', [accountCode, fromDate]);
    var running = before.isEmpty ? 0 :
      (before.single['debit'] as num).toInt() - (before.single['credit'] as num).toInt();
    final clauses = <String>['l.account_code = ?'];
    final args = <Object?>[accountCode];
    if (fromDate != null) { clauses.add('e.entry_date >= ?'); args.add(fromDate); }
    if (toDate != null) {
      clauses.add('e.entry_date < ?');
      args.add(DateTime.parse(toDate).add(const Duration(days: 1)).toIso8601String().substring(0, 10));
    }
    final rows = await db.rawQuery('''
      SELECT e.id AS entry_id, e.entry_date, e.description, e.reference_type,
        l.line_no, l.debit, l.credit, l.party_id, l.memo
      FROM journal_lines l JOIN journal_entries e ON e.id=l.journal_entry_id
      WHERE ${clauses.join(' AND ')}
      ORDER BY e.entry_date ASC, e.id ASC, l.line_no ASC
    ''', args);
    final lines = <Map<String, Object?>>[];
    for (final row in rows) {
      running += (row['debit'] as num).toInt() - (row['credit'] as num).toInt();
      lines.add({...row, 'running_balance': running});
    }
    return {'account': accounts.single, 'opening_balance': before.isEmpty ? 0 : running - rows.fold<int>(0, (s,r) => s + (r['debit'] as num).toInt() - (r['credit'] as num).toInt()), 'lines': lines, 'closing_balance': running};
  }

}
