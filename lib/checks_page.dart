import 'package:material_ui/material_ui.dart';

import 'check_repository.dart';
import 'jalali_date_field.dart';
import 'party_repository.dart';
import 'trade_repository.dart';

class CheckPage extends StatefulWidget {
  const CheckPage({
    super.key,
    required this.checks,
    required this.parties,
    required this.trades,
    required this.onChanged,
  });

  final CheckRepository checks;
  final PartyRepository parties;
  final TradeRepository trades;
  final VoidCallback onChanged;

  @override
  State<CheckPage> createState() => _CheckPageState();
}

class _CheckPageState extends State<CheckPage> {
  final _number = TextEditingController();
  final _bank = TextEditingController();
  final _drawer = TextEditingController();
  final _party = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();

  String _direction = 'incoming';
  DateTime _issueDate = DateTime.now();
  DateTime _dueDate = DateTime.now().add(const Duration(days: 7));
  int _sourceDocumentId = 0;
  bool _saving = false;
  List<Map<String, Object?>> _checks = [];
  List<Map<String, Object?>> _dueChecks = [];
  List<Map<String, Object?>> _documents = [];
  List<Map<String, Object?>> _partyOptions = [];
  String? _selectedPartyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _number.dispose();
    _bank.dispose();
    _drawer.dispose();
    _party.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  String _iso(DateTime date) => DateTime(date.year, date.month, date.day)
      .toIso8601String()
      .split('T')
      .first;

  String _money(Object? value) => (value as num?)?.toInt().toString() ?? '0';

  String _statusLabel(String status) => switch (status) {
        'received' => 'دریافت‌شده',
        'deposited' => 'واگذار به بانک',
        'issued' => 'صادرشده',
        'cleared' => 'وصول / پاس‌شده',
        'bounced' => 'برگشتی',
        'cancelled' => 'لغوشده',
        _ => status,
      };

  String _dueLabel(String rawDate) {
    final today = DateTime.now();
    final due = DateTime.parse(rawDate);
    final a = DateTime.utc(today.year, today.month, today.day);
    final b = DateTime.utc(due.year, due.month, due.day);
    final days = b.difference(a).inDays;
    if (days < 0) return 'معوق ${-days} روز';
    if (days == 0) return 'سررسید امروز';
    if (days == 1) return 'سررسید فردا';
    return 'سررسید ${days} روز دیگر';
  }

  Future<void> _load() async {
    try {
      final checks = await widget.checks.getChecks();
      final due = await widget.checks.getDueChecks();
      final partyOptions = await widget.parties.getParties(
        partyType: _direction == 'incoming' ? 'customer' : 'supplier',
      );
      final docs = await widget.trades.getDocuments(
        type: _direction == 'incoming' ? 'sale' : 'purchase',
      );
      final outstandingDocs = <Map<String, Object?>>[];
      for (final document in docs) {
        final id = (document['id'] as num).toInt();
        final outstanding = await widget.trades.getOutstandingAmount(id);
        if (outstanding > 0) {
          outstandingDocs.add({...document, 'outstanding_amount': outstanding});
        }
      }
      if (!mounted) return;
      setState(() {
        _checks = checks;
        _dueChecks = due;
        _documents = outstandingDocs;
        _partyOptions = partyOptions;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('بارگذاری چک‌ها ناموفق بود: $error')),
      );
    }
  }

  Future<void> _changeDirection(String value) async {
    setState(() {
      _direction = value;
      _sourceDocumentId = 0;
      _selectedPartyId = null;
    });
    await _load();
  }

