import 'dart:convert';

import 'package:sqflite/sqflite.dart';

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
    this.additionalRoles = const [],
  });

  final String partyType;
  final String displayName;
  final String? preferredId;
  final String? phone;
  final String? address;
  final String? notes;
  final String? sourceCategory;
  final String? sourceId;
  final List<String> additionalRoles;
}

class PartyRepository {
  PartyRepository(this._database);

  final AppDatabase _database;

  static const _validRoles = {'customer', 'supplier', 'other'};

  static String _normalizeName(String value) => value
      .trim()
      .replaceAll('ي', 'ی')
      .replaceAll('ك', 'ک')
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ');

  static String _normalizePhone(String value) {
    var digits = value
        .replaceAll('۰', '0')
        .replaceAll('۱', '1')
        .replaceAll('۲', '2')
        .replaceAll('۳', '3')
        .replaceAll('۴', '4')
        .replaceAll('۵', '5')
        .replaceAll('۶', '6')
        .replaceAll('۷', '7')
        .replaceAll('۸', '8')
        .replaceAll('۹', '9')
        .replaceAll('٠', '0')
        .replaceAll('١', '1')
        .replaceAll('٢', '2')
        .replaceAll('٣', '3')
        .replaceAll('٤', '4')
        .replaceAll('٥', '5')
        .replaceAll('٦', '6')
        .replaceAll('٧', '7')
        .replaceAll('٨', '8')
        .replaceAll('٩', '9')
        .replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('0098') && digits.length == 14) {
      digits = '0${digits.substring(4)}';
    } else if (digits.startsWith('98') && digits.length == 12) {
      digits = '0${digits.substring(2)}';
    }
    return digits;
  }

  Future<void> _addRoles(
    DatabaseExecutor executor,
    String partyId,
    Iterable<String> roles,
  ) async {
    final createdAt = DateTime.now().toIso8601String();
    for (final role in roles) {
      await executor.execute(
        'INSERT OR IGNORE INTO party_roles (party_id, role, created_at) VALUES (?, ?, ?)',
        [partyId, role, createdAt],
      );
    }
  }

  Future<String> ensureParty(PartyDraft draft) async {
    final type = draft.partyType.trim();
    final name = draft.displayName.trim();
    final roles = <String>{type, ...draft.additionalRoles.map((role) => role.trim())};
    if (name.isEmpty || roles.any((role) => !_validRoles.contains(role))) {
      throw ArgumentError('نام یا نقش طرف حساب معتبر نیست');
    }

    final normalized = _normalizeName(name);
    final normalizedPhone = _normalizePhone(draft.phone ?? '');
    if ((draft.phone?.trim().isNotEmpty ?? false) && normalizedPhone.length != 11) {
      throw ArgumentError('شماره همراه باید دقیقاً ۱۱ رقم باشد.');
    }
    final db = await _database.database;

    return db.transaction((txn) async {
      Map<String, Object?>? existing;

      final preferredId = draft.preferredId?.trim();
      if (preferredId != null && preferredId.isNotEmpty) {
        final byId = await txn.query(
          'parties',
          where: 'id = ?',
          whereArgs: [preferredId],
          limit: 1,
        );
        if (byId.isNotEmpty) existing = byId.single;
      }

      // A matching name and normalized phone identify the same person even
      // when that person is first registered as a customer and later as a
      // supplier. Name-only matches remain role-scoped to avoid merging
      // unrelated people who share a name.
      if (existing == null &&
          (preferredId == null || preferredId.isEmpty) &&
          normalizedPhone.isNotEmpty) {
        final phoneCandidates = await txn.query(
          'parties',
          where: 'phone IS NOT NULL',
        );
        for (final candidate in phoneCandidates) {
          if (_normalizePhone(candidate['phone']?.toString() ?? '') ==
                  normalizedPhone &&
              _normalizeName(candidate['display_name']?.toString() ?? '') ==
                  normalized) {
            existing = candidate;
            break;
          }
        }
      }

      if (existing == null && (preferredId == null || preferredId.isEmpty)) {
        final sameRole = await txn.query(
          'parties',
          where: 'party_type = ? AND normalized_name = ?',
          whereArgs: [type, normalized],
        );
        for (final candidate in sameRole) {
          final existingPhone = _normalizePhone(
            candidate['phone']?.toString() ?? '',
          );
          if (normalizedPhone.isNotEmpty &&
              existingPhone.isNotEmpty &&
              existingPhone != normalizedPhone) {
            continue;
          }
          existing = candidate;
          break;
        }
      }

      final now = DateTime.now().toIso8601String();
      if (existing != null) {
        final id = existing['id'] as String;
        await txn.update(
          'parties',
          {
            if (draft.phone != null && draft.phone!.trim().isNotEmpty)
              'phone': draft.phone!.trim(),
            if (draft.address != null) 'address': draft.address,
            if (draft.notes != null) 'notes': draft.notes,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        await _addRoles(txn, id, roles);
        return id;
      }

      final id = preferredId != null && preferredId.isNotEmpty
          ? preferredId
          : '${type}_${DateTime.now().microsecondsSinceEpoch}';
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
      await _addRoles(txn, id, roles);
      return id;
    });
  }

  Future<void> updateParty({
    required String partyId,
    required PartyDraft draft,
  }) async {
    final name = draft.displayName.trim();
    final roles = <String>{
      draft.partyType.trim(),
      ...draft.additionalRoles.map((role) => role.trim()),
    };
    if (partyId.trim().isEmpty ||
        name.isEmpty ||
        roles.isEmpty ||
        roles.any((role) => !_validRoles.contains(role))) {
      throw ArgumentError('اطلاعات مخاطب یا نقش‌های انتخاب‌شده معتبر نیست');
    }

    final normalizedPhone = _normalizePhone(draft.phone ?? '');
    if ((draft.phone?.trim().isNotEmpty ?? false) && normalizedPhone.length != 11) {
      throw ArgumentError('شماره همراه باید دقیقاً ۱۱ رقم باشد.');
    }
    final db = await _database.database;
    await db.transaction((txn) async {
      final existing = await txn.query(
        'parties',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [partyId],
        limit: 1,
      );
      if (existing.isEmpty) throw StateError('مخاطب پیدا نشد');

      await txn.update(
        'parties',
        {
          'party_type': roles.first,
          'display_name': name,
          'normalized_name': _normalizeName(name),
          'phone': normalizedPhone.isEmpty ? null : normalizedPhone,
          'address': draft.address?.trim(),
          'notes': draft.notes?.trim(),
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [partyId],
      );
      await txn.delete(
        'party_roles',
        where: 'party_id = ?',
        whereArgs: [partyId],
      );
      await _addRoles(txn, partyId, roles);
    });
  }

  Future<void> deleteParty(String partyId) async {
    if (partyId.trim().isEmpty) {
      throw ArgumentError('شناسه مخاطب معتبر نیست');
    }
    final db = await _database.database;
    await db.transaction((txn) async {
      final matches = await txn.query(
        'parties',
        columns: ['id', 'display_name', 'source_category', 'source_id'],
        where: 'id = ?',
        whereArgs: [partyId],
        limit: 1,
      );
      if (matches.isEmpty) throw StateError('مخاطب پیدا نشد');

      final linkedChecks = await txn.rawQuery(
        'SELECT COUNT(*) AS total FROM check_records WHERE party_id = ?',
        [partyId],
      );
      final linkedDocuments = await txn.rawQuery(
        'SELECT COUNT(*) AS total FROM business_documents WHERE counterparty_id = ?',
        [partyId],
      );
      final linkedJournal = await txn.rawQuery(
        'SELECT COUNT(*) AS total FROM journal_lines WHERE party_id = ?',
        [partyId],
      );
      final record = matches.single;
      final normalizedPartyName =
          _normalizeName(record['display_name']?.toString() ?? '');
      var linkedRepairs = 0;
      final repairRows = await txn.query(
        'repairs',
        columns: ['data_json'],
      );
      for (final repairRow in repairRows) {
        try {
          final decoded = jsonDecode(repairRow['data_json']?.toString() ?? '{}');
          if (decoded is! Map) continue;
          final data = Map<String, Object?>.from(decoded);
          final linkedPartyId =
              data['شناسه طرف حساب']?.toString().trim() ?? '';
          final repairName =
              _normalizeName(data['نام مشتری']?.toString() ?? '');
          if (linkedPartyId == partyId ||
              (linkedPartyId.isEmpty &&
                  normalizedPartyName.isNotEmpty &&
                  repairName == normalizedPartyName)) {
            linkedRepairs++;
          }
        } catch (_) {
          // Ignore malformed historical rows when checking deletion safety.
        }
      }
      final references = [
        linkedChecks.single['total'],
        linkedDocuments.single['total'],
        linkedJournal.single['total'],
      ].fold<int>(linkedRepairs, (sum, value) => sum + (value as num).toInt());


      final sourceCategory = record['source_category']?.toString() ?? '';
      final sourceId = record['source_id']?.toString() ?? '';
      final linkedLegacyCustomerId = sourceCategory == 'customers'
          ? int.tryParse(sourceId)
          : null;
      final hasLegacySource =
          sourceCategory.isNotEmpty || sourceId.isNotEmpty;
      final hasUnsupportedLegacySource =
          hasLegacySource && linkedLegacyCustomerId == null;
      if (references > 0 || hasUnsupportedLegacySource) {
        throw StateError(
          'این مخاطب سابقه فاکتور، چک، سند حسابداری یا پذیرش تعمیر دارد؛ '
          'برای حفظ سوابق امکان حذف مستقیم وجود ندارد.',
        );
      }

      // A legacy customer row is owned by this contact. Remove it in the
      // same transaction only after every financial and repair reference
      // above has been checked.
      if (linkedLegacyCustomerId != null) {
        await txn.delete(
          'customers',
          where: 'id = ?',
          whereArgs: [linkedLegacyCustomerId],
        );
      }
      await txn.delete(
        'parties',
        where: 'id = ?',
        whereArgs: [partyId],
      );
    });
  }

  Future<List<String>> getPartyRoles(String partyId) async {
    final db = await _database.database;
    final rows = await db.query(
      'party_roles',
      columns: ['role'],
      where: 'party_id = ?',
      whereArgs: [partyId],
      orderBy: 'role ASC',
    );
    return rows.map((row) => row['role'] as String).toList();
  }

  Future<List<Map<String, Object?>>> getParties({String? partyType}) async {
    final db = await _database.database;
    if (partyType == null) {
      return db.query(
        'parties',
        orderBy: 'display_name COLLATE NOCASE ASC',
      );
    }
    if (!_validRoles.contains(partyType)) {
      throw ArgumentError('نقش طرف حساب معتبر نیست');
    }
    return db.rawQuery('''
      SELECT p.*
      FROM parties p
      INNER JOIN party_roles r ON r.party_id = p.id
      WHERE r.role = ?
      ORDER BY p.display_name COLLATE NOCASE ASC
    ''', [partyType]);
  }

  Future<Map<String, List<Map<String, Object?>>>> getPartyActivity(
    String partyId,
  ) async {
    final db = await _database.database;
    final partyRows = await db.query(
      'parties',
      where: 'id = ?',
      whereArgs: [partyId],
      limit: 1,
    );
    if (partyRows.isEmpty) throw StateError('طرف حساب پیدا نشد');
    final party = partyRows.single;

    final documents = await db.query(
      'business_documents',
      where: 'counterparty_id = ?',
      whereArgs: [partyId],
      orderBy: 'document_date DESC, id DESC',
    );
    final checks = await db.query(
      'check_records',
      where: 'party_id = ?',
      whereArgs: [partyId],
      orderBy: 'due_date DESC, id DESC',
    );

    final legacyRows = await db.query(
      'repairs',
      columns: ['id', 'data_json', 'created_at', 'updated_at'],
      orderBy: 'created_at DESC, id DESC',
    );
    final repairs = <Map<String, Object?>>[];
    final normalizedPartyName =
        _normalizeName(party['display_name']?.toString() ?? '');
    for (final row in legacyRows) {
      try {
        final decoded = jsonDecode(row['data_json']?.toString() ?? '{}');
        if (decoded is! Map) continue;
        final data = Map<String, Object?>.from(decoded);
        final linkedPartyId =
            data['شناسه طرف حساب']?.toString().trim() ?? '';
        final repairName = _normalizeName(
          data['نام مشتری']?.toString() ?? '',
        );
        final linked = linkedPartyId == partyId ||
            (linkedPartyId.isEmpty &&
                normalizedPartyName.isNotEmpty &&
                repairName == normalizedPartyName);
        if (linked) {
          repairs.add({
            'id': row['id'],
            'created_at': row['created_at'],
            'updated_at': row['updated_at'],
            ...data,
          });
        }
      } catch (_) {
        // A malformed legacy repair row must not block the rest of the profile.
      }
    }

    return {
      'documents': documents,
      'repairs': repairs,
      'checks': checks,
    };
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
    final roles = await getPartyRoles(partyId);
    final isSupplier = roles.contains('supplier') && !roles.contains('customer');
    final hasBothTradingRoles =
        roles.contains('supplier') && roles.contains('customer');
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
      final balance = isSupplier
          ? -runningDebitMinusCredit
          : runningDebitMinusCredit;
      statement.add({
        ...row,
        'running_balance': balance,
        'balance_label': _balanceLabel(
          balance,
          isSupplier: isSupplier,
          hasBothTradingRoles: hasBothTradingRoles,
        ),
      });
    }

    final closingBalance = isSupplier
        ? creditTotal - debitTotal
        : debitTotal - creditTotal;

    final advanceBalances =
        await _getUnallocatedAdvanceBalances(db, partyId);

    return {
      ...advanceBalances,
      'party': party,
      'lines': statement,
      'total_debit': debitTotal,
      'total_credit': creditTotal,
      'closing_balance': closingBalance,
      'closing_label': _closingLabel(
        closingBalance,
        isSupplier: isSupplier,
        hasBothTradingRoles: hasBothTradingRoles,
      ),
      'roles': roles,
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
    final roles = await getPartyRoles(partyId);
    final isSupplier = roles.contains('supplier') && !roles.contains('customer');
    final hasBothTradingRoles =
        roles.contains('supplier') && roles.contains('customer');

    final totals = await db.rawQuery('''
      SELECT COALESCE(SUM(l.debit), 0) AS total_debit,
        COALESCE(SUM(l.credit), 0) AS total_credit
      FROM journal_lines l
      WHERE l.party_id = ?
    ''', [partyId]);
    final totalDebit = (totals.single['total_debit'] as num).toInt();
    final totalCredit = (totals.single['total_credit'] as num).toInt();

    // The closing balance represents the balance at the end of the selected
    // period, not the party's current balance when later entries exist.
    final closingArgs = <Object?>[partyId];
    final closingDateFilter = toExclusive == null ? '' : 'AND e.entry_date < ?';
    if (toExclusive != null) {
      closingArgs.add(toExclusive.toIso8601String().substring(0, 10));
    }
    final closingRows = await db.rawQuery('''
      SELECT COALESCE(SUM(l.debit - l.credit), 0) AS balance
      FROM journal_lines l
      JOIN journal_entries e ON e.id = l.journal_entry_id
      WHERE l.party_id = ? $closingDateFilter
    ''', closingArgs);
    final rawClosing = (closingRows.single['balance'] as num).toInt();
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
        'balance_label': _balanceLabel(
          balance,
          isSupplier: isSupplier,
          hasBothTradingRoles: hasBothTradingRoles,
        ),
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
    final advanceBalances = await _getUnallocatedAdvanceBalances(
      db,
      partyId,
      asOfDate: toDate,
    );

    return {
      ...advanceBalances,
      'party': party,
      'lines': lines,
      'total_debit': totalDebit,
      'total_credit': totalCredit,
      'opening_balance': isSupplier ? -openingRaw : openingRaw,
      'closing_balance': closingBalance,
      'closing_label': _closingLabel(
        closingBalance,
        isSupplier: isSupplier,
        hasBothTradingRoles: hasBothTradingRoles,
      ),
      'roles': roles,
      'total_lines': totalLines,
      'offset': offset,
      'next_offset': nextOffset,
      'has_more': nextOffset < totalLines,
    };
  }


  Future<Map<String, int>> _getUnallocatedAdvanceBalances(
    DatabaseExecutor db,
    String partyId, {
    String? asOfDate,
  }) async {
    Future<int> balanceFor(String type) async {
      final rows = await db.rawQuery('''
        SELECT COALESCE(SUM(
          d.paid_amount - COALESCE(a.allocated_amount, 0)
        ), 0) AS available
        FROM business_documents d
        LEFT JOIN (
          SELECT allocations.payment_document_id,
            SUM(allocations.amount) AS allocated_amount
          FROM invoice_payment_allocations allocations
          JOIN business_documents invoice
            ON invoice.id = allocations.invoice_document_id
          ${asOfDate == null ? '' : 'WHERE invoice.document_date <= ?'}
          GROUP BY allocations.payment_document_id
        ) a ON a.payment_document_id = d.id
        WHERE d.counterparty_id = ?
          AND d.document_type = ?
          AND d.source_document_id IS NULL
          ${asOfDate == null ? '' : 'AND d.document_date <= ?'}
      ''', [
        if (asOfDate != null) asOfDate,
        partyId,
        type,
        if (asOfDate != null) asOfDate,
      ]);
      return (rows.single['available'] as num).toInt();
    }

    return {
      'available_customer_advance': await balanceFor('customer_receipt'),
      'available_supplier_prepayment': await balanceFor('supplier_payment'),
    };
  }

  String _balanceLabel(
    int balance, {
    required bool isSupplier,
    required bool hasBothTradingRoles,
  }) {
    if (balance == 0) return 'تسویه';
    if (hasBothTradingRoles) return balance > 0 ? 'بدهکار' : 'بستانکار';
    if (isSupplier) return balance > 0 ? 'بستانکار' : 'بدهکار';
    return balance > 0 ? 'بدهکار' : 'بستانکار';
  }

  String _closingLabel(
    int balance, {
    required bool isSupplier,
    required bool hasBothTradingRoles,
  }) {
    if (balance == 0) return 'تسویه';
    if (hasBothTradingRoles) {
      return balance > 0 ? 'مانده بدهکار' : 'مانده بستانکار';
    }
    if (isSupplier) return balance > 0 ? 'طلب فروشنده' : 'بدهی فروشنده';
    return balance > 0 ? 'بدهی مشتری' : 'طلب مشتری';
  }
}
