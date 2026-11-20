import 'package:material_ui/material_ui.dart';

import 'loan_repository.dart';
import 'localized_number.dart';
import 'numeric_input.dart';

class LoanManagementPage extends StatefulWidget {
  const LoanManagementPage({super.key, required this.repository});

  final LoanRepository repository;

  @override
  State<LoanManagementPage> createState() => _LoanManagementPageState();
}

class _LoanManagementPageState extends State<LoanManagementPage> {
  final _party = TextEditingController();
  final _amount = TextEditingController();
  final _count = TextEditingController(text: '1');
  final _date = TextEditingController(
    text: DateTime.now().toIso8601String().substring(0, 10),
  );
  final _due = TextEditingController(
    text: DateTime.now().toIso8601String().substring(0, 10),
  );

  List<Map<String, Object?>> _loans = [];
  bool _loading = true;
  bool _saving = false;
  int? _repayingLoanId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _party.dispose();
    _amount.dispose();
    _count.dispose();
    _date.dispose();
    _due.dispose();
    super.dispose();
  }

  int? _number(String value) => LocalizedNumber.tryParseInt(value);

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value)),
    );
  }

  Future<void> _load() async {
    try {
      final rows = await widget.repository.getLoans();
      if (!mounted) return;
      setState(() => _loans = rows);
    } catch (error) {
      if (mounted) {
        _message('بارگذاری قرض‌ها ناموفق بود: $error');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addLoan() async {
    if (_saving) return;

    final amount = _number(_amount.text);
    final count = _number(_count.text) ?? 0;
    final loanDate = DateTime.tryParse(_date.text);
    final dueDate = DateTime.tryParse(_due.text);
    if (_party.text.trim().isEmpty ||
        amount == null ||
        amount <= 0 ||
        count < 1 ||
        loanDate == null ||
        dueDate == null ||
        dueDate.isBefore(loanDate)) {
      _message('نام قرض‌دهنده، مبلغ، تاریخ دریافت، سررسید و تعداد اقساط را صحیح وارد کنید');
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.repository.createReceivedLoan(
        partyName: _party.text.trim(),
        amount: amount,
        loanDate: _date.text,
        dueDate: _due.text,
        installmentCount: count,
        idempotencyKey: 'loan-${DateTime.now().microsecondsSinceEpoch}',
      );
      if (!mounted) return;

      _party.clear();
      _amount.clear();
      _count.text = '1';
      await _load();
      if (!mounted) return;
      _message('قرض ثبت شد؛ مبلغ به بدهی اضافه شد و درآمد محسوب نشد');
    } catch (error) {
      if (!mounted) return;
      _message('ثبت قرض ناموفق بود: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _repay(Map<String, Object?> loan) async {
    final loanId = (loan['id'] as num).toInt();
    if (_repayingLoanId != null) return;

    setState(() => _repayingLoanId = loanId);
    try {
      final remaining = (loan['remaining_amount'] as num).toInt();
      final installments = await widget.repository.getInstallments(loanId);
      if (!mounted) return;

      Map<String, Object?>? next;
      for (final item in installments) {
        if ((item['amount'] as num) > (item['paid_amount'] as num)) {
          next = item;
          break;
        }
      }
      if (next == null) {
        _message('برای این قرض قسط پرداخت‌نشده‌ای باقی نمانده است');
        return;
      }

      final installmentRemaining =
          (next['amount'] as num).toInt() - (next['paid_amount'] as num).toInt();
      final payable = remaining < installmentRemaining
          ? remaining
          : installmentRemaining;
      final controller = TextEditingController(text: payable.toString());
      final amount = await showDialog<int>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('بازپرداخت به ${loan['party_name']}'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: const [NumericInputFormatter()],
            decoration: const InputDecoration(
              labelText: 'مبلغ پرداخت به تومان',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                _number(controller.text),
              ),
              child: const Text('ثبت پرداخت'),
            ),
          ],
        ),
      );
      controller.dispose();

      if (!mounted || amount == null) return;
      if (amount <= 0 || amount > payable) {
        _message('مبلغ بازپرداخت باید بیشتر از صفر و حداکثر برابر مانده قسط باشد');
        return;
      }

      await widget.repository.recordRepayment(
        loanId: loanId,
        amount: amount,
        paymentDate: DateTime.now().toIso8601String().substring(0, 10),
        idempotencyKey: 'loan-repay-${DateTime.now().microsecondsSinceEpoch}',
        installmentId: next['id'] as int,
      );
      await _load();
      if (!mounted) return;
      _message('بازپرداخت ثبت شد و مانده بدهی کاهش یافت');
    } catch (error) {
      if (!mounted) return;
      _message('ثبت بازپرداخت ناموفق بود: $error');
    } finally {
      if (mounted) setState(() => _repayingLoanId = null);
    }
  }

  String _money(Object? value) => (value as num? ?? 0)
      .toInt()
      .toString()
      .replaceAllMapped(
        RegExp(r'\\B(?=(\\d{3})+(?!\\d))'),
        (match) => ',',
      );

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text(
                      'ثبت قرض دریافتی و برنامه اقساط',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            TextField(
                              controller: _party,
                              decoration: const InputDecoration(
                                labelText: 'نام شخص قرض‌دهنده',
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _amount,
                              keyboardType: TextInputType.number,
                              inputFormatters: const [NumericInputFormatter()],
                              decoration: const InputDecoration(
                                labelText: 'اصل مبلغ قرض (تومان)',
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _date,
                              keyboardType: TextInputType.datetime,
                              inputFormatters: const [
                                NumericDateInputFormatter(separator: '-'),
                              ],
                              decoration: const InputDecoration(
                                labelText: 'تاریخ دریافت (YYYY-MM-DD)',
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _due,
                              keyboardType: TextInputType.datetime,
                              inputFormatters: const [
                                NumericDateInputFormatter(separator: '-'),
                              ],
                              decoration: const InputDecoration(
                                labelText: 'تاریخ اولین سررسید (YYYY-MM-DD)',
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _count,
                              keyboardType: TextInputType.number,
                              inputFormatters: const [NumericInputFormatter()],
                              decoration: const InputDecoration(
                                labelText: 'تعداد اقساط ماهانه',
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _saving ? null : _addLoan,
                                icon: const Icon(Icons.add),
                                label: Text(
                                  _saving ? 'در حال ثبت...' : 'ثبت قرض و ایجاد اقساط',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'دفتر قرض‌ها و مانده بدهی',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_loans.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('هنوز قرضی ثبت نشده است'),
                      )
                    else
                      ..._loans.map((loan) {
                        final remaining =
                            (loan['remaining_amount'] as num).toInt();
                        final loanId = (loan['id'] as num).toInt();
                        final isRepaying = _repayingLoanId == loanId;
                        return Card(
                          child: ListTile(
                            title: Text(loan['party_name'].toString()),
                            subtitle: Text(
                              'اصل قرض: ${_money(loan['principal_amount'])} تومان'
                              ' • پرداخت‌شده: ${_money(loan['paid_amount'])} تومان'
                              '\\nمانده بدهی: ${_money(remaining)} تومان'
                              '\\nتعداد اقساط: ${loan['installment_count']}',
                            ),
                            isThreeLine: true,
                            trailing: remaining > 0
                                ? IconButton(
                                    tooltip: 'ثبت بازپرداخت',
                                    icon: isRepaying
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.payments_outlined),
                                    onPressed: _repayingLoanId != null
                                        ? null
                                        : () => _repay(loan),
                                  )
                                : const Icon(
                                    Icons.check_circle_outline,
                                    color: Colors.green,
                                  ),
                          ),
                        );
                      }),
                  ],
                ),
        ),
      );
}
