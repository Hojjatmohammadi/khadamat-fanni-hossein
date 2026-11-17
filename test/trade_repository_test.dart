import 'dart:convert';
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

  test('purchase discounts and partial sales preserve exact inventory value', () async {
    final productId = await addProduct();

    await trades.recordPurchase(
      TradeDocumentDraft(
        documentDate: '2026-11-16',
        counterpartyName: 'فروشنده با تخفیف',
        idempotencyKey: 'exact-cost-purchase',
        lines: [
          TradeLineDraft(productId: productId, quantity: 3, unitPrice: 100),
        ],
        discountAmount: 1,
      ),
    );

    final purchase = (await trades.getDocuments(type: 'purchase')).single;
    expect(purchase['subtotal'], 300);
    expect(purchase['discount_amount'], 1);
    expect(purchase['total_amount'], 299);
    final db = await store.database;
    final incoming = await db.query(
      'inventory_movements',
      where: 'movement_type = ?',
      whereArgs: ['purchase'],
    );
    expect(incoming.single['total_cost'], 299);
    expect(await store.getStockOnHand(productId), 3);

    await trades.recordSale(
      TradeDocumentDraft(
        documentDate: '2026-11-16',
        counterpartyName: 'مشتری فروش جزئی',
        idempotencyKey: 'exact-cost-partial-sale',
        lines: [
          TradeLineDraft(productId: productId, quantity: 2, unitPrice: 200),
        ],
      ),
    );

    final outgoing = await db.query(
      'inventory_movements',
      where: 'movement_type = ?',
      whereArgs: ['sale'],
    );
    expect(outgoing.single['total_cost'], 199);
    expect(await store.getStockOnHand(productId), 1);
    expect((await accountTotals('5000'))['total_debit'], 199);
    final valuation = await db.rawQuery(
      'SELECT COALESCE(SUM(CASE WHEN quantity_delta > 0 THEN total_cost '
      'ELSE -total_cost END), 0) AS value '
      'FROM inventory_movements WHERE product_id = ?',
      [productId],
    );
    expect(valuation.single['value'], 100);
  });

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

  test('purchase invoice and immutable display snapshot are archived atomically', () async {
    final productId = await addProduct(name: 'برد الکترونیکی');
    final purchaseId = await trades.recordPurchase(
      TradeDocumentDraft(
        documentDate: '2026-11-15',
        counterpartyName: 'فروشنده قطعات',
        idempotencyKey: 'purchase-archive-test',
        lines: [
          TradeLineDraft(productId: productId, quantity: 2, unitPrice: 3500),
        ],
        discountAmount: 500,
        shippingCost: 1000,
        paidAmount: 1000,
      ),
      invoiceHeaderSnapshot: {
        'shopName': 'خدمات فنی حسین',
        'currency': 'ریال',
        'ownerName': 'مسئول خرید',
        'phone': '09150000000',
        'stampImageBase64': 'purchase-stamp-at-issue',
      },
    );

    final db = await store.database;
    final archiveRows = await db.query(
      'invoice_archives',
      where: 'business_document_id = ?',
      whereArgs: [purchaseId],
    );
    expect(archiveRows, hasLength(1));
    final snapshot = jsonDecode(archiveRows.single['snapshot_json'] as String)
        as Map<String, dynamic>;
    expect(snapshot['documentType'], 'purchase');
    expect(snapshot['shopName'], 'خدمات فنی حسین');
    expect(snapshot['currency'], 'ریال');
    expect(snapshot['stampImageBase64'], 'purchase-stamp-at-issue');
    expect(snapshot['counterpartyName'], 'فروشنده قطعات');
    expect(snapshot['subtotal'], 7000);
    expect(snapshot['discountAmount'], 500);
    expect(snapshot['chargesAmount'], 1000);
    expect(snapshot['totalAmount'], 7500);
    expect(snapshot['paidAmount'], 1000);
    expect(snapshot['outstandingAmount'], 6500);
    expect(snapshot['items'], hasLength(1));
    final item = (snapshot['items'] as List).single as Map;
    expect(item['productName'], 'برد الکترونیکی');
    expect(item['lineTotal'], 7000);
    expect(item['netLineTotal'], 7500);
  });

  test('sale invoice and immutable display snapshot are archived atomically', () async {
    final productId = await addProduct(name: 'خازن 100 میکرو');
    await trades.recordPurchase(
      TradeDocumentDraft(
        documentDate: '2026-11-13',
        counterpartyName: 'فروشنده',
        idempotencyKey: 'invoice-archive-purchase',
        lines: [
          TradeLineDraft(productId: productId, quantity: 5, unitPrice: 1000),
        ],
      ),
    );

    final saleId = await trades.recordSale(
      TradeDocumentDraft(
        documentDate: '2026-11-14',
        counterpartyName: 'مشتری فاکتور',
        idempotencyKey: 'invoice-archive-sale',
        lines: [
          TradeLineDraft(productId: productId, quantity: 2, unitPrice: 2500),
        ],
        discountAmount: 500,
        paidAmount: 4500,
      ),
      invoiceHeaderSnapshot: {
        'shopName': 'خدمات فنی حسین',
        'currency': 'ریال',
        'ownerName': 'حجت محمدی',
        'phone': '09155637505',
        'postalCode': '1234567890',
        'address': 'عشق آباد',
        'stampImageBase64': 'stamp-fixed-at-issue',
        'signatureImageBase64': 'signature-fixed-at-issue',
        'appLogoBase64': 'logo-fixed-at-issue',
      },
    );

    final db = await store.database;
    final archiveRows = await db.query(
      'invoice_archives',
      where: 'business_document_id = ?',
      whereArgs: [saleId],
    );
    expect(archiveRows, hasLength(1));
    final snapshot = jsonDecode(archiveRows.single['snapshot_json'] as String)
        as Map<String, dynamic>;
    expect(snapshot['shopName'], 'خدمات فنی حسین');
    expect(snapshot['currency'], 'ریال');
    expect(snapshot['stampImageBase64'], 'stamp-fixed-at-issue');
    expect(snapshot['signatureImageBase64'], 'signature-fixed-at-issue');
    expect(snapshot['appLogoBase64'], 'logo-fixed-at-issue');
    expect(snapshot['counterpartyName'], 'مشتری فاکتور');
    expect(snapshot['subtotal'], 5000);
    expect(snapshot['discountAmount'], 500);
    expect(snapshot['totalAmount'], 4500);
    expect(snapshot['paidAmount'], 4500);
    expect(snapshot['items'], hasLength(1));
    final item = (snapshot['items'] as List).single as Map;
    expect(item['productName'], 'خازن 100 میکرو');
    expect(item['lineTotal'], 5000);
    expect(item['netLineTotal'], 4500);
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
        invoiceHeaderSnapshot: {'shopName': 'خدمات فنی حسین'},
      ),
      throwsStateError,
    );

    final db = await store.database;
    expect(await db.query('business_documents'), isEmpty);
    expect(await db.query('journal_entries'), isEmpty);
    expect(await db.query('inventory_movements'), isEmpty);
    expect(await db.query('invoice_archives'), isEmpty);
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
    expect(await trades.getOutstandingAmount(saleId), 4400);

    expect((await accountTotals('4050'))['total_debit'], 4000);
    expect((await accountTotals('2100'))['total_debit'], 400);
    expect((await accountTotals('1200'))['total_debit'], 12000);
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
    expect(await trades.getOutstandingAmount(purchaseId), 8800);

    expect((await accountTotals('2000'))['total_debit'], 2200);
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
  test('linked customer receipts and supplier payments cannot exceed invoice balances', () async {
    final productId = await addProduct();
    final purchaseId = await trades.recordPurchase(
      TradeDocumentDraft(
        documentDate: '2026-11-12',
        counterpartyName: 'فروشنده تسویه',
        counterpartyId: 'supplier-balance-1',
        idempotencyKey: 'supplier-balance-purchase',
        lines: [
          TradeLineDraft(productId: productId, quantity: 1, unitPrice: 1000),
        ],
        paidAmount: 100,
      ),
    );

    await trades.recordSupplierPayment(
      PartyPaymentDraft(
        documentDate: '2026-11-13',
        counterpartyName: 'فروشنده تسویه',
        counterpartyId: 'supplier-balance-1',
        amount: 600,
        idempotencyKey: 'supplier-linked-payment',
        referenceId: purchaseId.toString(),
      ),
    );
    expect(await trades.getOutstandingAmount(purchaseId), 300);

    await expectLater(
      trades.recordSupplierPayment(
        PartyPaymentDraft(
          documentDate: '2026-11-13',
          counterpartyName: 'فروشنده تسویه',
          counterpartyId: 'supplier-balance-1',
          amount: 301,
          idempotencyKey: 'supplier-linked-overpayment',
          referenceId: purchaseId.toString(),
        ),
      ),
      throwsStateError,
    );
    expect(await trades.getOutstandingAmount(purchaseId), 300);

    final saleId = await trades.recordSale(
      TradeDocumentDraft(
        documentDate: '2026-11-14',
        counterpartyName: 'مشتری تسویه',
        counterpartyId: 'customer-balance-1',
        idempotencyKey: 'customer-balance-sale',
        lines: [
          TradeLineDraft(productId: productId, quantity: 1, unitPrice: 1500),
        ],
      ),
    );
    await trades.recordCustomerReceipt(
      PartyPaymentDraft(
        documentDate: '2026-11-14',
        counterpartyName: 'مشتری تسویه',
        counterpartyId: 'customer-balance-1',
        amount: 500,
        idempotencyKey: 'customer-linked-receipt',
        referenceId: saleId.toString(),
      ),
    );
    expect(await trades.getOutstandingAmount(saleId), 1000);

    await expectLater(
      trades.recordCustomerReceipt(
        PartyPaymentDraft(
          documentDate: '2026-11-14',
          counterpartyName: 'مشتری تسویه',
          counterpartyId: 'customer-balance-1',
          amount: 1001,
          idempotencyKey: 'customer-linked-overreceipt',
          referenceId: saleId.toString(),
        ),
      ),
      throwsStateError,
    );
    expect(await trades.getOutstandingAmount(saleId), 1000);
  });
  test('proportional discount and VAT allocation never creates negative line shares', () async {
    final productIds = <int>[];
    for (var i = 0; i < 4; i++) {
      productIds.add(await addProduct(name: 'کالای تقسیم مبلغ $i'));
    }

    await trades.recordPurchase(
      TradeDocumentDraft(
        documentDate: '2026-11-14',
        counterpartyName: 'فروشنده تقسیم مبلغ',
        idempotencyKey: 'allocation-purchase',
        lines: [
          for (final productId in productIds)
            TradeLineDraft(productId: productId, quantity: 1, unitPrice: 1),
        ],
        discountAmount: 2,
        vatRate: 50,
      ),
    );

    final purchaseLines = await trades.getDocuments(type: 'purchase');
    expect(purchaseLines.single['subtotal'], 4);
    expect(purchaseLines.single['discount_amount'], 2);
    expect(purchaseLines.single['vat_amount'], 1);
    final purchaseId = purchaseLines.single['id'] as int;
    final allocatedPurchaseLines = await trades.getDocumentLines(purchaseId);
    final purchaseDiscountShares = allocatedPurchaseLines
        .map((line) => 1 - (line['line_total'] as int))
        .toList();
    expect(purchaseDiscountShares.every((share) => share >= 0), isTrue);
    expect(purchaseDiscountShares.fold<int>(0, (sum, share) => sum + share), 2);
    expect(
      allocatedPurchaseLines
          .where((line) => line['line_total'] == 0)
          .every((line) => line['tax_amount'] == 0),
      isTrue,
      reason: 'Fully discounted purchase lines must not receive VAT',
    );

    await trades.recordSale(
      TradeDocumentDraft(
        documentDate: '2026-11-14',
        counterpartyName: 'مشتری تقسیم مبلغ',
        idempotencyKey: 'allocation-sale',
        lines: [
          for (final productId in productIds)
            TradeLineDraft(productId: productId, quantity: 1, unitPrice: 1),
        ],
        discountAmount: 2,
        vatRate: 50,
        paidAmount: 3,
      ),
    );

    final sale = (await trades.getDocuments(type: 'sale')).single;
    expect(sale['subtotal'], 4);
    expect(sale['discount_amount'], 2);
    expect(sale['vat_amount'], 1);
    expect(sale['total_amount'], 3);
    final saleId = sale['id'] as int;
    final allocatedSaleLines = await trades.getDocumentLines(saleId);
    final taxShares = allocatedSaleLines
        .map((line) => line['tax_amount'] as int)
        .toList();
    expect(taxShares.every((share) => share >= 0), isTrue);
    expect(taxShares.fold<int>(0, (sum, share) => sum + share), 1);
    expect(allocatedSaleLines.every((line) => (line['line_total'] as int) >= 0),
        isTrue);
    expect(
      allocatedSaleLines
          .where((line) => line['line_total'] == 0)
          .every((line) => line['tax_amount'] == 0),
      isTrue,
      reason: 'Fully discounted sale lines must not receive VAT',
    );
  });

}
