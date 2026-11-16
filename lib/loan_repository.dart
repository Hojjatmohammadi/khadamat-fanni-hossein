import 'package:sqflite/sqflite.dart';
import 'accounting_repository.dart';
import 'app_database.dart';

class LoanRepository {
  LoanRepository(this._database) : _accounting = AccountingRepository(_database);
  final AppDatabase _database;
  final AccountingRepository _accounting;

  Future<int> createReceivedLoan({required String partyName, required int amount, required String loanDate, required String idempotencyKey, String? dueDate, String? note, int installmentCount = 1, String cashAccountCode = '1000'}) async {
    if (partyName.trim().isEmpty || DateTime.tryParse(loanDate) == null || (dueDate != null && DateTime.tryParse(dueDate) == null) || amount <= 0 || installmentCount < 1 || installmentCount > 120 || idempotencyKey.trim().isEmpty || !['1000','1010'].contains(cashAccountCode)) throw ArgumentError('اطلاعات قرض معتبر نیست');
    final db = await _database.database;
    return db.transaction((txn) async {
      final old = await txn.query('loan_records', where: 'idempotency_key = ?', whereArgs: [idempotencyKey], limit: 1);
      if (old.isNotEmpty) {
        final row = old.single;
        if (row['party_name'] != partyName.trim() || row['principal_amount'] != amount ||
            row['loan_date'] != loanDate || row['due_date'] != dueDate || row['note'] != note) {
          throw StateError('شناسه ثبت قرض قبلاً با اطلاعات متفاوت استفاده شده است');
        }
        return row['id'] as int;
      }
      final journalId = await _accounting.postJournalEntryInTransaction(txn, JournalEntryDraft(entryDate: loanDate, description: 'دریافت قرض از ${partyName.trim()}', idempotencyKey: 'loan-journal-$idempotencyKey', referenceType: 'loan_received', referenceId: idempotencyKey, lines: [JournalLineDraft(accountCode: cashAccountCode, debit: amount, memo: 'دریافت اصل قرض'), JournalLineDraft(accountCode: '2030', credit: amount, memo: 'بدهی بابت قرض')]));
      final loanId = await txn.insert('loan_records', {'direction':'received','party_name':partyName.trim(),'principal_amount':amount,'loan_date':loanDate,'due_date':dueDate,'note':note,'idempotency_key':idempotencyKey,'journal_entry_id':journalId,'created_at':DateTime.now().toIso8601String()});
      final base = amount ~/ installmentCount; var remainder = amount - base * installmentCount; final start = DateTime.parse(dueDate ?? loanDate);
      for (var i=0; i<installmentCount; i++) { final month=DateTime(start.year,start.month+i,1); final lastDay=DateTime(month.year,month.month+1,0).day; final due=DateTime(month.year,month.month,start.day>lastDay?lastDay:start.day); final part=base+(remainder>0?1:0); if(remainder>0) remainder--; await txn.insert('loan_installments', {'loan_id':loanId,'installment_number':i+1,'due_date':due.toIso8601String().substring(0,10),'amount':part,'paid_amount':0,'created_at':DateTime.now().toIso8601String()}); }
      return loanId;
    });
  }

  Future<int> recordRepayment({required int loanId, required int amount, required String paymentDate, required String idempotencyKey, String cashAccountCode='1000', int? installmentId, String? note}) async {
    if (DateTime.tryParse(paymentDate)==null || amount<=0 || idempotencyKey.trim().isEmpty || !['1000','1010'].contains(cashAccountCode)) throw ArgumentError('اطلاعات بازپرداخت معتبر نیست');
    final db=await _database.database;
    return db.transaction((txn) async {
      final previous=await txn.query('loan_transactions',where:'idempotency_key = ?',whereArgs:[idempotencyKey],limit:1); if(previous.isNotEmpty){final row=previous.single;if(row['loan_id']!=loanId||row['amount']!=amount||row['transaction_date']!=paymentDate||row['installment_id']!=installmentId)throw StateError('شناسه بازپرداخت قبلاً برای اطلاعات دیگری استفاده شده است');return row['id'] as int;}
      final loans=await txn.query('loan_records',where:'id = ? AND direction = ?',whereArgs:[loanId,'received'],limit:1); if(loans.isEmpty) throw ArgumentError('قرض موردنظر پیدا نشد');
      final paidRows=await txn.rawQuery("SELECT COALESCE(SUM(amount),0) AS paid FROM loan_transactions WHERE loan_id=? AND transaction_type='repayment'",[loanId]); final paid=(paidRows.single['paid'] as num).toInt(); final principal=(loans.single['principal_amount'] as num).toInt(); if(amount>principal-paid) throw ArgumentError('مبلغ بازپرداخت از مانده قرض بیشتر است');
      if(installmentId!=null){final rows=await txn.query('loan_installments',where:'id=? AND loan_id=?',whereArgs:[installmentId,loanId],limit:1); if(rows.isEmpty) throw ArgumentError('قسط انتخاب‌شده متعلق به این قرض نیست'); final remaining=(rows.single['amount'] as num).toInt()-(rows.single['paid_amount'] as num).toInt(); if(amount>remaining) throw ArgumentError('مبلغ پرداخت از مانده این قسط بیشتر است');}
      final journalId=await _accounting.postJournalEntryInTransaction(txn,JournalEntryDraft(entryDate:paymentDate,description:'بازپرداخت اصل قرض به ${loans.single['party_name']}',idempotencyKey:'loan-repayment-journal-$idempotencyKey',referenceType:'loan_repayment',referenceId:loanId.toString(),lines:[JournalLineDraft(accountCode:'2030',debit:amount,memo:'کاهش اصل بدهی قرض'),JournalLineDraft(accountCode:cashAccountCode,credit:amount,memo:'پرداخت اصل قرض')]));
      final transactionId=await txn.insert('loan_transactions',{'loan_id':loanId,'transaction_type':'repayment','transaction_date':paymentDate,'amount':amount,'installment_id':installmentId,'journal_entry_id':journalId,'idempotency_key':idempotencyKey,'note':note,'created_at':DateTime.now().toIso8601String()}); if(installmentId!=null) await txn.rawUpdate('UPDATE loan_installments SET paid_amount=paid_amount+? WHERE id=?',[amount,installmentId]); return transactionId;
    });
  }

  Future<List<Map<String,Object?>>> getLoans() async { final db=await _database.database; return db.rawQuery("SELECT l.*,COALESCE((SELECT SUM(t.amount) FROM loan_transactions t WHERE t.loan_id=l.id AND t.transaction_type='repayment'),0) AS paid_amount,l.principal_amount-COALESCE((SELECT SUM(t.amount) FROM loan_transactions t WHERE t.loan_id=l.id AND t.transaction_type='repayment'),0) AS remaining_amount,(SELECT COUNT(*) FROM loan_installments i WHERE i.loan_id=l.id) AS installment_count FROM loan_records l ORDER BY l.loan_date DESC,l.id DESC"); }
  Future<List<Map<String,Object?>>> getInstallments(int loanId) async { final db=await _database.database; return db.query('loan_installments',where:'loan_id=?',whereArgs:[loanId],orderBy:'installment_number ASC'); }
}