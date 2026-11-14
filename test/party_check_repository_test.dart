import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:khadamat_fanni_hosein/app_database.dart';
import 'package:khadamat_fanni_hosein/check_repository.dart';
import 'package:khadamat_fanni_hosein/jalali_date_field.dart';
import 'package:khadamat_fanni_hosein/party_repository.dart';
import 'package:khadamat_fanni_hosein/trade_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late AppDatabase store;
  late PartyRepository parties;
  late TradeRepository trades;
  late CheckRepository checks;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('khadamat_party_check_test_');
    store = AppDatabase(databasePath: '${tempDir.path}/party-check.db');
    parties = PartyRepository(store);
    trades = TradeRepository(store);
    checks = CheckRepository(store);
    await store.database;
  });

  tearDown(() async {
    await store.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<int> addProduct() => store.insert('products', {
        'نام کالا': 'قطعه دفتر اشخاص',
        'موجودی': '1',
        'بهای تمام‌شده هر واحد': '0',
      });

  Future<int> recordSale(int productId, String partyId) {
    return trades.recordSale(
      TradeDocumentDraft(
        documentDate: '2026-11-14',
        counterpartyName: 'مشتری آزمون',
        counterpartyId: partyId,
        idempotencyKey: 'sale-party-check-test',
        lines: [
          TradeLineDraft(productId: productId, quantity: 1, unitPrice: 2000),
        ],
      ),
    );
  }

  Future<int> recordPurchase(int productId, String partyId) {
    return trades.recordPurchase(
      TradeDocumentDraft(
        documentDate: '2026-11-14',
        counterpartyName: 'فروشنده آزمون',
        counterpartyId: partyId,
        idempotencyKey: 'purchase-party-check-test',
        lines: [
          TradeLineDraft(productId: productId, quantity: 1, unitPrice: 2000),
        ],
      ),
    );
  }

  test('Jalali parsing supports Persian digits and rejects invalid dates', () {
    final parsed = parseJalaliDate('۱۴۰۵/۰۸/۲۳');
    expect(parsed, isNotNull);
    expect(parsed!.year, 2026);
    expect(parsed.month, 11);
    expect(parsed.day, 14);

    expect(parseJalaliDate('1405/13/01'), isNull);
    expect(parseJalaliDate('1405/12/30'), isNull);
    expect(parseJalaliDate('۱۴۰۵-۰۸-۲۳'), parsed);

    expect(
      formatJalaliDate(DateTime(2026, 11, 14)),
      '۱۴۰۵/۰۸/۲۳',
    );
  });

  test('party registration is idempotent and party statement calculates customer balance', () async {
    final partyId = await parties.ensureParty(
      const PartyDraft(
        partyType: 'customer',
        displayName: '  علی   محمدی ',
        phone: '09120000000',
      ),
    );
    final repeatedId = await parties.ensureParty(
      const PartyDraft(
        partyType: 'customer',
        displayName: 'علی محمدی',
      ),
    );
    expect(repeatedId, partyId);

    final productId = await addProduct();
    await recordSale(productId, partyId);
    await trades.recordCustomerReceipt(
      PartyPaymentDraft(
        documentDate: '2026-11-14',
        counterpartyName: 'علی محمدی',
        counterpartyId: partyId,
        amount: 500,
        idempotencyKey: 'party-statement-receipt',
      ),
    );

    final statement = await parties.getPartyStatement(partyId);
    expect(statement['total_debit'], 2000);
    expect(statement['total_credit'], 500);
    expect(statement['closing_balance'], 1500);
    expect(statement['closing_label'], 'بدهی مشتری');
    expect(statement['lines'], hasLength(2));
  });

  test('incoming check reduces customer debt, clears to bank, and keeps an audit trail', () async {
    final partyId = await parties.ensureParty(
      const PartyDraft(
        partyType: 'customer',
        displayName: 'مشتری چک دریافتی',
      ),
    );
    final productId = await addProduct();
    final saleId = await recordSale(productId, partyId);

    final checkId = await checks.createCheck(
      CheckDraft(
        direction: 'incoming',
        checkNumber: '123456',
        bankName: 'بانک آزمایشی',
        drawerName: 'مشتری چک دریافتی',
        partyName: 'مشتری چک دریافتی',
        partyId: partyId,
        amount: 700,
        issueDate: '2026-11-14',
        dueDate: '2026-11-15',
        idempotencyKey: 'incoming-check-test',
        sourceDocumentId: saleId,
      ),
    );
    expect(await checks.createCheck(
      CheckDraft(
        direction: 'incoming',
        checkNumber: '123456',
        bankName: 'بانک آزمایشی',
        drawerName: 'مشتری چک دریافتی',
        partyName: 'مشتری چک دریافتی',
        partyId: partyId,
        amount: 700,
        issueDate: '2026-11-14',
        dueDate: '2026-11-15',
        idempotencyKey: 'incoming-check-test',
        sourceDocumentId: saleId,
      ),
    ), checkId);

    expect(await trades.getOutstandingAmount(saleId), 1300);
    await checks.updateCheckStatus(
      checkId: checkId,
      newStatus: 'deposited',
      reason: 'تحویل بانک شد',
      eventDate: '2026-11-14',
    );
    await checks.updateCheckStatus(
      checkId: checkId,
      newStatus: 'cleared',
      reason: 'وصول شد',
      eventDate: '2026-11-15',
    );
    expect(await trades.getOutstandingAmount(saleId), 1300);

    final statement = await parties.getPartyStatement(partyId);
    expect(statement['closing_balance'], 1300);
    final check = await checks.getCheck(checkId);
    expect(check['status'], 'cleared');
    expect(check['settlement_journal_id'], isNotNull);
    expect(await checks.getCheckEvents(checkId), hasLength(3));

    final db = await store.database;
    final checkAsset = await db.rawQuery(
      "SELECT COALESCE(SUM(debit-credit), 0) AS balance FROM journal_lines WHERE account_code = '1020'",
    );
    expect(checkAsset.single['balance'], 0);
  });

  test('bounced incoming check restores receivable and reopens invoice balance', () async {
    final partyId = await parties.ensureParty(
      const PartyDraft(
        partyType: 'customer',
        displayName: 'مشتری چک برگشتی',
      ),
    );
    final productId = await addProduct();
    final saleId = await recordSale(productId, partyId);
    final checkId = await checks.createCheck(
      CheckDraft(
        direction: 'incoming',
        checkNumber: '778899',
        bankName: 'بانک',
        drawerName: 'صادرکننده',
        partyName: 'مشتری چک برگشتی',
        partyId: partyId,
        amount: 600,
        issueDate: '2026-11-14',
        dueDate: '2026-11-16',
        idempotencyKey: 'incoming-check-bounced',
        sourceDocumentId: saleId,
      ),
    );
    expect(await trades.getOutstandingAmount(saleId), 1400);

    await checks.updateCheckStatus(
      checkId: checkId,
      newStatus: 'bounced',
      reason: 'عدم موجودی',
      eventDate: '2026-11-16',
    );
    expect(await trades.getOutstandingAmount(saleId), 2000);
    final check = await checks.getCheck(checkId);
    expect(check['status'], 'bounced');
    expect(check['reversal_journal_id'], isNotNull);
    final statement = await parties.getPartyStatement(partyId);
    expect(statement['closing_balance'], 2000);

    await expectLater(
      checks.updateCheckStatus(
        checkId: checkId,
        newStatus: 'cleared',
        reason: 'تلاش نامعتبر',
        eventDate: '2026-11-17',
      ),
      throwsStateError,
    );
  });

  test('outgoing check reduces supplier payable and records clearance separately', () async {
    final partyId = await parties.ensureParty(
      const PartyDraft(
        partyType: 'supplier',
        displayName: 'فروشنده چک پرداختی',
      ),
    );
    final productId = await addProduct();
    final purchaseId = await recordPurchase(productId, partyId);
    final checkId = await checks.createCheck(
      CheckDraft(
        direction: 'outgoing',
        checkNumber: '554433',
        bankName: 'بانک صادرکننده',
        drawerName: 'خدمات فنی حسین',
        partyName: 'فروشنده چک پرداختی',
        partyId: partyId,
        amount: 800,
        issueDate: '2026-11-14',
        dueDate: '2026-11-20',
        idempotencyKey: 'outgoing-check-test',
        sourceDocumentId: purchaseId,
      ),
    );
    expect(await trades.getOutstandingAmount(purchaseId), 1200);
    final statement = await parties.getPartyStatement(partyId);
    expect(statement['closing_balance'], 1200);
    expect(statement['closing_label'], 'طلب فروشنده');

    await checks.updateCheckStatus(
      checkId: checkId,
      newStatus: 'cleared',
      reason: 'چک پاس شد',
      eventDate: '2026-11-20',
    );
    final db = await store.database;
    final checksPayable = await db.rawQuery(
      "SELECT COALESCE(SUM(debit-credit), 0) AS balance FROM journal_lines WHERE account_code = '2020'",
    );
    expect(checksPayable.single['balance'], 0);
  });

  test('check reminders include overdue, today and tomorrow but exclude cleared checks', () async {
    final partyId = await parties.ensureParty(
      const PartyDraft(
        partyType: 'customer',
        displayName: 'شخص سررسید',
      ),
    );
    final items = [
      ('due-yesterday', '2026-11-13'),
      ('due-today', '2026-11-14'),
      ('due-tomorrow', '2026-11-15'),
      ('due-later', '2026-11-16'),
    ];
    for (final item in items) {
      await checks.createCheck(
        CheckDraft(
          direction: 'incoming',
          checkNumber: item.$1,
          bankName: 'بانک',
          drawerName: 'صادرکننده',
          partyName: 'شخص سررسید',
          partyId: partyId,
          amount: 100,
          issueDate: '2026-11-12',
          dueDate: item.$2,
          idempotencyKey: item.$1,
        ),
      );
    }
    final results = await checks.getDueChecks(asOfDate: DateTime(2026, 11, 14));
    expect(results.map((row) => row['check_number']).toSet(), {
      'due-yesterday',
      'due-today',
      'due-tomorrow',
    });

    final todayCheck = results.firstWhere((row) => row['check_number'] == 'due-today');
    await checks.updateCheckStatus(
      checkId: todayCheck['id'] as int,
      newStatus: 'cleared',
      reason: 'وصول شد',
      eventDate: '2026-11-14',
    );
    final refreshed = await checks.getDueChecks(asOfDate: DateTime(2026, 11, 14));
    expect(refreshed.any((row) => row['check_number'] == 'due-today'), isFalse);
  });

  test('rejects checks with invalid dates or amounts above invoice balance', () async {
    final partyId = await parties.ensureParty(
      const PartyDraft(
        partyType: 'customer',
        displayName: 'مشتری کنترل مبلغ چک',
      ),
    );
    await expectLater(
      checks.createCheck(
        CheckDraft(
          direction: 'incoming',
          checkNumber: '1',
          bankName: 'بانک',
          drawerName: 'صادرکننده',
          partyName: 'مشتری کنترل مبلغ چک',
          partyId: partyId,
          amount: 100,
          issueDate: '2026-11-15',
          dueDate: '2026-11-14',
          idempotencyKey: 'check-invalid-date',
        ),
      ),
      throwsArgumentError,
    );

    final productId = await addProduct();
    final saleId = await recordSale(productId, partyId);
    await expectLater(
      checks.createCheck(
        CheckDraft(
          direction: 'incoming',
          checkNumber: '2',
          bankName: 'بانک',
          drawerName: 'صادرکننده',
          partyName: 'مشتری کنترل مبلغ چک',
          partyId: partyId,
          amount: 2001,
          issueDate: '2026-11-14',
          dueDate: '2026-11-15',
          idempotencyKey: 'check-excess-amount',
          sourceDocumentId: saleId,
        ),
      ),
      throwsStateError,
    );
  });
}
