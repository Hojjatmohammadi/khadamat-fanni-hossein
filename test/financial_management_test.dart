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
}
