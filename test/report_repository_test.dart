import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:khadamat_fanni_hosein/accounting_repository.dart';
import 'package:khadamat_fanni_hosein/app_database.dart';
import 'package:khadamat_fanni_hosein/report_repository.dart';
import 'package:khadamat_fanni_hosein/trade_repository.dart';
import 'package:khadamat_fanni_hosein/check_repository.dart';

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
    expect(product['stock_value'], 6250);
  });

  test('Kardex exposes stock count reason and physical counted quantity', () async {
    final productId = await database.insert('products', {
      'نام کالا': 'قطعه انبارگردانی',
      'موجودی': '10',
      'بهای تمام‌شده هر واحد': '1000',
    });
    final accounting = AccountingRepository(database);
    await accounting.recordStockAdjustment(
      productId: productId,
      countedQuantity: 8,
      fallbackUnitCost: 1000,
      occurredAt: '2026-11-17T10:00:00.000',
      reason: 'کسری دو عدد در شمارش قفسه',
      idempotencyKey: 'kardex-stock-count-reason',
    );

    final rows = await ReportRepository(database).getInventoryMovements(
      from: DateTime(2026, 11, 17),
      to: DateTime(2026, 11, 17),
    );
    final adjustment = rows.singleWhere(
      (row) => row['movement_type'] == 'adjustment',
    );
    expect(adjustment['quantity_delta'], -2);
    expect(adjustment['adjustment_reason'], 'کسری دو عدد در شمارش قفسه');
    expect(adjustment['counted_quantity'], 8);
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

  test('cheque movement report returns immutable events within inclusive dates', () async {
    final checks = CheckRepository(database);
    final checkId = await checks.createCheck(
      const CheckDraft(
        direction: 'incoming',
        checkNumber: 'RPT-1405-01',
        bankName: 'بانک آزمایشی',
        drawerName: 'صادرکننده',
        partyName: 'مشتری گزارش چک',
        amount: 750000,
        issueDate: '2026-11-16',
        dueDate: '2026-11-25',
        idempotencyKey: 'report-check-movements',
      ),
    );
    await checks.updateCheckStatus(
      checkId: checkId,
      newStatus: 'deposited',
      reason: 'تحویل به بانک',
      eventDate: '2026-11-17',
    );
    await checks.updateCheckStatus(
      checkId: checkId,
      newStatus: 'cleared',
      reason: 'وصول شد',
      eventDate: '2026-11-18',
    );

    final repository = ReportRepository(database);
    final allEvents = await repository.getCheckMovements(
      from: DateTime(2026, 11, 16),
      to: DateTime(2026, 11, 18),
    );
    expect(allEvents, hasLength(3));
    expect(allEvents.map((row) => row['new_status']).toList(), [
      'received',
      'deposited',
      'cleared',
    ]);
    expect(allEvents.every((row) => row['check_id'] == checkId), isTrue);
    expect(allEvents.every((row) => row['amount'] == 750000), isTrue);
    expect(allEvents.first['old_status'], isNull);
    expect(allEvents.last['current_status'], 'cleared');

    final check = await checks.getCheck(checkId);
    final acceptanceId = check['acceptance_journal_id'];
    final settlementId = check['settlement_journal_id'];
    expect(acceptanceId, isNotNull);
    expect(settlementId, isNotNull);
    expect(
      allEvents.firstWhere((row) => row['new_status'] == 'received')
          ['journal_entry_id'],
      acceptanceId,
    );
    expect(
      allEvents.firstWhere((row) => row['new_status'] == 'deposited')
          ['journal_entry_id'],
      acceptanceId,
    );
    expect(
      allEvents.firstWhere((row) => row['new_status'] == 'cleared')
          ['journal_entry_id'],
      settlementId,
    );

    final journalIds = {acceptanceId as int, settlementId as int};
    for (final journalId in journalIds) {
      final totals = await database.rawQuery(
        'SELECT COALESCE(SUM(debit), 0) AS debit_total, '
        'COALESCE(SUM(credit), 0) AS credit_total '
        'FROM journal_lines WHERE journal_entry_id = ?',
        [journalId],
      );
      expect(totals.single['debit_total'], 750000);
      expect(totals.single['credit_total'], 750000);
    }

    final singleDay = await repository.getCheckMovements(
      from: DateTime(2026, 11, 17),
      to: DateTime(2026, 11, 17),
    );
    expect(singleDay, hasLength(1));
    expect(singleDay.single['new_status'], 'deposited');

    await expectLater(
      repository.getCheckMovements(
        from: DateTime(2026, 11, 18),
        to: DateTime(2026, 11, 17),
      ),
      throwsArgumentError,
    );
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
  test('profit reports classify sales returns and reconcile item, stock and ledger totals', () async {
    final productId = await database.insert('products', {
      'نام کالا': 'قطعه آزمون سود تلفیقی',
      'موجودی': '3',
      'بهای تمام‌شده هر واحد': '100',
    });

    final saleId = await trades.recordSale(TradeDocumentDraft(
      documentDate: '2026-11-16',
      counterpartyName: 'مشتری گزارش تلفیقی',
      idempotencyKey: 'integrated-report-sale',
      lines: [
        TradeLineDraft(productId: productId, quantity: 2, unitPrice: 500),
      ],
    ));
    final sourceLine = (await trades.getDocumentLines(saleId)).single;
    await trades.recordCustomerReturn(ReturnDocumentDraft(
      documentDate: '2026-11-17',
      sourceDocumentId: saleId,
      counterpartyName: 'مشتری گزارش تلفیقی',
      idempotencyKey: 'integrated-report-return',
      lines: [
        ReturnLineDraft(
          sourceLineId: sourceLine['id'] as int,
          quantity: 1,
        ),
      ],
    ));

    final accounting = AccountingRepository(database);
    await accounting.recordExpense(
      expenseDate: '2026-11-17',
      description: 'هزینه آزمون گزارش تلفیقی',
      amount: 100,
      expenseAccountCode: '6600',
      cashAccountCode: '1000',
      idempotencyKey: 'integrated-report-expense',
    );
    await accounting.recordRepairServiceIncome(
      serviceDate: '2026-11-17',
      description: 'اجرت آزمون گزارش تلفیقی',
      amount: 200,
      paidAmount: 0,
      cashAccountCode: '1000',
      repairId: 'integrated-report-repair',
      idempotencyKey: 'integrated-report-service',
    );

    final repository = ReportRepository(database);
    final from = DateTime(2026, 11, 16);
    final to = DateTime(2026, 11, 17);
    final profitAndLoss = await repository.getProfitAndLoss(from: from, to: to);
    final byCode = {
      for (final row in profitAndLoss) row['account_code']: row,
    };

    expect(byCode['4000']?['balance'], 1000);
    expect(byCode['4100']?['balance'], 200);
    expect(byCode['4050']?['balance'], 500);
    expect(byCode['4050']?['report_group'], 'sales_return');
    expect(byCode['5000']?['total_debit'], 200);
    expect(byCode['5000']?['total_credit'], 100);
    expect(byCode['5000']?['balance'], 100);
    expect(byCode['6600']?['balance'], 100);

    final netResult = profitAndLoss.fold<int>(
      0,
      (sum, row) => sum +
          (row['balance'] as num).toInt() *
              (row['account_type'] == 'income' ? 1 : -1),
    );
    expect(netResult, 500);

    final itemSales = await repository.getItemSales(from: from, to: to);
    expect(itemSales.single['net_revenue'], 500);
    expect(itemSales.single['net_quantity'], 1);

    final itemProfit = await repository.getItemProfit(from: from, to: to);
    expect(itemProfit.single['net_revenue'], 500);
    expect(itemProfit.single['net_cost'], 100);
    expect(itemProfit.single['gross_profit'], 400);

    final stock = await repository.getStockPriceList();
    final itemStock = stock.singleWhere((row) => row['product_id'] == productId);
    expect(itemStock['stock_quantity'], 2);
    expect(itemStock['stock_value'], 200);
  });

}
