import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:khadamat_fanni_hosein/app_database.dart';
import 'package:khadamat_fanni_hosein/check_reminder_service.dart';
import 'package:khadamat_fanni_hosein/party_ledger_page.dart';
import 'package:khadamat_fanni_hosein/party_repository.dart';
import 'package:khadamat_fanni_hosein/trade_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late AppDatabase database;
  late PartyRepository parties;
  late TradeRepository trades;
  late CheckReminderService reminders;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('khadamat_party_ledger_ui_');
    database = AppDatabase(databasePath: '${tempDir.path}/ledger-ui.db');
    parties = PartyRepository(database);
    trades = TradeRepository(database);
    reminders = CheckReminderService();
    await database.database;
  });

  tearDown(() async {
    await database.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<void> pumpUntilFound(
    WidgetTester tester,
    Finder finder, {
    int maxPumps = 50,
  }) async {
    for (var i = 0; i < maxPumps && finder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      finder,
      findsOneWidget,
      reason: 'Expected UI element did not appear within ${maxPumps * 100} ms',
    );
  }

  Future<void> pumpLedger(
    WidgetTester tester, {
    required String partyId,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PartyLedgerPage(
            repository: parties,
            reminders: reminders,
            trades: trades,
            initialPartyId: partyId,
          ),
        ),
      ),
    );
    await pumpUntilFound(
      tester,
      find.byKey(const ValueKey('record-customer-advance')),
    );
  }

  testWidgets('customer advance UI records amount and card-to-card method once',
      (tester) async {
    const customerId = 'ui-customer-advance';
    await parties.ensureParty(const PartyDraft(
      partyType: 'customer',
      displayName: 'مشتری آزمون رابط',
      phone: '09120000011',
      preferredId: customerId,
    ));

    await pumpLedger(tester, partyId: customerId);

    final action = find.byKey(const ValueKey('record-customer-advance'));
    expect(action, findsOneWidget);
    await tester.ensureVisible(action);
    await tester.tap(action);
    await pumpUntilFound(tester, find.text('ثبت بیعانه / دریافت از مشتری'));
    expect(find.byKey(const ValueKey('party-ledger-invoice-link')), findsOneWidget);
    expect(find.text('بیعانه / پیش‌پرداخت آزاد'), findsOneWidget);

    final amountField = find.byKey(
      const ValueKey('party-ledger-advance-amount'),
    );
    await tester.enterText(amountField, '12500');

    final methodField = find.byKey(
      const ValueKey('party-ledger-advance-method'),
    );
    await tester.tap(methodField);
    await pumpUntilFound(tester, find.text('کارت‌به‌کارت'));
    await tester.tap(find.text('کارت‌به‌کارت').last);
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.text('ثبت در گردش حساب'));
    await pumpUntilFound(tester, find.text('بیعانه مشتری در گردش حساب ثبت شد'));

    final documents = await trades.getDocuments(
      type: 'customer_receipt',
      counterpartyId: customerId,
    );
    expect(documents, hasLength(1));
    final document = documents.single;
    expect(document['total_amount'], 12500);
    expect(document['source_document_id'], isNull);

    final payload = jsonDecode(document['payload_json']! as String)
        as Map<String, dynamic>;
    expect(payload['amount'], 12500);
    expect(payload['paymentMethod'], 'card_to_card');
    expect(payload['cashAccountCode'], '1010');
    expect(payload['referenceId'], isNull);

    final db = await database.database;
    final journalLines = await db.query(
      'journal_lines',
      where: 'party_id = ?',
      whereArgs: [customerId],
    );
    expect(
      journalLines.where((line) => line['account_code'] == '1100').single['credit'],
      12500,
    );

    final statement = await parties.getPartyStatement(customerId);
    expect(statement['available_customer_advance'], 12500);
    expect(statement['closing_balance'], -12500);
    expect(find.textContaining('بیعانه آزاد قابل تخصیص: 12500 تومان'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 45)));

  testWidgets('supplier prepayment UI records a bank transfer and keeps it unallocated',
      (tester) async {
    const supplierId = 'ui-supplier-prepayment';
    await parties.ensureParty(const PartyDraft(
      partyType: 'supplier',
      displayName: 'فروشنده آزمون رابط',
      phone: '09120000022',
      preferredId: supplierId,
    ));

    await pumpLedger(tester, partyId: supplierId);

    final action = find.byKey(const ValueKey('record-supplier-prepayment'));
    expect(action, findsOneWidget);
    await tester.ensureVisible(action);
    await tester.tap(action);
    await pumpUntilFound(tester, find.text('ثبت پیش‌پرداخت به فروشنده'));
    expect(find.text('بیعانه / پیش‌پرداخت آزاد'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('party-ledger-advance-amount')),
      '8400',
    );

    await tester.tap(
      find.byKey(const ValueKey('party-ledger-advance-method')),
    );
    await pumpUntilFound(tester, find.text('انتقال بانکی'));
    await tester.tap(find.text('انتقال بانکی').last);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('ثبت در گردش حساب'));
    await pumpUntilFound(tester, find.text('پیش‌پرداخت فروشنده ثبت شد'));

    final documents = await trades.getDocuments(
      type: 'supplier_payment',
      counterpartyId: supplierId,
    );
    expect(documents, hasLength(1));
    expect(documents.single['total_amount'], 8400);
    expect(documents.single['source_document_id'], isNull);

    final payload = jsonDecode(documents.single['payload_json']! as String)
        as Map<String, dynamic>;
    expect(payload['paymentMethod'], 'bank_transfer');
    expect(payload['cashAccountCode'], '1010');
    expect(payload['referenceId'], isNull);

    final statement = await parties.getPartyStatement(supplierId);
    expect(statement['available_supplier_prepayment'], 8400);
    expect(statement['closing_balance'], -8400);
    expect(find.textContaining('پیش‌پرداخت آزاد فروشنده: 8400 تومان'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 45)));
}
