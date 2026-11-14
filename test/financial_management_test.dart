import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:khadamat_fanni_hosein/accounting_repository.dart';
import 'package:khadamat_fanni_hosein/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late AppDatabase database;
  late AccountingRepository accounting;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('khadamat_finance_test_');
    database = AppDatabase(databasePath: '${tempDir.path}/finance.db');
    accounting = AccountingRepository(database);
    await database.database;
  });

  tearDown(() async {
    await database.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('expense creates one balanced immutable journal and is idempotent', () async {
    final first = await accounting.recordExpense(
      expenseDate: '2026-11-14',
      description: 'اجاره کارگاه',
      amount: 2500000,
      expenseAccountCode: '6100',
      cashAccountCode: '1000',
      idempotencyKey: 'expense-rent-001',
    );
    final duplicate = await accounting.recordExpense(
      expenseDate: '2026-11-14',
      description: 'اجاره کارگاه',
      amount: 2500000,
      expenseAccountCode: '6100',
      cashAccountCode: '1000',
      idempotencyKey: 'expense-rent-001',
    );
    expect(duplicate, first);

    final db = await database.database;
    final entries = await db.query('journal_entries');
    expect(entries, hasLength(1));
    final lines = await db.query('journal_lines',
      where: 'journal_entry_id = ?', whereArgs: [first]);
    expect(lines, hasLength(2));
    expect(lines.firstWhere((l) => l['account_code'] == '6100')['debit'], 2500000);
    expect(lines.firstWhere((l) => l['account_code'] == '1000')['credit'], 2500000);

    final trial = await accounting.getTrialBalance();
    final expense = trial.firstWhere((r) => r['account_code'] == '6100');
    expect(expense['total_debit'], 2500000);
    expect(expense['total_credit'], 0);

    final ledger = await accounting.getAccountLedger('6100');
    expect(ledger['closing_balance'], 2500000);
    expect((ledger['lines'] as List), hasLength(1));
  });

  test('rejects invalid expense account and zero amount', () async {
    expect(
      () => accounting.recordExpense(
        expenseDate: '2026-11-14',
        description: 'هزینه نامعتبر',
        amount: 0,
        expenseAccountCode: '6100',
        cashAccountCode: '1000',
        idempotencyKey: 'invalid-amount',
      ),
      throwsArgumentError,
    );
    expect(
      () => accounting.recordExpense(
        expenseDate: '2026-11-14',
        description: 'حساب نامعتبر',
        amount: 100,
        expenseAccountCode: '1000',
        cashAccountCode: '1000',
        idempotencyKey: 'invalid-account',
      ),
      throwsArgumentError,
    );
  });

  test('date-filtered trial balance excludes entries outside the period', () async {
    await accounting.recordExpense(
      expenseDate: '2026-11-01',
      description: 'هزینه اول ماه',
      amount: 1000,
      expenseAccountCode: '6100',
      cashAccountCode: '1000',
      idempotencyKey: 'period-before',
    );
    await accounting.recordExpense(
      expenseDate: '2026-11-14',
      description: 'هزینه امروز',
      amount: 2000,
      expenseAccountCode: '6200',
      cashAccountCode: '1000',
      idempotencyKey: 'period-inside',
    );
    final trial = await accounting.getTrialBalance(
      fromDate: '2026-11-10',
      toDate: '2026-11-14',
    );
    expect(trial.firstWhere((r) => r['account_code'] == '6100')['total_debit'], 0);
    expect(trial.firstWhere((r) => r['account_code'] == '6200')['total_debit'], 2000);
  });

  test('bank reconciliation compares statement with same-day book balance and is immutable', () async {
    await accounting.postJournalEntry(const JournalEntryDraft(
      entryDate: '2026-11-14',
      description: 'واریز افتتاحیه بانک',
      idempotencyKey: 'bank-opening-001',
      lines: [
        JournalLineDraft(accountCode: '1010', debit: 1000000),
        JournalLineDraft(accountCode: '3000', credit: 1000000),
      ],
    ));
    final matching = await accounting.createBankReconciliation(
      accountCode: '1010',
      statementDate: '2026-11-14',
      statementBalance: 1000000,
      note: 'صورت‌حساب آبان',
      idempotencyKey: 'reconcile-bank-001',
    );
    final duplicate = await accounting.createBankReconciliation(
      accountCode: '1010',
      statementDate: '2026-11-14',
      statementBalance: 1000000,
      note: 'صورت‌حساب آبان',
      idempotencyKey: 'reconcile-bank-001',
    );
    expect(duplicate, matching);
    final rows = await accounting.getBankReconciliations(accountCode: '1010');
    expect(rows, hasLength(1));
    expect(rows.single['book_balance'], 1000000);
    expect(rows.single['difference'], 0);

    final db = await database.database;
    await expectLater(
      db.update('bank_reconciliations', {'note': 'تغییر غیرمجاز'},
        where: 'id = ?', whereArgs: [matching]),
      throwsA(anything),
    );
  });

  test('bank reconciliation reports positive and negative differences', () async {
    await accounting.postJournalEntry(const JournalEntryDraft(
      entryDate: '2026-11-14',
      description: 'واریز بانک',
      idempotencyKey: 'bank-opening-002',
      lines: [
        JournalLineDraft(accountCode: '1010', debit: 500000),
        JournalLineDraft(accountCode: '3000', credit: 500000),
      ],
    ));
    final id = await accounting.createBankReconciliation(
      accountCode: '1010',
      statementDate: '2026-11-14',
      statementBalance: 450000,
      idempotencyKey: 'reconcile-bank-002',
    );
    final row = (await accounting.getBankReconciliations()).singleWhere((r) => r['id'] == id);
    expect(row['book_balance'], 500000);
    expect(row['difference'], -50000);
  });

  test('bank reconciliation rejects invalid accounts, dates and negative balances', () async {
    Future<int> save({
      String account = '1010',
      String date = '2026-11-14',
      int balance = 100,
    }) => accounting.createBankReconciliation(
      accountCode: account,
      statementDate: date,
      statementBalance: balance,
      idempotencyKey: 'invalid-reconcile-$account-$date-$balance',
    );

    await expectLater(save(account: '1100'), throwsArgumentError);
    await expectLater(save(date: 'not-a-date'), throwsArgumentError);
    await expectLater(save(account: '1000', balance: -1), throwsArgumentError);
  });


  test('bank reconciliation accepts an overdraft but cash cannot be negative', () async {
    final id = await accounting.createBankReconciliation(
      accountCode: '1010',
      statementDate: '2026-11-14',
      statementBalance: -25000,
      idempotencyKey: 'bank-overdraft-001',
    );
    final row = (await accounting.getBankReconciliations()).singleWhere((r) => r['id'] == id);
    expect(row['statement_balance'], -25000);
  });

}