  Future<void> _saveCheck() async {
    if (_saving) return;
    final amount = int.tryParse(_amount.text.trim().replaceAll(',', ''));
    if (_number.text.trim().isEmpty ||
        _bank.text.trim().isEmpty ||
        _drawer.text.trim().isEmpty ||
        _party.text.trim().isEmpty ||
        amount == null ||
        amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('شماره چک، بانک، صادرکننده، طرف حساب و مبلغ را کامل کنید')),
      );
      return;
    }
    if (_dueDate.isBefore(DateTime(_issueDate.year, _issueDate.month, _issueDate.day))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تاریخ سررسید نمی‌تواند قبل از تاریخ صدور باشد')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final source = _sourceDocumentId == 0
          ? null
          : _documents.firstWhere(
              (document) => document['id'] == _sourceDocumentId,
            );
      final sourcePartyId = source?['counterparty_id']?.toString();
      final partyId = await widget.parties.ensureParty(
        PartyDraft(
          partyType: _direction == 'incoming' ? 'customer' : 'supplier',
          displayName: _party.text.trim(),
          preferredId: sourcePartyId ?? _selectedPartyId,
        ),
      );

      await widget.checks.createCheck(
        CheckDraft(
          direction: _direction,
          checkNumber: _number.text.trim(),
          bankName: _bank.text.trim(),
          drawerName: _drawer.text.trim(),
          partyName: _party.text.trim(),
          amount: amount,
          issueDate: _iso(_issueDate),
          dueDate: _iso(_dueDate),
          idempotencyKey: 'check-${DateTime.now().microsecondsSinceEpoch}',
          partyId: partyId,
          sourceDocumentId: _sourceDocumentId == 0 ? null : _sourceDocumentId,
          note: _note.text.trim(),
        ),
      );
      _number.clear();
      _bank.clear();
      _drawer.clear();
      _party.clear();
      _amount.clear();
      _note.clear();
      setState(() {
        _sourceDocumentId = 0;
        _selectedPartyId = null;
        _issueDate = DateTime.now();
        _dueDate = DateTime.now().add(const Duration(days: 7));
      });
      await _load();
      widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('چک و سند حسابداری آن ثبت شد')),
        );
      }
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ثبت چک ناموفق بود: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changeStatus(Map<String, Object?> check, String status) async {
    final controller = TextEditingController(
      text: status == 'cleared'
          ? 'وصول / پاس شد'
          : status == 'deposited'
              ? 'تحویل بانک شد'
              : status == 'bounced'
                  ? 'چک برگشت خورد'
                  : 'چک لغو شد',
    );
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('ثبت تغییر وضعیت چک'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'شرح عملیات'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('ثبت'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (reason == null || reason.isEmpty || !mounted) return;

    try {
      await widget.checks.updateCheckStatus(
        checkId: (check['id'] as num).toInt(),
        newStatus: status,
        reason: reason,
        eventDate: _iso(DateTime.now()),
      );
      await _load();
      widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('وضعیت چک و ثبت حسابداری به‌روزرسانی شد')),
        );
      }
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تغییر وضعیت چک ناموفق بود: $error')),
      );
    }
  }

  Widget _statusActions(Map<String, Object?> check) {
    final status = check['status'] as String;
    final incoming = check['direction'] == 'incoming';
    if (status == 'received' && incoming) {
      return Wrap(
        spacing: 4,
        children: [
          TextButton(
            onPressed: () => _changeStatus(check, 'deposited'),
            child: const Text('واگذاری به بانک'),
          ),
          TextButton(
            onPressed: () => _changeStatus(check, 'cleared'),
            child: const Text('وصول شد'),
          ),
          TextButton(
            onPressed: () => _changeStatus(check, 'bounced'),
            child: const Text('برگشتی'),
          ),
        ],
      );
    }
    if (status == 'deposited' && incoming) {
      return Wrap(
        spacing: 4,
        children: [
          TextButton(
            onPressed: () => _changeStatus(check, 'cleared'),
            child: const Text('وصول شد'),
          ),
          TextButton(
            onPressed: () => _changeStatus(check, 'bounced'),
            child: const Text('برگشتی'),
          ),
        ],
      );
    }
    if (status == 'issued' && !incoming) {
      return Wrap(
        spacing: 4,
        children: [
          TextButton(
            onPressed: () => _changeStatus(check, 'cleared'),
            child: const Text('پاس شد'),
          ),
          TextButton(
            onPressed: () => _changeStatus(check, 'bounced'),
            child: const Text('برگشتی'),
          ),
          TextButton(
            onPressed: () => _changeStatus(check, 'cancelled'),
            child: const Text('لغو چک'),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  Widget _checkCard(Map<String, Object?> check, {bool reminder = false}) {
    final incoming = check['direction'] == 'incoming';
    final dueDate = check['due_date'] as String;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${incoming ? 'چک دریافتی' : 'چک پرداختی'} شماره ${check['check_number']}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  _statusLabel(check['status'] as String),
                  style: TextStyle(
                    color: check['status'] == 'bounced'
                        ? Colors.red
                        : check['status'] == 'cleared'
                            ? Colors.green
                            : null,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            Text('طرف حساب: ${check['party_name']}'),
            Text('بانک: ${check['bank_name']} • صادرکننده: ${check['drawer_name']}'),
            Text('مبلغ: ${_money(check['amount'])} تومان'),
            Text('سررسید: ${formatJalaliDate(DateTime.parse(dueDate))}'),
            if (reminder)
              Text(
                _dueLabel(dueDate),
                style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold),
              ),
            _statusActions(check),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            const Text('مدیریت چک‌ها', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            if (_dueChecks.isNotEmpty)
              Card(
                color: const Color(0xFFFFF0D6),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_dueChecks.length} چک سررسیدشده یا نزدیک به سررسید',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Text('این یادآوری داخل برنامه نمایش داده می‌شود؛ برای دریافت اعلان حتی هنگام بسته بودن برنامه، سامانه اعلان زمان‌بندی‌شده هنوز لازم است.'),
                      for (final check in _dueChecks.take(5))
                        Text(
                          '• ${check['check_number']} — ${check['party_name']} — ${_dueLabel(check['due_date'] as String)}',
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            const Text('ثبت چک جدید', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _direction,
              decoration: const InputDecoration(labelText: 'نوع چک'),
              items: const [
                DropdownMenuItem(value: 'incoming', child: Text('چک دریافتی از مشتری')),
                DropdownMenuItem(value: 'outgoing', child: Text('چک پرداختی به فروشنده')),
              ],
              onChanged: (value) {
                if (value != null) _changeDirection(value);
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _number,
              decoration: const InputDecoration(labelText: 'شماره چک'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _bank,
              decoration: const InputDecoration(labelText: 'نام بانک'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _drawer,
              decoration: const InputDecoration(labelText: 'نام صاحب حساب / صادرکننده'),
            ),
            const SizedBox(height: 8),
            if (_partyOptions.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: _selectedPartyId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'انتخاب از اشخاص ثبت‌شده (${_direction == 'incoming' ? 'مشتری' : 'فروشنده'})',
                ),
                items: [
                  for (final party in _partyOptions)
                    DropdownMenuItem(
                      value: party['id'] as String,
                      child: Text(
                        party['display_name']?.toString() ?? '',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedPartyId = value;
                    if (value != null) {
                      final selected = _partyOptions.firstWhere((p) => p['id'] == value);
                      _party.text = selected['display_name']?.toString() ?? '';
                    }
                  });
                },
              ),
            TextField(
              controller: _party,
              decoration: InputDecoration(
                labelText: _direction == 'incoming' ? 'نام مشتری' : 'نام فروشنده',
              ),
              onChanged: (value) {
                if (_selectedPartyId != null) {
                  final selected = _partyOptions.firstWhere(
                    (p) => p['id'] == _selectedPartyId,
                  );
                  if (value.trim() != selected['display_name']?.toString()) {
                    setState(() => _selectedPartyId = null);
                  }
                }
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'مبلغ چک (تومان)'),
            ),
            const SizedBox(height: 8),
            JalaliDateField(
              initialDate: _issueDate,
              label: 'تاریخ صدور',
              onChanged: (date) => setState(() => _issueDate = date),
            ),
            const SizedBox(height: 8),
            JalaliDateField(
              initialDate: _dueDate,
              label: 'تاریخ سررسید',
              onChanged: (date) => setState(() => _dueDate = date),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: _sourceDocumentId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'اتصال به فاکتور (اختیاری)'),
              items: [
                const DropdownMenuItem(value: 0, child: Text('بدون اتصال به فاکتور')),
                for (final document in _documents)
                  DropdownMenuItem(
                    value: (document['id'] as num).toInt(),
                    child: Text(
                      '${document['document_number']} — ${document['counterparty_name']} — مانده: ${_money(document['outstanding_amount'])}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                final selected = value ?? 0;
                setState(() {
                  _sourceDocumentId = selected;
                  if (selected != 0) {
                    final document = _documents.firstWhere(
                      (row) => row['id'] == selected,
                    );
                    _party.text = document['counterparty_name']?.toString() ?? '';
                    _selectedPartyId = document['counterparty_id']?.toString();
                  }
                });
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'توضیحات'),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _saving ? null : _saveCheck,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(_saving ? 'در حال ثبت...' : 'ثبت چک'),
            ),
            const Divider(height: 28),
            Text('چک‌های سررسید نزدیک', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            if (_dueChecks.isEmpty)
              const Card(child: Padding(
                padding: EdgeInsets.all(14),
                child: Text('چکی برای سررسید امروز یا فردا وجود ندارد'),
              )),
            for (final check in _dueChecks) _checkCard(check, reminder: true),
            const Divider(height: 28),
            const Text('همه چک‌ها', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            if (_checks.isEmpty)
              const Card(child: Padding(
                padding: EdgeInsets.all(14),
                child: Text('هنوز چکی ثبت نشده است'),
              )),
            for (final check in _checks) _checkCard(check),
          ],
        ),
      ),
    );
  }
}
