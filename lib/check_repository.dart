import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'accounting_repository.dart';
import 'app_database.dart';

class CheckDraft {
  const CheckDraft({
    required this.direction,
    required this.checkNumber,
    required this.bankName,
    required this.drawerName,
    required this.partyName,
    required this.amount,
    required this.issueDate,
    required this.dueDate,
    required this.idempotencyKey,
    this.partyId,
    this.sourceDocumentId,
    this.note,
  });

  final String direction;
  final String checkNumber;
  final String bankName;
  final String drawerName;
  final String partyName;
  final int amount;
  final String issueDate;
  final String dueDate;
  final String idempotencyKey;
  final String? partyId;
  final int? sourceDocumentId;
  final String? note;

  Map<String, Object?> toPayload() => {
        'direction': direction,
        'checkNumber': checkNumber.trim(),
        'bankName': bankName.trim(),
        'drawerName': drawerName.trim(),
        'partyName': partyName.trim(),
        'amount': amount,
        'issueDate': issueDate,
        'dueDate': dueDate,
        'idempotencyKey': idempotencyKey,
        'partyId': partyId,
        'sourceDocumentId': sourceDocumentId,
        'note': note,
      };
}

class CheckRepository {
  CheckRepository(this._database)
      : _accounting = AccountingRepository(_database);

  final AppDatabase _database;
  final AccountingRepository _accounting;

  Future<int> createCheck(CheckDraft draft) async {
    _validateDraft(draft);
    final payload = jsonEncode(draft.toPayload());
    final db = await _database.database;

    return db.transaction((txn) async {
      final duplicate = await txn.query(
        'check_records',
        where: 'idempotency_key = ?',
        whereArgs: [draft.idempotencyKey],
        limit: 1,
      );
      if (duplicate.isNotEmpty) {
        if (duplicate.single['payload_json'] == payload) {
          return duplicate.single['id'] as int;
        }
        throw StateError('کلید یکتای چک برای اطلاعات دیگری استفاده شده است');
      }

      String? partyId = draft.partyId;
      if (partyId != null) {
        final partyRows = await txn.query(
          'parties',
          where: 'id = ?',
          whereArgs: [partyId],
          limit: 1,
        );
        if (partyRows.isEmpty) throw StateError('طرف حساب چک پیدا نشد');
      }

      if (draft.sourceDocumentId != null) {
        final sources = await txn.query(
          'business_documents',
          where: 'id = ?',
          whereArgs: [draft.sourceDocumentId],
          limit: 1,
        );
        if (sources.isEmpty) throw StateError('فاکتور مرتبط با چک پیدا نشد');
        final source = sources.single;
        final sourceType = draft.direction == 'incoming' ? 'sale' : 'purchase';
        if (source['document_type'] != sourceType) {
          throw StateError('نوع فاکتور با چک دریافتی یا پرداختی سازگار نیست');
        }
        final sourcePartyId = source['counterparty_id']?.toString();
        if (partyId != null &&
            sourcePartyId != null &&
            partyId != sourcePartyId) {
          throw StateError('طرف حساب چک با طرف حساب فاکتور یکسان نیست');
        }
        partyId ??= sourcePartyId;

        final paymentType = draft.direction == 'incoming'
            ? 'customer_receipt'
            : 'supplier_payment';
        final linkedPayments = await txn.rawQuery(
          'SELECT COALESCE(SUM(paid_amount), 0) AS paid '
          'FROM business_documents WHERE source_document_id = ? AND document_type = ?',
          [draft.sourceDocumentId, paymentType],
        );
        final linkedChecks = await txn.rawQuery(
          'SELECT COALESCE(SUM(amount), 0) AS amount FROM check_records '
          "WHERE source_document_id = ? AND status NOT IN ('bounced', 'cancelled')",
          [draft.sourceDocumentId],
        );
        final linkedReturns = await txn.rawQuery(
          'SELECT COALESCE(SUM(total_amount), 0) AS amount '
          'FROM business_documents WHERE source_document_id = ? AND document_type = ?',
          [
            draft.sourceDocumentId,
            draft.direction == 'incoming' ? 'customer_return' : 'supplier_return',
          ],
        );
        final alreadyPaid =
            (source['paid_amount'] as num).toInt() +
            (linkedPayments.single['paid'] as num).toInt() +
            (linkedChecks.single['amount'] as num).toInt();
        final remaining = (source['total_amount'] as num).toInt() -
            alreadyPaid -
            (linkedReturns.single['amount'] as num).toInt();
        if (draft.amount > remaining) {
          throw StateError('مبلغ چک از مانده فاکتور بیشتر است');
        }
      }

      final initialStatus =
          draft.direction == 'incoming' ? 'received' : 'issued';
      final journalLines = draft.direction == 'incoming'
          ? [
              JournalLineDraft(accountCode: '1020', debit: draft.amount),
              JournalLineDraft(
                accountCode: '1100',
                credit: draft.amount,
                partyId: partyId,
              ),
            ]
          : [
              JournalLineDraft(
                accountCode: '2000',
                debit: draft.amount,
                partyId: partyId,
              ),
              JournalLineDraft(accountCode: '2020', credit: draft.amount),
            ];

      final journalId = await _accounting.postJournalEntryInTransaction(
        txn,
        JournalEntryDraft(
          entryDate: draft.issueDate,
          description: draft.direction == 'incoming'
              ? 'دریافت چک شماره ${draft.checkNumber} از ${draft.partyName.trim()}'
              : 'صدور چک شماره ${draft.checkNumber} برای ${draft.partyName.trim()}',
          idempotencyKey: 'check-accept-${draft.idempotencyKey}',
          referenceType: 'check',
          referenceId: draft.idempotencyKey,
          lines: journalLines,
        ),
      );

      final now = DateTime.now().toIso8601String();
      final checkId = await txn.insert('check_records', {
        'direction': draft.direction,
        'check_number': draft.checkNumber.trim(),
        'bank_name': draft.bankName.trim(),
        'drawer_name': draft.drawerName.trim(),
        'party_id': partyId,
        'party_name': draft.partyName.trim(),
        'amount': draft.amount,
        'issue_date': draft.issueDate,
        'due_date': draft.dueDate,
        'status': initialStatus,
        'source_document_id': draft.sourceDocumentId,
        'acceptance_journal_id': journalId,
        'settlement_journal_id': null,
        'reversal_journal_id': null,
        'idempotency_key': draft.idempotencyKey,
        'payload_json': payload,
        'note': draft.note,
        'created_at': now,
        'updated_at': now,
      });

      await _insertEvent(
        txn,
        checkId: checkId,
        oldStatus: null,
        newStatus: initialStatus,
        eventDate: draft.issueDate,
        description: draft.direction == 'incoming'
            ? 'ثبت و دریافت چک'
            : 'ثبت چک پرداختی',
      );
      return checkId;
    });
  }

