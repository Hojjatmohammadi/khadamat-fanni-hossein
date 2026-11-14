import 'app_database.dart';

class PartyDraft {
  const PartyDraft({
    required this.partyType,
    required this.displayName,
    this.preferredId,
    this.phone,
    this.address,
    this.notes,
    this.sourceCategory,
    this.sourceId,
  });

  final String partyType;
  final String displayName;
  final String? preferredId;
  final String? phone;
  final String? address;
  final String? notes;
  final String? sourceCategory;
  final String? sourceId;
}

class PartyRepository {
  PartyRepository(this._database);

  final AppDatabase _database;

  Future<String> ensureParty(PartyDraft draft) async {
    final type = draft.partyType.trim();
    final name = draft.displayName.trim();
    if (!const {'customer', 'supplier', 'other'}.contains(type) || name.isEmpty) {
      throw ArgumentError('نوع یا نام طرف حساب معتبر نیست');
    }
    final normalized = name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final db = await _database.database;

    return db.transaction((txn) async {
      if (draft.preferredId != null && draft.preferredId!.trim().isNotEmpty) {
        final byId = await txn.query(
          'parties',
          where: 'id = ?',
          whereArgs: [draft.preferredId],
          limit: 1,
        );
        if (byId.isNotEmpty) return draft.preferredId!;
      }

      if (draft.preferredId?.trim().isEmpty != false) {
        final existing = await txn.query(
          'parties',
          where: 'party_type = ? AND normalized_name = ?',
          whereArgs: [type, normalized],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          final id = existing.single['id'] as String;
          await txn.update(
            'parties',
            {
              if (draft.phone != null) 'phone': draft.phone,
              if (draft.address != null) 'address': draft.address,
              if (draft.notes != null) 'notes': draft.notes,
              'updated_at': DateTime.now().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [id],
          );
          return id;
        }
      }

      final id = draft.preferredId?.trim().isNotEmpty == true
          ? draft.preferredId!.trim()
          : '${type}_${DateTime.now().microsecondsSinceEpoch}';
      final now = DateTime.now().toIso8601String();
      await txn.insert('parties', {
        'id': id,
        'party_type': type,
        'display_name': name,
        'normalized_name': normalized,
        'phone': draft.phone,
        'address': draft.address,
        'notes': draft.notes,
        'source_category': draft.sourceCategory,
        'source_id': draft.sourceId,
        'created_at': now,
        'updated_at': now,
      });
      return id;
    });
  }

  Future<List<Map<String, Object?>>> getParties({String? partyType}) async {
    final db = await _database.database;
    return db.query(
      'parties',
      where: partyType == null ? null : 'party_type = ?',
      whereArgs: partyType == null ? null : [partyType],
      orderBy: 'display_name COLLATE NOCASE ASC',
    );
  }

  Future<Map<String, Object?>> getPartyStatement(String partyId) async {
    final db = await _database.database;
    final parties = await db.query(
      'parties',
      where: 'id = ?',
      whereArgs: [partyId],
      limit: 1,
    );
    if (parties.isEmpty) throw StateError('طرف حساب پیدا نشد');

    final party = parties.single;
    final rawLines = await db.rawQuery('''
      SELECT
        e.id AS journal_entry_id,
        e.entry_date,
        e.description,
        e.reference_type,
        e.reference_id,
        l.id AS line_id,
        l.account_code,
        a.name AS account_name,
        l.debit,
        l.credit,
        l.memo
      FROM journal_lines l
      INNER JOIN journal_entries e ON e.id = l.journal_entry_id
      INNER JOIN accounts a ON a.code = l.account_code
      WHERE l.party_id = ?
      ORDER BY e.entry_date ASC, e.id ASC, l.line_no ASC
    ''', [partyId]);

    var debitTotal = 0;
    var creditTotal = 0;
    var runningDebitMinusCredit = 0;
    final statement = <Map<String, Object?>>[];

    for (final row in rawLines) {
      final debit = (row['debit'] as num).toInt();
      final credit = (row['credit'] as num).toInt();
      debitTotal += debit;
      creditTotal += credit;
      runningDebitMinusCredit += debit - credit;
      final balance = party['party_type'] == 'supplier'
          ? -runningDebitMinusCredit
          : runningDebitMinusCredit;
      statement.add({
        ...row,
        'running_balance': balance,
        'balance_label': balance > 0
            ? (party['party_type'] == 'supplier' ? 'بستانکار' : 'بدهکار')
            : balance < 0
                ? (party['party_type'] == 'supplier' ? 'بدهکار' : 'بستانکار')
                : 'تسویه',
      });
    }

    final closingBalance = party['party_type'] == 'supplier'
        ? creditTotal - debitTotal
        : debitTotal - creditTotal;

    return {
      'party': party,
      'lines': statement,
      'total_debit': debitTotal,
      'total_credit': creditTotal,
      'closing_balance': closingBalance,
      'closing_label': closingBalance > 0
          ? (party['party_type'] == 'supplier' ? 'طلب فروشنده' : 'بدهی مشتری')
          : closingBalance < 0
              ? (party['party_type'] == 'supplier' ? 'بدهی فروشنده' : 'طلب مشتری')
              : 'تسویه',
    };
  }

  /// Loads a bounded page of a party ledger without materializing the full
  /// history. The opening balance includes all postings before [fromDate].
  /// Dates use ISO yyyy-MM-dd and [toDate] is inclusive.
  Future<Map<String, Object?>> getPartyStatementPage(
    String partyId, {
    String? fromDate,
    String? toDate,
    int limit = 100,
    int offset = 0,
  }) async {
    if (partyId.trim().isEmpty || limit < 1 || limit > 500 || offset < 0) {
      throw ArgumentError('شناسه طرف حساب یا محدوده صفحه معتبر نیست');
    }
    DateTime? from;
    DateTime? toExclusive;
    if (fromDate != null) {
      from = DateTime.tryParse(fromDate);
      if (from == null || from.toIso8601String().substring(0, 10) != fromDate) {
        throw ArgumentError('تاریخ شروع معتبر نیست');
      }
    }
    if (toDate != null) {
      final parsed = DateTime.tryParse(toDate);
      if (parsed == null || parsed.toIso8601String().substring(0, 10) != toDate) {
        throw ArgumentError('تاریخ پایان معتبر نیست');
      }
      toExclusive = parsed.add(const Duration(days: 1));
    }
    if (from != null && toExclusive != null && !toExclusive.isAfter(from)) {
      throw ArgumentError('بازه تاریخ نامعتبر است');
    }

    final db = await _database.database;
    final parties = await db.query(
      'parties',
      where: 'id = ?',
      whereArgs: [partyId],
      limit: 1,
    );
    if (parties.isEmpty) throw StateError('طرف حساب پیدا نشد');
    final party = parties.single;
    final isSupplier = party['party_type'] == 'supplier';

    final totals = await db.rawQuery('''
      SELECT COALESCE(SUM(l.debit), 0) AS total_debit,
        COALESCE(SUM(l.credit), 0) AS total_credit
      FROM journal_lines l
      WHERE l.party_id = ?
    ''', [partyId]);
    final totalDebit = (totals.single['total_debit'] as num).toInt();
    final totalCredit = (totals.single['total_credit'] as num).toInt();
    final rawClosing = totalDebit - totalCredit;
    final closingBalance = isSupplier ? -rawClosing : rawClosing;

    var openingRaw = 0;
    if (fromDate != null) {
      final opening = await db.rawQuery('''
        SELECT COALESCE(SUM(l.debit - l.credit), 0) AS balance
        FROM journal_lines l
        JOIN journal_entries e ON e.id = l.journal_entry_id
        WHERE l.party_id = ? AND e.entry_date < ?
      ''', [partyId, fromDate]);
      openingRaw = (opening.single['balance'] as num).toInt();
    }
    var runningRaw = openingRaw;

    final filters = <String>['l.party_id = ?'];
    final args = <Object?>[partyId];
    if (fromDate != null) {
      filters.add('e.entry_date >= ?');
      args.add(fromDate);
    }
    if (toExclusive != null) {
      filters.add('e.entry_date < ?');
      args.add(toExclusive.toIso8601String().substring(0, 10));
    }
    if (offset > 0) {
      final priorRows = await db.rawQuery('''
        SELECT COALESCE(SUM(prior.debit - prior.credit), 0) AS balance
        FROM (
          SELECT l.debit, l.credit
          FROM journal_lines l
          JOIN journal_entries e ON e.id = l.journal_entry_id
          WHERE ${filters.join(' AND ')}
          ORDER BY e.entry_date ASC, e.id ASC, l.line_no ASC
          LIMIT ?
        ) AS prior
      ''', [...args, offset]);
      runningRaw += (priorRows.single['balance'] as num).toInt();
    }

    final rows = await db.rawQuery('''
      SELECT e.id AS journal_entry_id, e.entry_date, e.description,
        e.reference_type, e.reference_id, l.id AS line_id, l.account_code,
        a.name AS account_name, l.debit, l.credit, l.memo
      FROM journal_lines l
      JOIN journal_entries e ON e.id = l.journal_entry_id
      JOIN accounts a ON a.code = l.account_code
      WHERE ${filters.join(' AND ')}
      ORDER BY e.entry_date ASC, e.id ASC, l.line_no ASC
      LIMIT ? OFFSET ?
    ''', [...args, limit, offset]);

    final lines = <Map<String, Object?>>[];
    for (final row in rows) {
      runningRaw += (row['debit'] as num).toInt() -
          (row['credit'] as num).toInt();
      final balance = isSupplier ? -runningRaw : runningRaw;
      lines.add({
        ...row,
        'running_balance': balance,
        'balance_label': balance > 0
            ? (isSupplier ? 'بستانکار' : 'بدهکار')
            : balance < 0
                ? (isSupplier ? 'بدهکار' : 'بستانکار')
                : 'تسویه',
      });
    }
    final pageCount = await db.rawQuery('''
      SELECT COUNT(*) AS line_count
      FROM journal_lines l
      JOIN journal_entries e ON e.id = l.journal_entry_id
      WHERE ${filters.join(' AND ')}
    ''', args);
    final totalLines = (pageCount.single['line_count'] as num).toInt();
    final nextOffset = offset + rows.length;
    return {
      'party': party,
      'lines': lines,
      'total_debit': totalDebit,
      'total_credit': totalCredit,
      'opening_balance': isSupplier ? -openingRaw : openingRaw,
      'closing_balance': closingBalance,
      'closing_label': closingBalance > 0
          ? (isSupplier ? 'طلب فروشنده' : 'بدهی مشتری')
          : closingBalance < 0
              ? (isSupplier ? 'بدهی فروشنده' : 'طلب مشتری')
              : 'تسویه',
      'total_lines': totalLines,
      'offset': offset,
      'next_offset': nextOffset,
      'has_more': nextOffset < totalLines,
    };
  }

}
