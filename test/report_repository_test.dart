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

  test('stock price list reports current prices and ledger-derived quantity', () async {
    final productId = await database.insert('products', {
      'نام کالا': 'موتور آزمایشی',
      'گروه اصلی': 'قطعات',
      'کد کالا': 'M-120',
      'موجودی': '۵',
      'قیمت خرید هر واحد': '۱۲۵۰',
      'قیمت فروش': '۲۴۰۰',
    });

    final rows = await ReportRepository(database).getStockPriceList();
    final product = rows.singleWhere(
      (row) => row['product_id'] == productId,
    );

    expect(product['product_name'], 'موتور آزمایشی');
    expect(product['category'], 'قطعات');
    expect(product['product_code'], 'M-120');
    expect(product['stock_quantity'], 5);
    expect(product['purchase_price'], 1250);
    expect(product['sale_price'], 2400);
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

  test('item sales report nets customer returns by product and date', () async {
    final productId = await database.insert('products', {
      'نام کالا': 'بلبرینگ فروش',
      'موجودی': '10',
      'بهای تمام‌شده هر واحد': '100',
    });
    final saleId = await trades.recordSale(TradeDocumentDraft(
      documentDate: '2026-11-16',
      counterpartyName: 'مشتری گزارش فروش کالا',
      idempotencyKey: 'item-sales-source',
      lines: [
        TradeLineDraft(productId: productId, quantity: 3, unitPrice: 500),
      ],
    ));
    final saleLines = await trades.getDocumentLines(saleId);
    await trades.recordCustomerReturn(ReturnDocumentDraft(
      documentDate: '2026-11-17',
      sourceDocumentId: saleId,
      counterpartyName: 'مشتری گزارش فروش کالا',
      idempotencyKey: 'item-sales-return',
      lines: [
        ReturnLineDraft(
          sourceLineId: saleLines.single['id'] as int,
          quantity: 1,
        ),
      ],
    ));

    final rows = await ReportRepository(database).getItemSales(
      from: DateTime(2026, 11, 16),
      to: DateTime(2026, 11, 17),
    );
    final item = rows.singleWhere((row) => row['product_id'] == productId);
    expect(item['product_name'], 'بلبرینگ فروش');
    expect(item['net_quantity'], 2);
    expect(item['net_revenue'], 1000);
  });

  test('item profit uses exact stock movement cost after partial customer return', () async {
    final productId = await database.insert('products', {
      'نام کالا': 'قطعه با بهای دقیق',
      'موجودی': '0',
      'بهای تمام‌شده هر واحد': '0',
    });
    await trades.recordPurchase(TradeDocumentDraft(
      documentDate: '2026-11-16',
      counterpartyName: 'فروشنده',
      idempotencyKey: 'profit-exact-purchase',
      lines: [
        TradeLineDraft(productId: productId, quantity: 3, unitPrice: 100),
      ],
      discountAmount: 1,
    ));
    final saleId = await trades.recordSale(TradeDocumentDraft(
      documentDate: '2026-11-16',
      counterpartyName: 'مشتری',
      idempotencyKey: 'profit-exact-sale',
      lines: [
        TradeLineDraft(productId: productId, quantity: 2, unitPrice: 200),
      ],
    ));
    final saleLine = (await trades.getDocumentLines(saleId)).single;
    await trades.recordCustomerReturn(ReturnDocumentDraft(
      documentDate: '2026-11-17',
      sourceDocumentId: saleId,
      counterpartyName: 'مشتری',
      idempotencyKey: 'profit-exact-return',
      lines: [
        ReturnLineDraft(
          sourceLineId: saleLine['id'] as int,
          quantity: 1,
        ),
      ],
    ));

    final rows = await ReportRepository(database).getItemProfit(
      from: DateTime(2026, 11, 16),
      to: DateTime(2026, 11, 17),
    );
    final item = rows.singleWhere((row) => row['product_id'] == productId);
    expect(item['net_revenue'], 200);
    expect(item['net_cost'], 99);
    expect(item['gross_profit'], 101);
    expect(item['net_quantity'], 1);
  });

  test('Kardex keeps opening movements before date range in running balance', () async {
    final productId = await database.insert('products', {
      'نام کالا': 'کاردکس مانده‌دار',
      'موجودی': '0',
      'بهای تمام‌شده هر واحد': '0',
    });
    await trades.recordPurchase(TradeDocumentDraft(
      documentDate: '2026-11-10',
      counterpartyName: 'فروشنده',
      idempotencyKey: 'kardex-before-range',
      lines: [TradeLineDraft(productId: productId, quantity: 5, unitPrice: 100)],
    ));
    await trades.recordPurchase(TradeDocumentDraft(
      documentDate: '2026-11-15',
      counterpartyName: 'فروشنده',
      idempotencyKey: 'kardex-inside-range',
      lines: [TradeLineDraft(productId: productId, quantity: 4, unitPrice: 120)],
    ));
    await trades.recordSale(TradeDocumentDraft(
      documentDate: '2026-11-16',
      counterpartyName: 'مشتری',
      idempotencyKey: 'kardex-sale-inside-range',
      lines: [TradeLineDraft(productId: productId, quantity: 2, unitPrice: 200)],
    ));

    final rows = await ReportRepository(database).getInventoryMovements(
      from: DateTime(2026, 11, 15),
      to: DateTime(2026, 11, 16),
    );
    final productRows = rows.where((row) => row['product_id'] == productId).toList();
    expect(productRows, hasLength(2));
    expect(productRows[0]['movement_type'], 'purchase');
    expect(productRows[0]['balance_after'], 9);
    expect(productRows[1]['movement_type'], 'sale');
    expect(productRows[1]['balance_after'], 7);
  });
}