  Future<void> updateCheckStatus({
    required int checkId,
    required String newStatus,
    required String reason,
    String? eventDate,
  }) async {
    if (!const {'deposited', 'cleared', 'bounced', 'cancelled'}
        .contains(newStatus)) {
      throw ArgumentError('وضعیت جدید چک معتبر نیست');
    }
    if (reason.trim().isEmpty) {
      throw ArgumentError('شرح تغییر وضعیت چک الزامی است');
    }
    final date = eventDate ?? DateTime.now().toIso8601String().split('T').first;
    if (DateTime.tryParse(date) == null) {
      throw ArgumentError('تاریخ تغییر وضعیت چک معتبر نیست');
    }

    final db = await _database.database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'check_records',
        where: 'id = ?',
        whereArgs: [checkId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('چک پیدا نشد');
      final check = rows.single;
      final oldStatus = check['status'] as String;
      final direction = check['direction'] as String;
      if (oldStatus == newStatus) return;

      final isIncoming = direction == 'incoming';
      final allowed = isIncoming
          ? {
              'received': {'deposited', 'cleared', 'bounced', 'cancelled'},
              'deposited': {'cleared', 'bounced', 'cancelled'},
            }
          : {
              'issued': {'cleared', 'bounced', 'cancelled'},
            };
      if (!(allowed[oldStatus]?.contains(newStatus) ?? false)) {
        throw StateError('تغییر وضعیت از $oldStatus به $newStatus مجاز نیست');
      }

      final amount = (check['amount'] as num).toInt();
      final checkNumber = check['check_number']?.toString() ?? '';
      int? settlementJournalId;
      int? reversalJournalId;

      if (newStatus == 'cleared') {
        final lines = isIncoming
            ? [
                JournalLineDraft(accountCode: '1010', debit: amount),
                JournalLineDraft(accountCode: '1020', credit: amount),
              ]
            : [
                JournalLineDraft(accountCode: '2020', debit: amount),
                JournalLineDraft(accountCode: '1010', credit: amount),
              ];
        settlementJournalId = await _accounting.postJournalEntryInTransaction(
          txn,
          JournalEntryDraft(
            entryDate: date,
            description: isIncoming
                ? 'وصول چک دریافتی شماره $checkNumber'
                : 'پرداخت چک صادرشده شماره $checkNumber',
            idempotencyKey: 'check-cleared-$checkId',
            referenceType: 'check_cleared',
            referenceId: checkId.toString(),
            lines: lines,
          ),
        );
      } else if (newStatus == 'bounced' || newStatus == 'cancelled') {
        reversalJournalId = await _accounting.reverseJournalEntryInTransaction(
          txn,
          journalEntryId: check['acceptance_journal_id'] as int,
          reversalDate: date,
          reason: reason,
          idempotencyKey: 'check-reversal-$checkId',
        );
      }

      await txn.update(
        'check_records',
        {
          'status': newStatus,
          if (settlementJournalId != null)
            'settlement_journal_id': settlementJournalId,
          if (reversalJournalId != null)
            'reversal_journal_id': reversalJournalId,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [checkId],
      );
      await _insertEvent(
        txn,
        checkId: checkId,
        oldStatus: oldStatus,
        newStatus: newStatus,
        eventDate: date,
        description: reason.trim(),
      );
    });
  }

