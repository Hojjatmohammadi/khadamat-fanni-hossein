import 'package:material_ui/material_ui.dart';

import 'accounting_repository.dart';
import 'jalali_date_field.dart';

class FinancialManagementPage extends StatefulWidget {
  const FinancialManagementPage({super.key, required this.repository});

  final AccountingRepository repository;

  @override
  State<FinancialManagementPage> createState() => _FinancialManagementPageState();
}

class _FinancialManagementPageState extends State<FinancialManagementPage> {
  final _description = TextEditingController();
  final _amount = TextEditingController();
  final _statementBalance = TextEditingController();
  final _reconciliationNote = TextEditingController();
  DateTime _expenseDate = DateTime.now();
  DateTime _reportFrom = DateTime(DateTime.now().year, 1, 1);
  DateTime _reportTo = DateTime.now();
  DateTime _statementDate = DateTime.now();
  String _reconciliationAccount = '1010';
  String _expenseAccount = '6100';
  String _cashAccount = '1000';
  String? _ledgerAccount;
  List<Map<String, Object?>> _accounts = [];
  List<Map<String, Object?>> _journal = [];
  List<Map<String, Object?>> _trialBalance = [];
  Map<String, Object?>? _ledger;
  List<Map<String, Object?>> _reconciliations = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    _statementBalance.dispose();
    _reconciliationNote.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final accounts = await widget.repository.getAccounts();
      final fromDate = _isoDate(_reportFrom);
      final toDate = _isoDate(_reportTo);
      final journal = await widget.repository.getJournalEntries(fromDate: fromDate, toDate: toDate);
      final trial = await widget.repository.getTrialBalance(fromDate: fromDate, toDate: toDate);
      final reconciliations = await widget.repository.getBankReconciliations();
      final expenseAccounts = accounts.where((a) => a['account_type'] == 'expense').toList();
      final selectedExpense = expenseAccounts.any((a) => a['code'] == _expenseAccount)
          ? _expenseAccount
          : expenseAccounts.first['code'] as String;
      final ledgerAccounts = accounts;
      final selectedLedger = ledgerAccounts.any((a) => a['code'] == _ledgerAccount)
          ? _ledgerAccount
          : accounts.isEmpty ? null : accounts.first['code'] as String;
      final ledger = selectedLedger == null
          ? null
          : await widget.repository.getAccountLedger(selectedLedger, fromDate: fromDate, toDate: toDate);
      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _journal = journal;
        _trialBalance = trial;
        _expenseAccount = selectedExpense;
        _ledgerAccount = selectedLedger;
        _ledger = ledger;
        _reconciliations = reconciliations;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('بارگذاری گزارش‌های مالی ناموفق بود: $error');
    }
  }

  Future<void> _selectLedger(String? code) async {
    if (code == null) return;
    try {
      final result = await widget.repository.getAccountLedger(code,
        fromDate: _isoDate(_reportFrom), toDate: _isoDate(_reportTo));
      if (!mounted) return;
      setState(() {
        _ledgerAccount = code;
        _ledger = result;
      });
    } catch (error) {
      _message('خواندن دفتر حساب ناموفق بود: $error');
    }
  }

  Future<void> _saveExpense() async {
    final amount = _parseAmount(_amount.text);
    if (_description.text.trim().isEmpty || amount == null || amount <= 0) {
      _message('شرح هزینه و مبلغ معتبر را وارد کنید');
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.repository.recordExpense(
        expenseDate: DateTime(_expenseDate.year, _expenseDate.month, _expenseDate.day).toIso8601String().substring(0, 10),
        description: _description.text.trim(),
        amount: amount,
        expenseAccountCode: _expenseAccount,
        cashAccountCode: _cashAccount,
        idempotencyKey: 'expense-${DateTime.now().microsecondsSinceEpoch}',
      );
      _description.clear();
      _amount.clear();
      await _load();
      if (!mounted) return;
      _message('هزینه ثبت شد و سند حسابداری متوازن ایجاد شد');
    } catch (error) {
      _message('ثبت هزینه ناموفق بود: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }


  Future<void> _saveReconciliation() async {
    final balance = _parseAmount(_statementBalance.text);
    if (balance == null || (_reconciliationAccount == '1000' && balance < 0)) {
      _message('مانده صورت‌حساب را به‌درستی وارد کنید (مانده صندوق منفی نمی‌شود)');
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.repository.createBankReconciliation(
        accountCode: _reconciliationAccount,
        statementDate: _isoDate(_statementDate),
        statementBalance: balance,
        note: _reconciliationNote.text.trim(),
        idempotencyKey: 'bank-reconcile-${DateTime.now().microsecondsSinceEpoch}',
      );
      _statementBalance.clear();
      _reconciliationNote.clear();
      await _load();
      if (!mounted) return;
      _message('صورت‌حساب ثبت و اختلاف با مانده دفاتر محاسبه شد');
    } catch (error) {
      _message('ثبت تطبیق بانکی ناموفق بود: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _isoDate(DateTime value) =>
      DateTime(value.year, value.month, value.day).toIso8601String().substring(0, 10);

  Widget _reportDateControls() => Card(
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('محدوده گزارش (تاریخ شمسی)', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          JalaliDateField(
            key: ValueKey('report-from-${_isoDate(_reportFrom)}'),
            initialDate: _reportFrom,
            label: 'از تاریخ',
            onChanged: (date) => setState(() => _reportFrom = date),
          ),
          const SizedBox(height: 8),
          JalaliDateField(
            key: ValueKey('report-to-${_isoDate(_reportTo)}'),
            initialDate: _reportTo,
            label: 'تا تاریخ',
            onChanged: (date) => setState(() => _reportTo = date),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () {
              if (_reportFrom.isAfter(_reportTo)) {
                _message('تاریخ شروع نباید بعد از تاریخ پایان باشد');
              } else {
                _load();
              }
            },
            icon: const Icon(Icons.filter_alt),
            label: const Text('اعمال فیلتر تاریخ'),
          ),
        ],
      ),
    ),
  );

  int? _parseAmount(String value) {
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    var normalized = value.trim().replaceAll(',', '').replaceAll('٬', '');
    for (var i = 0; i < 10; i++) {
      normalized = normalized.replaceAll(persian[i], '$i').replaceAll(arabic[i], '$i');
    }
    return int.tryParse(normalized);
  }

  String _money(Object? value) => ((value as num?)?.toInt() ?? 0).toString();
  String _date(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed == null ? '—' : formatJalaliDate(parsed);
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _accounts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final expenses = _accounts.where((a) => a['account_type'] == 'expense').toList();
    final ledgerLines = (_ledger?['lines'] as List<Map<String, Object?>>?) ?? [];
    return DefaultTabController(
      length: 5,
      child: Column(
        children: [
          const Material(
            color: Colors.white,
            child: TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: 'ثبت هزینه'),
                Tab(text: 'دفتر روزنامه'),
                Tab(text: 'تراز آزمایشی'),
                Tab(text: 'دفتر کل حساب'),
                Tab(text: 'تطبیق بانکی'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text('ثبت هزینه‌های مغازه', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    JalaliDateField(
                      initialDate: _expenseDate,
                      label: 'تاریخ هزینه',
                      onChanged: (date) => setState(() => _expenseDate = date),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _description,
                      decoration: const InputDecoration(labelText: 'شرح هزینه'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _amount,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'مبلغ (تومان)'),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      key: ValueKey(_expenseAccount),
                      initialValue: _expenseAccount,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'گروه هزینه'),
                      items: [
                        for (final account in expenses)
                          DropdownMenuItem(
                            value: account['code'] as String,
                            child: Text('${account['name']}'),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _expenseAccount = value);
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      key: ValueKey(_cashAccount),
                      initialValue: _cashAccount,
                      decoration: const InputDecoration(labelText: 'پرداخت از'),
                      items: const [
                        DropdownMenuItem(value: '1000', child: Text('صندوق')),
                        DropdownMenuItem(value: '1010', child: Text('بانک')),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _cashAccount = value);
                      },
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _saving ? null : _saveExpense,
                      icon: const Icon(Icons.save),
                      label: Text(_saving ? 'در حال ثبت...' : 'ثبت هزینه و سند حسابداری'),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'پس از ثبت، سند بدهکار هزینه و بستانکار صندوق/بانک به‌صورت خودکار ایجاد می‌شود. سند ثبت‌شده قابل ویرایش یا حذف نیست و اصلاح آن باید با سند برگشت انجام شود.',
                      style: TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                  ],
                ),
                RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      const Text('دفتر روزنامه', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                      _reportDateControls(),
                      for (final entry in _journal)
                        Card(
                          child: ExpansionTile(
                            title: Text('${entry['description']}'),
                            subtitle: Text('سند ${entry['id']}  •  ${_date(entry['entry_date'])}'),
                            children: [
                              for (final line in (entry['lines'] as List<Map<String, Object?>>))
                                ListTile(
                                  dense: true,
                                  title: Text('${line['account_name']}'),
                                  subtitle: Text(line['memo']?.toString() ?? ''),
                                  trailing: Text(
                                    (line['debit'] as num).toInt() > 0
                                      ? 'بدهکار: ${_money(line['debit'])}'
                                      : 'بستانکار: ${_money(line['credit'])}',
                                  ),
                                ),
                            ],
                          ),
                        ),
                      if (_journal.isEmpty) const Text('هنوز سند حسابداری ثبت نشده است'),
                    ],
                  ),
                ),
                RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      const Text('تراز آزمایشی', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                      _reportDateControls(),
                      const Text('گردش بدهکار و بستانکار در محدوده تاریخ انتخاب‌شده نمایش داده می‌شود.'),
                      const SizedBox(height: 8),
                      for (final row in _trialBalance)
                        Card(
                          child: ListTile(
                            title: Text('${row['account_code']} — ${row['account_name']}'),
                            subtitle: Text('بدهکار: ${_money(row['total_debit'])}  |  بستانکار: ${_money(row['total_credit'])}'),
                            trailing: Text(_money((row['balance_debit_minus_credit'] as num).abs())),
                          ),
                        ),
                    ],
                  ),
                ),
                RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      const Text('دفتر کل حساب', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                      _reportDateControls(),
                      DropdownButtonFormField<String>(
                        key: ValueKey(_ledgerAccount),
                        initialValue: _ledgerAccount,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'انتخاب حساب'),
                        items: [
                          for (final account in _accounts)
                            DropdownMenuItem(
                              value: account['code'] as String,
                              child: Text('${account['code']} — ${account['name']}'),
                            ),
                        ],
                        onChanged: _selectLedger,
                      ),
                      const SizedBox(height: 8),
                      if (_ledger != null)
                        Card(
                          child: ListTile(
                            title: Text('مانده پایان: ${_money((_ledger!['closing_balance'] as num).abs())} تومان'),
                            subtitle: Text('مانده اول دوره (بدهکار منهای بستانکار): ${_money(_ledger!['opening_balance'])}'),
                          ),
                        ),
                      for (final line in ledgerLines)
                        Card(
                          child: ListTile(
                            title: Text('${line['description']}'),
                            subtitle: Text(_date(line['entry_date'])),
                            trailing: Text(
                              (line['debit'] as num).toInt() > 0
                                ? 'بدهکار ${_money(line['debit'])}\nمانده ${_money(line['running_balance'])}'
                                : 'بستانکار ${_money(line['credit'])}\nمانده ${_money(line['running_balance'])}',
                              textAlign: TextAlign.end,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
import 'package:material_ui/material_ui.dart';

import 'accounting_repository.dart';
import 'jalali_date_field.dart';

class FinancialManagementPage extends StatefulWidget {
  const FinancialManagementPage({super.key, required this.repository});

  final AccountingRepository repository;

  @override
  State<FinancialManagementPage> createState() => _FinancialManagementPageState();
}

class _FinancialManagementPageState extends State<FinancialManagementPage> {
  final _description = TextEditingController();
  final _amount = TextEditingController();
  final _statementBalance = TextEditingController();
  final _reconciliationNote = TextEditingController();
  DateTime _expenseDate = DateTime.now();
  DateTime _reportFrom = DateTime(DateTime.now().year, 1, 1);
  DateTime _reportTo = DateTime.now();
  DateTime _statementDate = DateTime.now();
  String _reconciliationAccount = '1010';
  String _expenseAccount = '6100';
  String _cashAccount = '1000';
  String? _ledgerAccount;
  List<Map<String, Object?>> _accounts = [];
  List<Map<String, Object?>> _journal = [];
  List<Map<String, Object?>> _trialBalance = [];
  Map<String, Object?>? _ledger;
  List<Map<String, Object?>> _reconciliations = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    _statementBalance.dispose();
    _reconciliationNote.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final accounts = await widget.repository.getAccounts();
      final fromDate = _isoDate(_reportFrom);
      final toDate = _isoDate(_reportTo);
      final journal = await widget.repository.getJournalEntries(fromDate: fromDate, toDate: toDate);
      final trial = await widget.repository.getTrialBalance(fromDate: fromDate, toDate: toDate);
      final reconciliations = await widget.repository.getBankReconciliations();
      final expenseAccounts = accounts.where((a) => a['account_type'] == 'expense').toList();
      final selectedExpense = expenseAccounts.any((a) => a['code'] == _expenseAccount)
          ? _expenseAccount
          : expenseAccounts.first['code'] as String;
      final ledgerAccounts = accounts;
      final selectedLedger = ledgerAccounts.any((a) => a['code'] == _ledgerAccount)
          ? _ledgerAccount
          : accounts.isEmpty ? null : accounts.first['code'] as String;
      final ledger = selectedLedger == null
          ? null
          : await widget.repository.getAccountLedger(selectedLedger, fromDate: fromDate, toDate: toDate);
      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _journal = journal;
        _trialBalance = trial;
        _expenseAccount = selectedExpense;
        _ledgerAccount = selectedLedger;
        _ledger = ledger;
        _reconciliations = reconciliations;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('بارگذاری گزارش‌های مالی ناموفق بود: $error');
    }
  }

  Future<void> _selectLedger(String? code) async {
    if (code == null) return;
    try {
      final result = await widget.repository.getAccountLedger(code,
        fromDate: _isoDate(_reportFrom), toDate: _isoDate(_reportTo));
      if (!mounted) return;
      setState(() {
        _ledgerAccount = code;
        _ledger = result;
      });
    } catch (error) {
      _message('خواندن دفتر حساب ناموفق بود: $error');
    }
  }

  Future<void> _saveExpense() async {
    final amount = _parseAmount(_amount.text);
    if (_description.text.trim().isEmpty || amount == null || amount <= 0) {
      _message('شرح هزینه و مبلغ معتبر را وارد کنید');
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.repository.recordExpense(
        expenseDate: DateTime(_expenseDate.year, _expenseDate.month, _expenseDate.day).toIso8601String().substring(0, 10),
        description: _description.text.trim(),
        amount: amount,
        expenseAccountCode: _expenseAccount,
        cashAccountCode: _cashAccount,
        idempotencyKey: 'expense-${DateTime.now().microsecondsSinceEpoch}',
      );
      _description.clear();
      _amount.clear();
      await _load();
      if (!mounted) return;
      _message('هزینه ثبت شد و سند حسابداری متوازن ایجاد شد');
    } catch (error) {
      _message('ثبت هزینه ناموفق بود: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }


  Future<void> _saveReconciliation() async {
    final balance = _parseAmount(_statementBalance.text);
    if (balance == null || balance < 0) {
      _message('مانده صورت‌حساب بانکی را به‌درستی وارد کنید');
      return;
    }
    if (_reportFrom.isAfter(_reportTo)) {
      _message('تاریخ شروع گزارش نباید بعد از تاریخ پایان باشد');
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.repository.createBankReconciliation(
        accountCode: _reconciliationAccount,
        statementDate: _isoDate(_statementDate),
        statementBalance: balance,
        note: _reconciliationNote.text.trim(),
        idempotencyKey: 'bank-reconcile-${DateTime.now().microsecondsSinceEpoch}',
      );
      _statementBalance.clear();
      _reconciliationNote.clear();
      await _load();
      if (!mounted) return;
      _message('صورت‌حساب ثبت و اختلاف با مانده دفاتر محاسبه شد');
    } catch (error) {
      _message('ثبت تطبیق بانکی ناموفق بود: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _isoDate(DateTime value) =>
      DateTime(value.year, value.month, value.day).toIso8601String().substring(0, 10);

  Widget _reportDateControls() => Card(
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('محدوده گزارش (تاریخ شمسی)', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          JalaliDateField(
            key: ValueKey('report-from-${_isoDate(_reportFrom)}'),
            initialDate: _reportFrom,
            label: 'از تاریخ',
            onChanged: (date) => setState(() => _reportFrom = date),
          ),
          const SizedBox(height: 8),
          JalaliDateField(
            key: ValueKey('report-to-${_isoDate(_reportTo)}'),
            initialDate: _reportTo,
            label: 'تا تاریخ',
            onChanged: (date) => setState(() => _reportTo = date),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () {
              if (_reportFrom.isAfter(_reportTo)) {
                _message('تاریخ شروع نباید بعد از تاریخ پایان باشد');
              } else {
                _load();
              }
            },
            icon: const Icon(Icons.filter_alt),
            label: const Text('اعمال فیلتر تاریخ'),
          ),
        ],
      ),
    ),
  );

  int? _parseAmount(String value) {
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    var normalized = value.trim().replaceAll(',', '').replaceAll('٬', '');
    for (var i = 0; i < 10; i++) {
      normalized = normalized.replaceAll(persian[i], '$i').replaceAll(arabic[i], '$i');
    }
    return int.tryParse(normalized);
  }

  String _money(Object? value) => ((value as num?)?.toInt() ?? 0).toString();
  String _date(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed == null ? '—' : formatJalaliDate(parsed);
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _accounts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final expenses = _accounts.where((a) => a['account_type'] == 'expense').toList();
    final ledgerLines = (_ledger?['lines'] as List<Map<String, Object?>>?) ?? [];
    return DefaultTabController(
      length: 5,
      child: Column(
        children: [
          const Material(
            color: Colors.white,
            child: TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: 'ثبت هزینه'),
                Tab(text: 'دفتر روزنامه'),
                Tab(text: 'تراز آزمایشی'),
                Tab(text: 'دفتر کل حساب'),
                Tab(text: 'تطبیق بانکی'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text('ثبت هزینه‌های مغازه', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    JalaliDateField(
                      initialDate: _expenseDate,
                      label: 'تاریخ هزینه',
                      onChanged: (date) => setState(() => _expenseDate = date),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _description,
                      decoration: const InputDecoration(labelText: 'شرح هزینه'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _amount,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'مبلغ (تومان)'),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      key: ValueKey(_expenseAccount),
                      initialValue: _expenseAccount,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'گروه هزینه'),
                      items: [
                        for (final account in expenses)
                          DropdownMenuItem(
                            value: account['code'] as String,
                            child: Text('${account['name']}'),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _expenseAccount = value);
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      key: ValueKey(_cashAccount),
                      initialValue: _cashAccount,
                      decoration: const InputDecoration(labelText: 'پرداخت از'),
                      items: const [
                        DropdownMenuItem(value: '1000', child: Text('صندوق')),
                        DropdownMenuItem(value: '1010', child: Text('بانک')),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _cashAccount = value);
                      },
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _saving ? null : _saveExpense,
                      icon: const Icon(Icons.save),
                      label: Text(_saving ? 'در حال ثبت...' : 'ثبت هزینه و سند حسابداری'),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'پس از ثبت، سند بدهکار هزینه و بستانکار صندوق/بانک به‌صورت خودکار ایجاد می‌شود. سند ثبت‌شده قابل ویرایش یا حذف نیست و اصلاح آن باید با سند برگشت انجام شود.',
                      style: TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                  ],
                ),
                RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      const Text('دفتر روزنامه', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                      _reportDateControls(),
                      for (final entry in _journal)
                        Card(
                          child: ExpansionTile(
                            title: Text('${entry['description']}'),
                            subtitle: Text('سند ${entry['id']}  •  ${_date(entry['entry_date'])}'),
                            children: [
                              for (final line in (entry['lines'] as List<Map<String, Object?>>))
                                ListTile(
                                  dense: true,
                                  title: Text('${line['account_name']}'),
                                  subtitle: Text(line['memo']?.toString() ?? ''),
                                  trailing: Text(
                                    (line['debit'] as num).toInt() > 0
                                      ? 'بدهکار: ${_money(line['debit'])}'
                                      : 'بستانکار: ${_money(line['credit'])}',
                                  ),
                                ),
                            ],
                          ),
                        ),
                      if (_journal.isEmpty) const Text('هنوز سند حسابداری ثبت نشده است'),
                    ],
                  ),
                ),
                RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      const Text('تراز آزمایشی', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                      _reportDateControls(),
                      const Text('مانده‌ها بر اساس جمع گردش بدهکار و بستانکار از ابتدای اطلاعات ثبت‌شده محاسبه می‌شوند.'),
                      const SizedBox(height: 8),
                      for (final row in _trialBalance)
                        Card(
                          child: ListTile(
                            title: Text('${row['account_code']} — ${row['account_name']}'),
                            subtitle: Text('بدهکار: ${_money(row['total_debit'])}  |  بستانکار: ${_money(row['total_credit'])}'),
                            trailing: Text(_money((row['balance_debit_minus_credit'] as num).abs())),
                          ),
                        ),
                    ],
                  ),
                ),
                RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      const Text('دفتر کل حساب', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                      _reportDateControls(),
                      DropdownButtonFormField<String>(
                        key: ValueKey(_ledgerAccount),
                        initialValue: _ledgerAccount,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'انتخاب حساب'),
                        items: [
                          for (final account in _accounts)
                            DropdownMenuItem(
                              value: account['code'] as String,
                              child: Text('${account['code']} — ${account['name']}'),
                            ),
                        ],
                        onChanged: _selectLedger,
                      ),
                      const SizedBox(height: 8),
                      if (_ledger != null)
                        Card(
                          child: ListTile(
                            title: Text('مانده پایان: ${_money((_ledger!['closing_balance'] as num).abs())} تومان'),
                            subtitle: Text('مانده اول دوره (بدهکار منهای بستانکار): ${_money(_ledger!['opening_balance'])}'),
                          ),
                        ),
                      for (final line in ledgerLines)
                        Card(
                          child: ListTile(
                            title: Text('${line['description']}'),
                            subtitle: Text(_date(line['entry_date'])),
                            trailing: Text(
                              (line['debit'] as num).toInt() > 0
                                ? 'بدهکار ${_money(line['debit'])}\nمانده ${_money(line['running_balance'])}'
                                : 'بستانکار ${_money(line['credit'])}\nمانده ${_money(line['running_balance'])}',
                              textAlign: TextAlign.end,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      const Text('تطبیق صندوق و بانک', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                      const Text('مانده صورت‌حساب بانک را وارد کنید تا با مانده ثبت‌شده در دفتر حسابداری در پایان همان روز مقایسه شود. اختلاف به معنی مغایرت بررسی‌نشده است و به‌صورت خودکار سند اصلاحی ایجاد نمی‌کند.'),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey(_reconciliationAccount),
                        initialValue: _reconciliationAccount,
                        decoration: const InputDecoration(labelText: 'حساب مورد تطبیق'),
                        items: const [
                          DropdownMenuItem(value: '1010', child: Text('بانک')),
                          DropdownMenuItem(value: '1000', child: Text('صندوق')),
                        ],
                        onChanged: (value) {
                          if (value != null) setState(() => _reconciliationAccount = value);
                        },
                      ),
                      const SizedBox(height: 10),
                      JalaliDateField(
                        initialDate: _statementDate,
                        label: 'تاریخ صورت‌حساب',
                        onChanged: (date) => setState(() => _statementDate = date),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _statementBalance,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'مانده پایان صورت‌حساب (تومان)'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _reconciliationNote,
                        decoration: const InputDecoration(labelText: 'توضیحات / شماره صورت‌حساب'),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _saving ? null : _saveReconciliation,
                        icon: const Icon(Icons.compare_arrows),
                        label: Text(_saving ? 'در حال ثبت...' : 'محاسبه و ثبت تطبیق'),
                      ),
                      const SizedBox(height: 16),
                      const Text('سوابق تطبیق', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                      for (final item in _reconciliations)
                        Card(
                          child: ListTile(
                            title: Text('${item['account_code'] == '1010' ? 'بانک' : 'صندوق'} — ${_date(item['statement_date'])}'),
                            subtitle: Text('مانده دفتر: ${_money(item['book_balance'])} | صورت‌حساب: ${_money(item['statement_balance'])}\n${item['note'] ?? ''}'),
                            isThreeLine: true,
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('اختلاف: ${_money((item['difference'] as num).abs())}'),
                                Text((item['difference'] as num) == 0 ? 'مطابق' : ((item['difference'] as num) > 0 ? 'صورت‌حساب بیشتر' : 'دفتر بیشتر'),
                                  style: TextStyle(color: (item['difference'] as num) == 0 ? Colors.green : Colors.orange, fontSize: 11)),
                              ],
                            ),
                          ),
                        ),
                      if (_reconciliations.isEmpty) const Text('هنوز تطبیق بانکی ثبت نشده است'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
