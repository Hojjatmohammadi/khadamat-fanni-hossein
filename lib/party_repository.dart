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
}
