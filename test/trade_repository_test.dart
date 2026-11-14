import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:khadamat_fanni_hosein/accounting_repository.dart';
import 'package:khadamat_fanni_hosein/app_database.dart';
import 'package:khadamat_fanni_hosein/trade_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late AppDatabase store;
  late TradeRepository trades;
  late AccountingRepository accounting;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('khadamat_trade_test_');
    store = AppDatabase(databasePath: '${tempDir.path}/trade.db');
    trades = TradeRepository(store);
    accounting = AccountingRepository(store);
    await store.database;
  });

  tearDown(() async {
    await store.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<int> addProduct({
    String name = 'قطعه آزمایشی',
    String quantity = '0',
    String unitCost = '0',
  }) {
    return store.insert('products', {
      'نام کالا': name,
      'موجودی': quantity,
      'بهای تمام‌شده هر واحد': unitCost,
    });
  }

  Future<Map<String, Object?>> accountTotals(String code) async {
    final rows = await accounting.getTrialBalance();
    return rows.singleWhere((row) => row['account_code'] == code);
  }

  test('purchase invoice updates stock, inventory value, VAT and supplier payable once', () async {
    final productId = await addProduct();
    final draft = TradeDocumentDraft(
      documentDate: '2026-11-14',
      counterpartyName: 'فروشنده قطعات',
      counterpartyId: 'supplier-1',
      idempotencyKey: 'purchase-test-1',
      lines: [
        TradeLineDraft(productId: productId, quantity: 10, unitPrice: 1000),
      ],
      shippingCost: 600,
      freightCost: 400,
      vatRate: 20,
      paidAmount: 3000,
    );

    final documentId = await trades.recordPurchase(draft);
    expect(await trades.recordPurchase(draft), documentId);
    expect(await store.getStockOnHand(productId), 10);

    final documents = await trades.getDocuments(type: 'purchase');
    expect(documents, hasLength(1));
    expect(documents.single['total_amount'], 13000);
    expect(documents.single['paid_amount'], 3000);

    final documentLines = await trades.getDocumentLines(documentId);
    expect(documentLines, hasLength(1));
    expect(documentLines.single['unit_cost'], 1100);
    expect(documentLines.single['line_total'], 11000);

    final inventory = await accountTotals('1200');
    final inputVat = await accountTotals('2110');
    final cash = await accountTotals('1000');
    final payable = await accountTotals('2000');
    expect(inventory['total_debit'], 11000);
    expect(inputVat['total_debit'], 2000);
    expect(cash['total_credit'], 3000);
    expect(payable['total_credit'], 10000);

    final db = await store.database;
    expect(await db.query('business_documents'), hasLength(1));
    expect(await db.query('inventory_movements'), hasLength(1));
  });

  test('sale invoice checks stock and posts revenue, receivable and cost of goods sold atomically', () async {
    final productId = await addProduct();
    await trades.recordPurchase(
      TradeDocumentDraft(
        documentDate: '2026-11-13',
        counterpartyName: 'فروشنده',
        idempotencyKey: 'sale-source-purchase',
        lines: [
          TradeLineDraft(productId: productId, quantity: 10, unitPrice: 1000),
        ],
      ),
    );

    final sale = TradeDocumentDraft(
      documentDate: '2026-11-14',
      counterpartyName: 'مشتری فروش',
      counterpartyId: 'customer-1',
      idempotencyKey: 'sale-test-1',
      lines: [
        TradeLineDraft(productId: productId, quantity: 3, unitPrice: 2000),
      ],
      vatRate: 10,
      paidAmount: 2000,
    );
    final saleId = await trades.recordSale(sale);
    expect(await trades.recordSale(sale), saleId);
    expect(await store.getStockOnHand(productId), 7);

    final document = (await trades.getDocuments(type: 'sale')).single;
    expect(document['subtotal'], 6000);
    expect(document['vat_amount'], 600);
    expect(document['total_amount'], 6600);
    expect(document['paid_amount'], 2000);

    expect((await accountTotals('4000'))['total_credit'], 6000);
    expect((await accountTotals('2100'))['total_credit'], 600);
    expect((await accountTotals('1100'))['total_debit'], 4600);
    expect((await accountTotals('5000'))['total_debit'], 3000);
    expect((await accountTotals('1200'))['total_credit'], 3000);

    final lines = await trades.getDocumentLines(saleId);
    expect(lines.single['unit_cost'], 1000);
    expect(lines.single['line_total'], 6000);

    final db = await store.database;
    expect(await db.query('business_documents'), hasLength(2));
    expect(await db.query('inventory_movements'), hasLength(2));
  });

  test('sale with insufficient stock leaves no invoice, journal or stock movement', () async {
    final productId = await addProduct();
    await expectLater(
      trades.recordSale(
        TradeDocumentDraft(
          documentDate: '2026-11-14',
          counterpartyName: 'مشتری',
          idempotencyKey: 'sale-insufficient-stock',
          lines: [
            TradeLineDraft(productId: productId, quantity: 1, unitPrice: 5000),
          ],
          paidAmount: 5000,
        ),
      ),
      throwsStateError,
    );

    final db = await store.database;
    expect(await db.query('business_documents'), isEmpty);
    expect(await db.query('journal_entries'), isEmpty);
    expect(await db.query('inventory_movements'), isEmpty);
  });

  test('repair consumption posts parts expense and stock decrease as one transaction', () async {
    final productId = await addProduct();
    await trades.recordPurchase(
      TradeDocumentDraft(
        documentDate: '2026-11-13',
        counterpartyName: 'فروشنده',
        idempotencyKey: 'repair-purchase',
        lines: [
          TradeLineDraft(productId: productId, quantity: 5, unitPrice: 400),
        ],
      ),
    );

    final repairId = await trades.recordRepairConsumption(
      documentDate: '2026-11-14',
      repairId: 'repair-55',
      customerName: 'مشتری تعمیر',
      customerId: 'customer-55',
      idempotencyKey: 'repair-consumption-55',
      parts: [
        TradeLineDraft(productId: productId, quantity: 2, unitPrice: 0),
      ],
    );
    expect(await trades.recordRepairConsumption(
      documentDate: '2026-11-14',
      repairId: 'repair-55',
      customerName: 'مشتری تعمیر',
      customerId: 'customer-55',
      idempotencyKey: 'repair-consumption-55',
      parts: [
        TradeLineDraft(productId: productId, quantity: 2, unitPrice: 0),
      ],
    ), repairId);

    expect(await store.getStockOnHand(productId), 3);
    expect((await accountTotals('5100'))['total_debit'], 800);
    expect((await accountTotals('1200'))['total_credit'], 800);
    final document = (await trades.getDocuments(type: 'repair_consumption')).single;
    expect(document['total_amount'], 800);
    expect(await trades.getDocumentLines(repairId), hasLength(1));
  });

  test('customer return restores stock, reverses VAT and cost, and caps returned quantity', () async {
    final productId = await addProduct();
    await trades.recordPurchase(
      TradeDocumentDraft(
        documentDate: '2026-11-12',
        counterpartyName: 'فروشنده',
        idempotencyKey: 'customer-return-purchase',
        lines: [
          TradeLineDraft(productId: productId, quantity: 10, unitPrice: 1000),
        ],
      ),
    );
    final saleId = await trades.recordSale(
      TradeDocumentDraft(
        documentDate: '2026-11-13',
        counterpartyName: 'مشتری برگشت',
        counterpartyId: 'customer-return-1',
        idempotencyKey: 'customer-return-sale',
        lines: [
          TradeLineDraft(productId: productId, quantity: 4, unitPrice: 2000),
        ],
        vatRate: 10,
        paidAmount: 0,
      ),
    );
    final saleLines = await trades.getDocumentLines(saleId);

    final returnDraft = ReturnDocumentDraft(
      documentDate: '2026-11-14',
      sourceDocumentId: saleId,
      counterpartyName: 'مشتری برگشت',
      counterpartyId: 'customer-return-1',
      idempotencyKey: 'customer-return-test',
      lines: [
        ReturnLineDraft(sourceLineId: saleLines.single['id'] as int, quantity: 2),
      ],
    );
    await trades.recordCustomerReturn(returnDraft);
    expect(await store.getStockOnHand(productId), 8);

    expect((await accountTotals('4050'))['total_debit'], 4000);
    expect((await accountTotals('2100'))['total_debit'], 400);
    expect((await accountTotals('1200'))['total_debit'], 2000);
    expect((await accountTotals('5000'))['total_credit'], 2000);

    await expectLater(
      trades.recordCustomerReturn(
        ReturnDocumentDraft(
          documentDate: '2026-11-14',
          sourceDocumentId: saleId,
          counterpartyName: 'مشتری برگشت',
          idempotencyKey: 'customer-return-too-many',
          lines: [
            ReturnLineDraft(
              sourceLineId: saleLines.single['id'] as int,
              quantity: 3,
            ),
          ],
        ),
      ),
      throwsStateError,
    );
    expect(await store.getStockOnHand(productId), 8);
    expect(await trades.getDocuments(type: 'customer_return'), hasLength(1));
  });

  test('supplier return decreases stock and reverses payable and purchase VAT once', () async {
    final productId = await addProduct();
    final purchaseId = await trades.recordPurchase(
      TradeDocumentDraft(
        documentDate: '2026-11-12',
        counterpartyName: 'فروشنده برگشت',
        counterpartyId: 'supplier-return-1',
        idempotencyKey: 'supplier-return-source',
        lines: [
          TradeLineDraft(productId: productId, quantity: 10, unitPrice: 1000),
        ],
        vatRate: 10,
      ),
    );
    final purchaseLines = await trades.getDocumentLines(purchaseId);
    final returnId = await trades.recordSupplierReturn(
      ReturnDocumentDraft(
        documentDate: '2026-11-14',
        sourceDocumentId: purchaseId,
        counterpartyName: 'فروشنده برگشت',
        counterpartyId: 'supplier-return-1',
        idempotencyKey: 'supplier-return-test',
        lines: [
          ReturnLineDraft(
            sourceLineId: purchaseLines.single['id'] as int,
            quantity: 2,
          ),
        ],
      ),
    );
    expect(returnId, greaterThan(0));
    expect(await store.getStockOnHand(productId), 8);

    expect((await accountTotals('2000'))['total_debit'], 2200);
    expect((await accountTotals('1200'))['credit_total'], isNull);
    expect((await accountTotals('1200'))['total_credit'], 2000);
    expect((await accountTotals('2110'))['total_credit'], 200);

    await expectLater(
      trades.recordSupplierReturn(
        ReturnDocumentDraft(
          documentDate: '2026-11-14',
          sourceDocumentId: purchaseId,
          counterpartyName: 'فروشنده برگشت',
          idempotencyKey: 'supplier-return-excess',
          lines: [
            ReturnLineDraft(
              sourceLineId: purchaseLines.single['id'] as int,
              quantity: 9,
            ),
          ],
        ),
      ),
      throwsStateError,
    );
    expect(await store.getStockOnHand(productId), 8);
  });

  test('customer receipt and supplier payment are posted to the correct party control accounts', () async {
    final receiptId = await trades.recordCustomerReceipt(
      PartyPaymentDraft(
        documentDate: '2026-11-14',
        counterpartyName: 'مشتری دریافت',
        counterpartyId: 'customer-pay-1',
        amount: 2500,
        idempotencyKey: 'receipt-test-1',
        cashAccountCode: '1010',
      ),
    );
    expect(receiptId, greaterThan(0));
    await trades.recordSupplierPayment(
      PartyPaymentDraft(
        documentDate: '2026-11-14',
        counterpartyName: 'فروشنده پرداخت',
        counterpartyId: 'supplier-pay-1',
        amount: 1500,
        idempotencyKey: 'payment-test-1',
      ),
    );

    expect((await accountTotals('1010'))['total_debit'], 2500);
    expect((await accountTotals('1100'))['total_credit'], 2500);
    expect((await accountTotals('2000'))['total_debit'], 1500);
    expect((await accountTotals('1000'))['total_credit'], 1500);

    final db = await store.database;
    expect(await db.query('business_documents'), hasLength(2));
    expect(await db.query('journal_entries'), hasLength(2));
  });

  test('business documents cannot be edited or deleted after posting', () async {
    final productId = await addProduct();
    final documentId = await trades.recordPurchase(
      TradeDocumentDraft(
        documentDate: '2026-11-14',
        counterpartyName: 'فروشنده',
        idempotencyKey: 'immutable-purchase',
        lines: [
          TradeLineDraft(productId: productId, quantity: 1, unitPrice: 1000),
        ],
      ),
    );
    final db = await store.database;
    await expectLater(
      db.update(
        'business_documents',
        {'counterparty_name': 'ویرایش غیرمجاز'},
        where: 'id = ?',
        whereArgs: [documentId],
      ),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      db.delete(
        'business_documents',
        where: 'id = ?',
        whereArgs: [documentId],
      ),
      throwsA(isA<DatabaseException>()),
    );
  });
}