  Future<List<Map<String, Object?>>> getChecks({
    String? direction,
    String? status,
    String? partyId,
  }) async {
    final db = await _database.database;
    final clauses = <String>[];
    final args = <Object?>[];
    if (direction != null) {
      clauses.add('direction = ?');
      args.add(direction);
    }
    if (status != null) {
      clauses.add('status = ?');
      args.add(status);
    }
    if (partyId != null) {
      clauses.add('party_id = ?');
      args.add(partyId);
    }
    return db.query(
      'check_records',
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'due_date ASC, id ASC',
    );
  }

  Future<List<Map<String, Object?>>> getDueChecks({DateTime? asOfDate}) async {
    final today = asOfDate ?? DateTime.now();
    final through = DateTime(today.year, today.month, today.day + 1);
    final db = await _database.database;
    return db.query(
      'check_records',
      where: "due_date <= ? AND status IN ('received', 'deposited', 'issued')",
      whereArgs: [through.toIso8601String().split('T').first],
      orderBy: 'due_date ASC, id ASC',
    );
  }

  Future<List<Map<String, Object?>>> getCheckEvents(int checkId) async {
    final db = await _database.database;
    return db.query(
      'check_events',
      where: 'check_id = ?',
      whereArgs: [checkId],
      orderBy: 'event_date ASC, id ASC',
    );
  }

  Future<Map<String, Object?>> getCheck(int checkId) async {
    final db = await _database.database;
    final rows = await db.query(
      'check_records',
      where: 'id = ?',
      whereArgs: [checkId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('چک پیدا نشد');
    return rows.single;
  }

  void _validateDraft(CheckDraft draft) {
    if (!const {'incoming', 'outgoing'}.contains(draft.direction) ||
        draft.checkNumber.trim().isEmpty ||
        draft.bankName.trim().isEmpty ||
        draft.drawerName.trim().isEmpty ||
        draft.partyName.trim().isEmpty ||
        draft.amount <= 0 ||
        draft.idempotencyKey.trim().isEmpty ||
        DateTime.tryParse(draft.issueDate) == null ||
        DateTime.tryParse(draft.dueDate) == null) {
      throw ArgumentError('اطلاعات چک کامل یا معتبر نیست');
    }
    final issue = DateTime.parse(draft.issueDate);
    final due = DateTime.parse(draft.dueDate);
    if (due.isBefore(issue)) {
      throw ArgumentError('تاریخ سررسید نمی‌تواند قبل از تاریخ صدور باشد');
    }
  }

  Future<void> _insertEvent(
    DatabaseExecutor txn, {
    required int checkId,
    required String? oldStatus,
    required String newStatus,
    required String eventDate,
    required String description,
  }) async {
    await txn.insert('check_events', {
      'check_id': checkId,
      'old_status': oldStatus,
      'new_status': newStatus,
      'event_date': eventDate,
      'description': description,
      'created_at': DateTime.now().toIso8601String(),
    });
  }
}
