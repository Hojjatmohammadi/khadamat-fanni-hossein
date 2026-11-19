import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khadamat_fanni_hosein/party_payment_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('customer receipt can be linked to an open invoice and paid card-to-card',
      (tester) async {
    Map<String, Object?>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () async {
                  result = await showDialog<Map<String, Object?>?>(
                    context: context,
                    builder: (_) => const PartyPaymentDialog(
                      isCustomerReceipt: true,
                      openInvoices: [
                        {
                          'id': 42,
                          'document_number': 'SAL-000042',
                          'remaining_amount': 7000,
                        },
                      ],
                    ),
                  );
                },
                child: const Text('باز کردن فرم دریافت / پرداخت'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('باز کردن فرم دریافت / پرداخت'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('ثبت بیعانه / دریافت از مشتری'), findsOneWidget);
    expect(find.text('SAL-000042 • مانده: 7000'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('party-ledger-invoice-link')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('SAL-000042 • مانده: 7000'), findsOneWidget);
    await tester.tap(find.text('SAL-000042 • مانده: 7000').last);
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(
      find.byKey(const ValueKey('party-ledger-advance-amount')),
      '3500',
    );
    await tester.tap(
      find.byKey(const ValueKey('party-ledger-advance-method')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('کارت‌به‌کارت').last);
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('ثبت در گردش حساب'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(result, {
      'amount': 3500,
      'referenceId': '42',
      'paymentMethod': 'card_to_card',
    });
  });

  testWidgets('supplier prepayment can remain free and use bank transfer',
      (tester) async {
    Map<String, Object?>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () async {
                  result = await showDialog<Map<String, Object?>?>(
                    context: context,
                    builder: (_) => const PartyPaymentDialog(
                      isCustomerReceipt: false,
                      openInvoices: [],
                    ),
                  );
                },
                child: const Text('باز کردن فرم دریافت / پرداخت'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('باز کردن فرم دریافت / پرداخت'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('ثبت پیش‌پرداخت به فروشنده'), findsOneWidget);
    expect(find.text('بیعانه / پیش‌پرداخت آزاد'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('party-ledger-invoice-link')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('بیعانه / پیش‌پرداخت آزاد'), findsOneWidget);
    await tester.tap(find.text('بیعانه / پیش‌پرداخت آزاد').last);
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(
      find.byKey(const ValueKey('party-ledger-advance-amount')),
      '8400',
    );
    await tester.tap(
      find.byKey(const ValueKey('party-ledger-advance-method')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('انتقال بانکی').last);
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('ثبت در گردش حساب'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(result, {
      'amount': 8400,
      'referenceId': null,
      'paymentMethod': 'bank_transfer',
    });
  });

  testWidgets('empty or zero amount does not close the payment dialog',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => showDialog<Map<String, Object?>?>(
                  context: context,
                  builder: (_) => const PartyPaymentDialog(
                    isCustomerReceipt: true,
                    openInvoices: [],
                  ),
                ),
                child: const Text('باز کردن فرم دریافت / پرداخت'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('باز کردن فرم دریافت / پرداخت'));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('ثبت در گردش حساب'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('مبلغ باید عدد معتبر و بیشتر از صفر باشد'), findsOneWidget);
    expect(find.text('ثبت بیعانه / دریافت از مشتری'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('party-ledger-advance-amount')),
      '0',
    );
    await tester.tap(find.text('ثبت در گردش حساب'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('ثبت بیعانه / دریافت از مشتری'), findsOneWidget);
  });
}
