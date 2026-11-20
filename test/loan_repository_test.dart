import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:khadamat_fanni_hosein/app_database.dart';
import 'package:khadamat_fanni_hosein/loan_repository.dart';

void main(){
 TestWidgetsFlutterBinding.ensureInitialized(); sqfliteFfiInit(); databaseFactory=databaseFactoryFfi;
 late Directory dir; late AppDatabase database; late LoanRepository loans;
 setUp(() async {dir=await Directory.systemTemp.createTemp('loan_test_');database=AppDatabase(databasePath:'${dir.path}/test.db');loans=LoanRepository(database);await database.database;});
 tearDown(() async {await database.close();if(await dir.exists())await dir.delete(recursive:true);});
 test('received loan posts cash against liability and creates installment schedule',() async {
  final id=await loans.createReceivedLoan(partyName:'قرض‌دهنده آزمایشی',amount:120000,loanDate:'2026-11-16',dueDate:'2026-12-01',installmentCount:3,idempotencyKey:'loan-001');
  expect(await loans.createReceivedLoan(partyName:'قرض‌دهنده آزمایشی',amount:120000,loanDate:'2026-11-16',dueDate:'2026-12-01',installmentCount:3,idempotencyKey:'loan-001'),id);
  final db=await database.database;final loan=(await loans.getLoans()).single;expect(loan['remaining_amount'],120000);
  final installments=await loans.getInstallments(id);expect(installments,hasLength(3));expect(installments.fold<int>(0,(s,r)=>s+(r['amount'] as num).toInt()),120000);
  final journal=await db.query('journal_entries');expect(journal,hasLength(1));final lines=await db.query('journal_lines',where:'journal_entry_id=?',whereArgs:[journal.single['id']]);
  expect(lines.singleWhere((r)=>r['account_code']=='1000')['debit'],120000);expect(lines.singleWhere((r)=>r['account_code']=='2030')['credit'],120000);
  expect(await db.query('accounts',where:'code=?',whereArgs:['2030']),hasLength(1));
 });
 test('repayment reduces principal liability, is idempotent and cannot overpay',() async {
  final loanId=await loans.createReceivedLoan(partyName:'شخص',amount:100000,loanDate:'2026-11-16',dueDate:'2026-12-01',installmentCount:2,idempotencyKey:'loan-002');
  final installments=await loans.getInstallments(loanId);final first=installments.first;
  final tx=await loans.recordRepayment(loanId:loanId,amount:50000,paymentDate:'2026-12-01',installmentId:first['id'] as int,idempotencyKey:'repay-001');
  expect(await loans.recordRepayment(loanId:loanId,amount:50000,paymentDate:'2026-12-01',installmentId:first['id'] as int,idempotencyKey:'repay-001'),tx);
  expect((await loans.getLoans()).single['remaining_amount'],50000);expect((await loans.getInstallments(loanId)).first['paid_amount'],50000);
  final db=await database.database;final entries=await db.query('journal_entries');expect(entries,hasLength(2));final repayment=await db.query('journal_lines',where:'journal_entry_id=?',whereArgs:[entries.last['id']]);
  expect(repayment.singleWhere((r)=>r['account_code']=='2030')['debit'],50000);expect(repayment.singleWhere((r)=>r['account_code']=='1000')['credit'],50000);
  await expectLater(loans.recordRepayment(loanId:loanId,amount:60000,paymentDate:'2026-12-02',idempotencyKey:'repay-over'),throwsArgumentError);
  expect((await loans.getLoans()).single['remaining_amount'],50000);
 });
 test('repayment cannot exceed selected installment balance',() async {
  final id=await loans.createReceivedLoan(partyName:'شخص',amount:90000,loanDate:'2026-11-16',dueDate:'2026-12-01',installmentCount:3,idempotencyKey:'loan-003');final first=(await loans.getInstallments(id)).first;
  await expectLater(loans.recordRepayment(loanId:id,amount:31000,paymentDate:'2026-12-01',installmentId:first['id'] as int,idempotencyKey:'repay-too-much'),throwsArgumentError);
  expect((await loans.getLoans()).single['remaining_amount'],90000);
 });
}