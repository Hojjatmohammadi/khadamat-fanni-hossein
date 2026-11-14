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
    if (DateTime.tryParse(reversalDate) == null) {
      throw ArgumentError('تاریخ برگشت سند معتبر نیست');
    }
    if (reason.trim().isEmpty || idempotencyKey.trim().isEmpty) {
      throw ArgumentError('شرح برگشت و کلید یکتا الزامی است');
    }

    final db = await _database.database;
    return db.transaction((txn) async {
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
    });
  }

  Future<List<Map<String, Object?>>> getTrialBalance() async {
    final db = await _database.database;
    final rows = await db.rawQuery('''
      SELECT
        a.code AS account_code,
        a.name AS account_name,
        a.account_type AS account_type,
        COALESCE(SUM(l.debit), 0) AS total_debit,
        COALESCE(SUM(l.credit), 0) AS total_credit
      FROM accounts a
      LEFT JOIN journal_lines l ON l.account_code = a.code
      GROUP BY a.code, a.name, a.account_type
      ORDER BY a.code
    ''');
    return rows.map((row) {
      final debit = (row['total_debit'] as num).toInt();
      final credit = (row['total_credit'] as num).toInt();
      return <String, Object?>{
        ...row,
        'balance_debit_minus_credit': debit - credit,
      };
    }).toList();
  }

  Future<int> recordStockMovement(StockMovementDraft draft) async {
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
    final db = await _database.database;
    return db.transaction((txn) async {
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
}
