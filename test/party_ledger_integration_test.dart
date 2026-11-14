import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:khadamat_fanni_hosein/app_database.dart';
import 'package:khadamat_fanni_hosein/party_repository.dart';
import 'package:khadamat_fanni_hosein/trade_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late AppDatabase store;
  late TradeRepository trades;
  late PartyRepository parties;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('khadamat_party_ledger_');
    store = AppDatabase(databasePath: '${tempDir.path}/ledger.db');
    trades = TradeRepository(store);
    parties = PartyRepository(store);
    await store.database;
  });

  tearDown(() async {
    await store.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('linked customer receipts and returns inherit the invoice party in the ledger', () async {
    final productId = await store.insert('products', {
      'نام کالا': 'قطعه دفتر مشتری',
      'موجودی': '10',
      'بهای تمام‌شده هر واحد': '500',
    });
    const customerId = 'customer-ledger-inherit';
    await parties.ensureParty(const PartyDraft(
      partyType: 'customer',
      displayName: 'مشتری دفتر',
      preferredId: customerId,
    ));

    final saleId = await trades.recordSale(
      TradeDocumentDraft(
        documentDate: '2026-11-14',
        counterpartyName: 'مشتری دفتر',
        counterpartyId: customerId,
        idempotencyKey: 'ledger-customer-sale',
        lines: [
          TradeLineDraft(productId: productId, quantity: 4, unitPrice: 2000),
        ],
      ),
    );

    await trades.recordCustomerReceipt(
      PartyPaymentDraft(
        documentDate: '2026-11-14',
        counterpartyName: 'مشتری دفتر',
        amount: 1000,
        idempotencyKey: 'ledger-customer-receipt',
        referenceId: saleId.toString(),
      ),
    );

    final saleLines = await trades.getDocumentLines(saleId);
    await trades.recordCustomerReturn(
      ReturnDocumentDraft(
        documentDate: '2026-11-15',
        sourceDocumentId: saleId,
        counterpartyName: 'نام اشتباه واردشده',
        idempotencyKey: 'ledger-customer-return',
        lines: [
          ReturnLineDraft(
            sourceLineId: saleLines.single['id'] as int,
            quantity: 1,
          ),
        ],
      ),
    );

    final statement = await parties.getPartyStatement(customerId);
    expect(statement['closing_balance'], 5000);
    expect(statement['closing_label'], 'بدهی مشتری');
    final party = statement['party'] as Map<String, Object?>;
    expect(party['display_name'], 'مشتری دفتر');
    final lines = statement['lines'] as List<Map<String, Object?>>;
    expect(lines, hasLength(3));
    expect(lines.any((line) => line['reference_type'] == 'customer_receipt'), isTrue);
    expect(lines.any((line) => line['reference_type'] == 'customer_return'), isTrue);

    final returnDocuments = await trades.getDocuments(type: 'customer_return');
    expect(returnDocuments.single['counterparty_id'], customerId);
    expect(returnDocuments.single['counterparty_name'], 'مشتری دفتر');
  });

  test('linked supplier payments and returns inherit the invoice party in the ledger', () async {
    final productId = await store.insert('products', {
      'نام کالا': 'قطعه دفتر فروشنده',
      'موجودی': '0',
      'بهای تمام‌شده هر واحد': '0',
    });
    const supplierId = 'supplier-ledger-inherit';
    await parties.ensureParty(const PartyDraft(
      partyType: 'supplier',
      displayName: 'فروشنده دفتر',
      preferredId: supplierId,
    ));

    final purchaseId = await trades.recordPurchase(
      TradeDocumentDraft(
        documentDate: '2026-11-14',
        counterpartyName: 'فروشنده دفتر',
        counterpartyId: supplierId,
        idempotencyKey: 'ledger-supplier-purchase',
        lines: [
          TradeLineDraft(productId: productId, quantity: 5, unitPrice: 1000),
        ],
      ),
    );

    await trades.recordSupplierPayment(
      PartyPaymentDraft(
        documentDate: '2026-11-14',
        counterpartyName: 'فروشنده دفتر',
        amount: 1000,
        idempotencyKey: 'ledger-supplier-payment',
        referenceId: purchaseId.toString(),
      ),
    );

    final purchaseLines = await trades.getDocumentLines(purchaseId);
    await trades.recordSupplierReturn(
      ReturnDocumentDraft(
        documentDate: '2026-11-15',
        sourceDocumentId: purchaseId,
        counterpartyName: 'نام اشتباه واردشده',
        idempotencyKey: 'ledger-supplier-return',
        lines: [
          ReturnLineDraft(
            sourceLineId: purchaseLines.single['id'] as int,
            quantity: 1,
          ),
        ],
      ),
    );

    final statement = await parties.getPartyStatement(supplierId);
    expect(statement['closing_balance'], 3000);
    expect(statement['closing_label'], 'طلب فروشنده');
    final lines = statement['lines'] as List<Map<String, Object?>>;
    expect(lines, hasLength(3));
    expect(lines.any((line) => line['reference_type'] == 'supplier_payment'), isTrue);
    expect(lines.any((line) => line['reference_type'] == 'supplier_return'), isTrue);

    final returnDocuments = await trades.getDocuments(type: 'supplier_return');
    expect(returnDocuments.single['counterparty_id'], supplierId);
    expect(returnDocuments.single['counterparty_name'], 'فروشنده دفتر');
  });

  test('party ledger pages preserve opening and closing balances', () async {
    final productId = await store.insert('products', {
      'نام کالا': 'قطعه صفحه‌بندی دفتر',
      'موجودی': '10',
      'بهای تمام‌شده هر واحد': '100',
    });
    const customerId = 'customer-ledger-pages';
    await parties.ensureParty(const PartyDraft(
      partyType: 'customer',
      displayName: 'مشتری صفحه‌بندی',
      preferredId: customerId,
    ));
    await trades.recordSale(TradeDocumentDraft(
      documentDate: '2026-11-10',
      counterpartyName: 'مشتری صفحه‌بندی',
      counterpartyId: customerId,
      idempotencyKey: 'ledger-page-sale-1',
      lines: [TradeLineDraft(productId: productId, quantity: 1, unitPrice: 1000)],
    ));
    await trades.recordSale(TradeDocumentDraft(
      documentDate: '2026-11-11',
      counterpartyName: 'مشتری صفحه‌بندی',
      counterpartyId: customerId,
      idempotencyKey: 'ledger-page-sale-middle',
      lines: [TradeLineDraft(productId: productId, quantity: 1, unitPrice: 500)],
    ));
    await trades.recordSale(TradeDocumentDraft(
      documentDate: '2026-11-12',
      counterpartyName: 'مشتری صفحه‌بندی',
      counterpartyId: customerId,
      idempotencyKey: 'ledger-page-sale-2',
      lines: [TradeLineDraft(productId: productId, quantity: 1, unitPrice: 2000)],
    ));

    final first = await parties.getPartyStatementPage(
      customerId,
      fromDate: '2026-11-11',
      toDate: '2026-11-12',
      limit: 1,
    );
    expect(first['opening_balance'], 1000);
    expect(first['closing_balance'], 3500);
    expect(first['total_lines'], 2);
    expect(first['lines'], hasLength(1));
    expect(first['has_more'], isTrue);
    expect((first['lines'] as List<Map<String, Object?>>).single['running_balance'], 1500);

    final second = await parties.getPartyStatementPage(
      customerId,
      fromDate: '2026-11-11',
      toDate: '2026-11-12',
      limit: 1,
      offset: 1,
    );
    expect(second['has_more'], isFalse);
    expect(second['offset'], 1);
    expect(second['closing_balance'], 3500);
    expect((second['lines'] as List<Map<String, Object?>>).single['running_balance'], 3500);
  });

  test('a linked settlement cannot be posted to a different party', () async {
    final productId = await store.insert('products', {
      'نام کالا': 'قطعه کنترل طرف حساب',
      'موجودی': '1',
      'بهای تمام‌شده هر واحد': '0',
    });
    final saleId = await trades.recordSale(
      TradeDocumentDraft(
        documentDate: '2026-11-14',
        counterpartyName: 'مشتری اصلی',
        counterpartyId: 'customer-original',
        idempotencyKey: 'ledger-party-mismatch-sale',
        lines: [
          TradeLineDraft(productId: productId, quantity: 1, unitPrice: 2000),
        ],
      ),
    );

    await expectLater(
      trades.recordCustomerReceipt(
        PartyPaymentDraft(
          documentDate: '2026-11-14',
          counterpartyName: 'مشتری دیگر',
          counterpartyId: 'customer-other',
          amount: 100,
          idempotencyKey: 'ledger-party-mismatch-receipt',
          referenceId: saleId.toString(),
        ),
      ),
      throwsStateError,
    );

    await expectLater(
      trades.recordCustomerReturn(
        ReturnDocumentDraft(
          documentDate: '2026-11-15',
          sourceDocumentId: saleId,
          counterpartyName: 'مشتری دیگر',
          counterpartyId: 'customer-other',
          idempotencyKey: 'ledger-party-mismatch-return',
          lines: [
            ReturnLineDraft(
              sourceLineId: (await trades.getDocumentLines(saleId)).single['id'] as int,
              quantity: 1,
            ),
          ],
        ),
      ),
      throwsStateError,
    );
  });
}
