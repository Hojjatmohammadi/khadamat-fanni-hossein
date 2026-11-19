import 'package:material_ui/material_ui.dart';

import 'localized_number.dart';
import 'numeric_input.dart';

/// Reusable form for recording an optional invoice-linked settlement or a
/// free customer advance / supplier prepayment.
class PartyPaymentDialog extends StatefulWidget {
  const PartyPaymentDialog({
    super.key,
    required this.isCustomerReceipt,
    required this.openInvoices,
  });

  final bool isCustomerReceipt;
  final List<Map<String, Object?>> openInvoices;

  @override
  State<PartyPaymentDialog> createState() => _PartyPaymentDialogState();
}

class _PartyPaymentDialogState extends State<PartyPaymentDialog> {
  final _amountController = TextEditingController();
  String _paymentMethod = 'cash';
  int? _selectedInvoiceId;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = LocalizedNumber.tryParseInt(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('مبلغ باید عدد معتبر و بیشتر از صفر باشد')),
      );
      return;
    }

    Navigator.pop<Map<String, Object?>>(context, {
      'amount': amount,
      'referenceId': _selectedInvoiceId?.toString(),
      'paymentMethod': _paymentMethod,
    });
  }

  @override
  Widget build(BuildContext context) {
    final isCustomerReceipt = widget.isCustomerReceipt;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text(
          isCustomerReceipt
              ? 'ثبت بیعانه / دریافت از مشتری'
              : 'ثبت پیش‌پرداخت به فروشنده',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isCustomerReceipt
                  ? 'دریافت را می‌توانید به یک فاکتور باز متصل کنید یا به‌عنوان بیعانه آزاد ثبت کنید.'
                  : 'پرداخت را می‌توانید به یک فاکتور باز متصل کنید یا به‌عنوان پیش‌پرداخت آزاد ثبت کنید.',
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              key: const ValueKey('party-ledger-invoice-link'),
              initialValue: _selectedInvoiceId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'اتصال به فاکتور (اختیاری)',
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('بیعانه / پیش‌پرداخت آزاد'),
                ),
                ...widget.openInvoices.map((invoice) {
                  final id = invoice['id'] as int;
                  final number =
                      invoice['document_number']?.toString() ?? id.toString();
                  final remaining =
                      (invoice['remaining_amount'] as num).toInt();
                  return DropdownMenuItem<int?>(
                    value: id,
                    child: Text('$number • مانده: $remaining'),
                  );
                }),
              ],
              onChanged: (value) => setState(() => _selectedInvoiceId = value),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('party-ledger-advance-amount'),
              controller: _amountController,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: numericInputFormattersForField('مبلغ'),
              decoration: const InputDecoration(labelText: 'مبلغ (تومان)'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const ValueKey('party-ledger-advance-method'),
              initialValue: _paymentMethod,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'روش دریافت / پرداخت',
              ),
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('نقدی')),
                DropdownMenuItem(
                  value: 'bank_transfer',
                  child: Text('انتقال بانکی'),
                ),
                DropdownMenuItem(
                  value: 'card_to_card',
                  child: Text('کارت‌به‌کارت'),
                ),
              ],
              onChanged: (value) => setState(
                () => _paymentMethod = value ?? 'cash',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: _submit,
            child: const Text('ثبت در گردش حساب'),
          ),
        ],
      ),
    );
  }
}
