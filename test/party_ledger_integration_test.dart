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


  test('an unused contact can be deleted together with its role links', () async {
    final id = await parties.ensureParty(const PartyDraft(
      partyType: 'customer',
      displayName: 'مخاطب بدون سابقه',
      phone: '09129998877',
    ));

    await parties.deleteParty(id);

    expect(await parties.getParties(), isEmpty);
    expect(await parties.getPartyRoles(id), isEmpty);
  });

  test('a contact linked to a repair intake cannot be deleted', () async {
    const id = 'party-protected-repair';
    await parties.ensureParty(const PartyDraft(
      partyType: 'customer',
      displayName: 'مشتری دارای پذیرش تعمیر',
      preferredId: id,
    ));
    await store.insert('repairs', {
      'نام مشتری': 'مشتری دارای پذیرش تعمیر',
      'شناسه طرف حساب': id,
      'نوع دستگاه': 'جاروبرقی',
    });

    await expectLater(parties.deleteParty(id), throwsA(isA<StateError>()));
    expect((await parties.getParties()).single['id'], id);
  });

  test('a contact with invoice history cannot be deleted', () async {
    final id = await parties.ensureParty(const PartyDraft(
      partyType: 'customer',
      displayName: 'مخاطب دارای فاکتور',
      preferredId: 'party-protected-history',
    ));
    final productId = await store.insert('products', {
      'نام کالا': 'کالای پرونده مخاطب',
      'موجودی': '5',
      'بهای تمام‌شده هر واحد': '400',
    });
    await trades.recordSale(
      TradeDocumentDraft(
        documentDate: '2026-11-16',
        counterpartyName: 'مخاطب دارای فاکتور',
        counterpartyId: id,
        idempotencyKey: 'protected-contact-delete',
        lines: [
          TradeLineDraft(productId: productId, quantity: 1, unitPrice: 900),
        ],
      ),
    );

    await expectLater(
      parties.deleteParty(id),
      throwsA(isA<StateError>()),
    );
    expect((await parties.getParties()).single['id'], id);
    expect(await parties.getPartyRoles(id), contains('customer'));
  });

  test('contact activity combines purchase sale and repair history', () async {
    const contactId = 'party-with-complete-activity';
    await parties.ensureParty(const PartyDraft(
      partyType: 'customer',
      additionalRoles: ['supplier'],
      displayName: 'شخص دارای سابقه کامل',
      preferredId: contactId,
    ));
    final productId = await store.insert('products', {
      'نام کالا': 'کالای سابقه',
      'موجودی': '10',
      'بهای تمام‌شده هر واحد': '500',
    });
    await trades.recordSale(
      TradeDocumentDraft(
        documentDate: '2026-11-15',
        counterpartyName: 'شخص دارای سابقه کامل',
        counterpartyId: contactId,
        idempotencyKey: 'profile-activity-sale',
        lines: [
          TradeLineDraft(productId: productId, quantity: 1, unitPrice: 800),
        ],
      ),
    );
    await trades.recordPurchase(
      TradeDocumentDraft(
        documentDate: '2026-11-16',
        counterpartyName: 'شخص دارای سابقه کامل',
        counterpartyId: contactId,
        idempotencyKey: 'profile-activity-purchase',
        lines: [
          TradeLineDraft(productId: productId, quantity: 2, unitPrice: 450),
        ],
      ),
    );
    await store.insert('repairs', {
      'نام مشتری': 'شخص دارای سابقه کامل',
      'شناسه طرف حساب': contactId,
      'نوع دستگاه': 'دریل',
      'وضعیت': 'در حال تعمیر',
    });

    final activity = await parties.getPartyActivity(contactId);
    expect(activity['documents'], hasLength(2));
    expect(
      (activity['documents'] ?? []).map((row) => row['document_type']),
      containsAll(['sale', 'purchase']),
    );
    expect(activity['repairs'], hasLength(1));
    expect(activity['repairs']!.single['نوع دستگاه'], 'دریل');
  });

  test('one contact can be both a customer and a supplier', () async {
    const sharedId = 'party-id-multiple-roles';
    final customerId = await parties.ensureParty(const PartyDraft(
      partyType: 'customer',
      displayName: 'مشتری و فروشنده',
      phone: '۰۹۱۲۱۲۳۴۵۶۷',
      preferredId: sharedId,
    ));

    final supplierId = await parties.ensureParty(const PartyDraft(
      partyType: 'supplier',
      displayName: 'مشتری و فروشنده',
      phone: '09121234567',
      preferredId: sharedId,
    ));

    expect(customerId, sharedId);
    expect(supplierId, customerId);
    expect(await parties.getPartyRoles(sharedId), containsAll(['customer', 'supplier']));
    expect((await parties.getParties(partyType: 'customer')).single['id'], sharedId);
    expect((await parties.getParties(partyType: 'supplier')).single['id'], sharedId);

    final statement = await parties.getPartyStatementPage(sharedId);
    expect(statement['roles'], containsAll(['customer', 'supplier']));
    expect(statement['closing_label'], 'تسویه');
  });

  test('same person with equivalent phone formatting is not duplicated across roles', () async {
    final customerId = await parties.ensureParty(const PartyDraft(
      partyType: 'customer',
      displayName: 'علی رضایی',
      phone: '09120001122',
    ));
    final supplierId = await parties.ensureParty(const PartyDraft(
      partyType: 'supplier',
      displayName: 'علی رضایی',
      phone: '+98 912 000 1122',
    ));

    expect(supplierId, customerId);
    expect((await parties.getParties()).where((party) => party['id'] == customerId), hasLength(1));
    expect(await parties.getPartyRoles(customerId), containsAll(['customer', 'supplier']));
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


  test('customer advance is automatically allocated once to future sales', () async {
    const customerId = 'customer-advance-auto-allocation';
    await parties.ensureParty(const PartyDraft(
      partyType: 'customer',
      displayName: 'مشتری دارای بیعانه',
      preferredId: customerId,
    ));
    final productId = await store.insert('products', {
      'نام کالا': 'کالای بیعانه مشتری',
      'موجودی': '10',
      'بهای تمام‌شده هر واحد': '500',
    });

    await trades.recordCustomerReceipt(PartyPaymentDraft(
      documentDate: '2026-11-10',
      counterpartyName: 'مشتری دارای بیعانه',
      counterpartyId: customerId,
      amount: 3000,
      idempotencyKey: 'customer-advance-before-sale',
    ));

    final saleId = await trades.recordSale(TradeDocumentDraft(
      documentDate: '2026-11-11',
      counterpartyName: 'مشتری دارای بیعانه',
      counterpartyId: customerId,
      idempotencyKey: 'customer-advance-sale',
      lines: [TradeLineDraft(productId: productId, quantity: 1, unitPrice: 2000)],
    ));

    expect(await trades.getOutstandingAmount(saleId), 0);
    final db = await store.database;
    final allocations = await db.query(
      'invoice_payment_allocations',
      where: 'invoice_document_id = ?',
      whereArgs: [saleId],
    );
    expect(allocations, hasLength(1));
    expect(allocations.single['amount'], 2000);

    var statement = await parties.getPartyStatementPage(customerId);
    expect(statement['available_customer_advance'], 1000);
    expect(statement['closing_balance'], -1000);

    final secondSaleId = await trades.recordSale(TradeDocumentDraft(
      documentDate: '2026-11-12',
      counterpartyName: 'مشتری دارای بیعانه',
      counterpartyId: customerId,
      idempotencyKey: 'customer-advance-second-sale',
      lines: [TradeLineDraft(productId: productId, quantity: 1, unitPrice: 1500)],
    ));
    expect(await trades.getOutstandingAmount(secondSaleId), 500);
    statement = await parties.getPartyStatementPage(customerId);
    expect(statement['available_customer_advance'], 0);
    expect(statement['closing_balance'], 500);

    // Allocation is metadata only; the receipt and sale journals are not reposted.
    final entries = await db.query('journal_entries');
    expect(entries, hasLength(5));
    final allAllocations = await db.query('invoice_payment_allocations');
    expect(allAllocations, hasLength(2));
    expect(allAllocations.fold<int>(
      0,
      (sum, row) => sum + (row['amount'] as num).toInt(),
    ), 3000);
  });

  test('supplier prepayment is automatically allocated and remaining amount is visible', () async {
    const supplierId = 'supplier-advance-auto-allocation';
    await parties.ensureParty(const PartyDraft(
      partyType: 'supplier',
      displayName: 'فروشنده دارای پیش‌پرداخت',
      preferredId: supplierId,
    ));
    final productId = await store.insert('products', {
      'نام کالا': 'کالای پیش‌پرداخت فروشنده',
      'موجودی': '0',
      'بهای تمام‌شده هر واحد': '0',
    });

    await trades.recordSupplierPayment(PartyPaymentDraft(
      documentDate: '2026-11-10',
      counterpartyName: 'فروشنده دارای پیش‌پرداخت',
      counterpartyId: supplierId,
      amount: 2500,
      idempotencyKey: 'supplier-prepayment-before-purchase',
    ));

    final purchaseId = await trades.recordPurchase(TradeDocumentDraft(
      documentDate: '2026-11-11',
      counterpartyName: 'فروشنده دارای پیش‌پرداخت',
      counterpartyId: supplierId,
      idempotencyKey: 'supplier-prepayment-purchase',
      lines: [TradeLineDraft(productId: productId, quantity: 2, unitPrice: 1000)],
    ));

    expect(await trades.getOutstandingAmount(purchaseId), 0);
    final statement = await parties.getPartyStatementPage(supplierId);
    expect(statement['available_supplier_prepayment'], 500);
    expect(statement['closing_balance'], -500);

    final db = await store.database;
    final allocations = await db.query(
      'invoice_payment_allocations',
      where: 'invoice_document_id = ?',
      whereArgs: [purchaseId],
    );
    expect(allocations, hasLength(1));
    expect(allocations.single['amount'], 2000);
    expect(await db.query('journal_entries'), hasLength(2));
  });


  test('historical party statement excludes advances allocated after period end', () async {
    const customerId = 'customer-historical-advance';
    await parties.ensureParty(const PartyDraft(
      partyType: 'customer',
      displayName: 'مشتری بیعانه تاریخی',
      preferredId: customerId,
    ));
    final productId = await store.insert('products', {
      'نام کالا': 'کالای مانده تاریخی',
      'موجودی': '5',
      'بهای تمام‌شده هر واحد': '100',
    });

    await trades.recordCustomerReceipt(PartyPaymentDraft(
      documentDate: '2026-11-10',
      counterpartyName: 'مشتری بیعانه تاریخی',
      counterpartyId: customerId,
      amount: 3000,
      idempotencyKey: 'historical-advance-receipt',
    ));

    final beforeAllocation = await parties.getPartyStatementPage(
      customerId,
      toDate: '2026-11-10',
    );
    expect(beforeAllocation['available_customer_advance'], 3000);

    await trades.recordSale(TradeDocumentDraft(
      documentDate: '2026-11-11',
      counterpartyName: 'مشتری بیعانه تاریخی',
      counterpartyId: customerId,
      idempotencyKey: 'historical-advance-sale',
      lines: [TradeLineDraft(productId: productId, quantity: 1, unitPrice: 2000)],
    ));

    final afterAllocation = await parties.getPartyStatementPage(
      customerId,
      toDate: '2026-11-11',
    );
    expect(afterAllocation['available_customer_advance'], 1000);
    final current = await parties.getPartyStatementPage(customerId);
    expect(current['available_customer_advance'], 1000);
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
    // This later posting must not change the closing balance for Nov 11-12.
    await trades.recordSale(TradeDocumentDraft(
      documentDate: '2026-11-13',
      counterpartyName: 'مشتری صفحه‌بندی',
      counterpartyId: customerId,
      idempotencyKey: 'ledger-page-sale-after-range',
      lines: [TradeLineDraft(productId: productId, quantity: 1, unitPrice: 9000)],
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


  test('linked customer receipt cannot exceed the remaining sale balance', () async {
    final productId = await store.insert('products', {
      'نام کالا': 'کالای کنترل اضافه‌دریافت',
      'موجودی': '5',
      'بهای تمام‌شده هر واحد': '100',
    });
    const customerId = 'customer-no-overpayment';
    await parties.ensureParty(const PartyDraft(
      partyType: 'customer',
      displayName: 'مشتری کنترل اضافه‌دریافت',
      preferredId: customerId,
    ));
    final saleId = await trades.recordSale(TradeDocumentDraft(
      documentDate: '2026-11-17',
      counterpartyName: 'مشتری کنترل اضافه‌دریافت',
      counterpartyId: customerId,
      idempotencyKey: 'customer-overpayment-sale',
      lines: [TradeLineDraft(productId: productId, quantity: 1, unitPrice: 1000)],
    ));

    await expectLater(
      trades.recordCustomerReceipt(PartyPaymentDraft(
        documentDate: '2026-11-17',
        counterpartyName: 'مشتری کنترل اضافه‌دریافت',
        counterpartyId: customerId,
        amount: 1001,
        referenceId: saleId.toString(),
        idempotencyKey: 'customer-overpayment-receipt',
      )),
      throwsStateError,
    );
    expect(await trades.getOutstandingAmount(saleId), 1000);
    expect((await trades.getDocuments(type: 'customer_receipt')), isEmpty);
  });

  test('linked supplier payment cannot exceed the remaining purchase balance', () async {
    final productId = await store.insert('products', {
      'نام کالا': 'کالای کنترل اضافه‌پرداخت',
      'موجودی': '0',
      'بهای تمام‌شده هر واحد': '0',
    });
    const supplierId = 'supplier-no-overpayment';
    await parties.ensureParty(const PartyDraft(
      partyType: 'supplier',
      displayName: 'فروشنده کنترل اضافه‌پرداخت',
      preferredId: supplierId,
    ));
    final purchaseId = await trades.recordPurchase(TradeDocumentDraft(
      documentDate: '2026-11-17',
      counterpartyName: 'فروشنده کنترل اضافه‌پرداخت',
      counterpartyId: supplierId,
      idempotencyKey: 'supplier-overpayment-purchase',
      lines: [TradeLineDraft(productId: productId, quantity: 1, unitPrice: 1000)],
    ));

    await expectLater(
      trades.recordSupplierPayment(PartyPaymentDraft(
        documentDate: '2026-11-17',
        counterpartyName: 'فروشنده کنترل اضافه‌پرداخت',
        counterpartyId: supplierId,
        amount: 1001,
        referenceId: purchaseId.toString(),
        idempotencyKey: 'supplier-overpayment-payment',
      )),
      throwsStateError,
    );
    expect(await trades.getOutstandingAmount(purchaseId), 1000);
    expect((await trades.getDocuments(type: 'supplier_payment')), isEmpty);
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
