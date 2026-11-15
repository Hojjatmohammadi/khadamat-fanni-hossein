import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:khadamat_fanni_hosein/accounting_repository.dart';
import 'package:khadamat_fanni_hosein/app_database.dart';
import 'package:khadamat_fanni_hosein/report_repository.dart';
import 'package:khadamat_fanni_hosein/trade_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late AppDatabase database;
  late TradeRepository trades;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('reports_test_');
    database = AppDatabase(databasePath: '${tempDir.path}/reports.db');
    trades = TradeRepository(database);
    await database.database;
  });

  tearDown(() async {
    await database.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('trade report filters by inclusive date range and document type', () async {
    final productId = await database.insert('products', {
      'نام کالا': 'قطعه گزارش',
      'موجودی': '10',
      'بهای تمام‌شده هر واحد': '100',
    });
    await trades.recordSale(TradeDocumentDraft(
      documentDate: '2026-11-10',
      counterpartyName: 'مشتری اول',
      idempotencyKey: 'report-sale-1',
      lines: [TradeLineDraft(productId: productId, quantity: 1, unitPrice: 500)],
    ));
    await trades.recordSale(TradeDocumentDraft(
      documentDate: '2026-11-12',
      counterpartyName: 'مشتری دوم',
      idempotencyKey: 'report-sale-2',
      lines: [TradeLineDraft(productId: productId, quantity: 1, unitPrice: 600)],
    ));

    final repository = ReportRepository(database);
    final rows = await repository.getTradeDocuments(
      from: DateTime(2026, 11, 11),
      to: DateTime(2026, 11, 12),
      type: 'sale',
    );
    expect(rows, hasLength(1));
    expect(rows.single['counterparty_name'], 'مشتری دوم');
    expect(rows.single['total_amount'], 600);
  });

  test('expense and repair service reports do not double-count settlements', () async {
    final accounting = AccountingRepository(database);
    final repository = ReportRepository(database);

    await accounting.recordExpense(
      expenseDate: '2026-11-14',
      description: 'خرید لوازم مصرفی',
      amount: 1200,
      expenseAccountCode: '6600',
      cashAccountCode: '1000',
      idempotencyKey: 'report-expense-1',
    );
    await accounting.recordRepairServiceIncome(
      serviceDate: '2026-11-14',
      description: 'اجرت تعمیر پمپ',
      amount: 10000,
      paidAmount: 4000,
      cashAccountCode: '1000',
      customerId: 'customer-service-1',
      idempotencyKey: 'repair-service-income-1',
      repairId: 'repair-1',
    );
    await accounting.recordRepairServiceReceipt(
      receiptDate: '2026-11-15',
      repairId: 'repair-1',
      customerId: 'customer-service-1',
      description: 'اجرت تعمیر پمپ',
      amount: 6000,
      cashAccountCode: '1000',
      idempotencyKey: 'repair-service-later-receipt',
    );

    final expenses = await repository.getExpenses(
      from: DateTime(2026, 11, 14),
      to: DateTime(2026, 11, 15),
    );
    expect(expenses, hasLength(1));
    expect(expenses.single['amount'], 1200);
    expect(expenses.single['account_code'], '6600');

    final serviceIncome = await repository.getRepairServiceRevenue(
      from: DateTime(2026, 11, 14),
      to: DateTime(2026, 11, 15),
    );
    expect(serviceIncome, hasLength(1));
    expect(serviceIncome.single['amount'], 10000);
    expect(serviceIncome.single['account_code'], '4100');

    final profitAndLoss = await repository.getProfitAndLoss(
      from: DateTime(2026, 11, 14),
      to: DateTime(2026, 11, 15),
    );
    final serviceAccount = profitAndLoss.singleWhere(
      (row) => row['account_code'] == '4100',
    );
    final expenseAccount = profitAndLoss.singleWhere(
      (row) => row['account_code'] == '6600',
    );
    expect(serviceAccount['balance'], 10000);
    expect(expenseAccount['balance'], 1200);
  });

  test('stock report returns ledger movements with product names', () async {
    final productId = await database.insert('products', {
      'نام کالا': 'خازن گزارش',
      'موجودی': '4',
      'بهای تمام‌شده هر واحد': '200',
    });
    final rows = await ReportRepository(database).getInventoryMovements(
      from: DateTime(2026, 11, 1),
      to: DateTime(2026, 11, 30),
    );
    expect(rows, isNotEmpty);
    expect(rows.any((row) => row['product_name'] == 'خازن گزارش'), isTrue);
    expect(rows.any((row) => row['product_id'] == productId), isTrue);
  });
}
