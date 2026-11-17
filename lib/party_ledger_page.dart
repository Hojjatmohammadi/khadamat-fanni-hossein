import 'package:material_ui/material_ui.dart';

import 'check_repository.dart';
import 'checks_page.dart';
import 'jalali_date_field.dart';
import 'localized_number.dart';
import 'party_repository.dart';
import 'trade_repository.dart';

class PartyLedgerPage extends StatefulWidget {
  const PartyLedgerPage({
    super.key,
    required this.repository,
    this.trades,
    this.checks,
    this.onChanged,
    this.initialPartyId,
  });

  final PartyRepository repository;
  final TradeRepository? trades;
  final CheckRepository? checks;
  final VoidCallback? onChanged;
  final String? initialPartyId;

  @override
  State<PartyLedgerPage> createState() => _PartyLedgerPageState();
}

class _PartyLedgerPageState extends State<PartyLedgerPage> {
  List<Map<String, Object?>> _parties = [];
  List<Map<String, Object?>> _activityDocuments = [];
  List<Map<String, Object?>> _activityRepairs = [];
  List<Map<String, Object?>> _activityChecks = [];
  Map<String, Object?>? _statement;
  String? _selectedPartyId;
  final _partySearchController = TextEditingController();
  bool _loading = true;
  bool _loadingMore = false;
  int _nextOffset = 0;
  bool _hasMore = false;
  static const int _pageSize = 100;

  @override
  void dispose() {
    _partySearchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadParties();
  }

  Future<void> _loadParties() async {
    setState(() => _loading = true);
    try {
      final storedParties = await widget.repository.getParties();
      final parties = await Future.wait(storedParties.map((party) async {
        final id = party['id'] as String;
        return <String, Object?>{
          ...party,
          'roles': await widget.repository.getPartyRoles(id),
        };
      }));
      final preferredId = _selectedPartyId ?? widget.initialPartyId;
      final selected = parties.any((p) => p['id'] == preferredId)
          ? preferredId
          : parties.isEmpty
              ? null
              : parties.first['id'] as String;
      Map<String, Object?>? statement;
      Map<String, List<Map<String, Object?>>> activity = {
        'documents': [],
        'repairs': [],
        'checks': [],
      };
      if (selected != null) {
        statement = await widget.repository.getPartyStatementPage(
          selected,
          limit: _pageSize,
        );
        activity = await widget.repository.getPartyActivity(selected);
      }
      if (!mounted) return;
      setState(() {
        _parties = parties;
        _activityDocuments = activity['documents'] ?? [];
        _activityRepairs = activity['repairs'] ?? [];
        _activityChecks = activity['checks'] ?? [];
        _selectedPartyId = selected;
        _statement = statement;
        _nextOffset = (statement?['next_offset'] as num?)?.toInt() ?? 0;
        _hasMore = statement?['has_more'] == true;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('بارگذاری دفتر اشخاص ناموفق بود: $error')),
      );
    }
  }

  Future<void> _selectParty(String? id) async {
    if (id == null) return;
    setState(() {
      _selectedPartyId = id;
      _statement = null;
      _loading = true;
      _loadingMore = false;
      _nextOffset = 0;
      _hasMore = false;
    });
    try {
      final result = await widget.repository.getPartyStatementPage(
        id,
        limit: _pageSize,
      );
      final activity = await widget.repository.getPartyActivity(id);
      if (!mounted) return;
      setState(() {
        _statement = result;
        _activityDocuments = activity['documents'] ?? [];
        _activityRepairs = activity['repairs'] ?? [];
        _activityChecks = activity['checks'] ?? [];
        _nextOffset = (result['next_offset'] as num?)?.toInt() ?? 0;
        _hasMore = result['has_more'] == true;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خواندن گردش حساب ناموفق بود: $error')),
      );
    }
  }

  Future<void> _recordPartyPayment({required bool isCustomerReceipt}) async {
    final trades = widget.trades;
    final partyId = _selectedPartyId;
    final party = _statement?['party'] as Map<String, Object?>?;
    if (trades == null || partyId == null || party == null) return;

    final roles = (_statement?['roles'] as List?)?.cast<String>() ?? const [];
    if (isCustomerReceipt && !roles.contains('customer')) return;
    if (!isCustomerReceipt && !roles.contains('supplier')) return;

    final amountController = TextEditingController();
    var paymentMethod = 'cash';
    final amount = await showDialog<int?>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text(
              isCustomerReceipt ? 'ثبت بیعانه / دریافت از مشتری' : 'ثبت پیش‌پرداخت به فروشنده',
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isCustomerReceipt
                      ? 'مبلغ به‌عنوان بستانکاری این مشتری در گردش حساب ثبت می‌شود و به فاکتور خاصی متصل نیست.'
                      : 'مبلغ به‌عنوان پرداخت به این فروشنده در گردش حساب ثبت می‌شود و به فاکتور خاصی متصل نیست.',
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('party-ledger-advance-amount'),
                  controller: amountController,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'مبلغ (تومان)'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const ValueKey('party-ledger-advance-method'),
                  initialValue: paymentMethod,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'روش دریافت / پرداخت'),
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('نقدی')),
                    DropdownMenuItem(value: 'bank_transfer', child: Text('انتقال بانکی')),
                    DropdownMenuItem(value: 'card_to_card', child: Text('کارت‌به‌کارت')),
                  ],
                  onChanged: (value) => refresh(() => paymentMethod = value ?? 'cash'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('انصراف'),
              ),
              FilledButton(
                onPressed: () {
                  final parsed = LocalizedNumber.tryParseInt(amountController.text);
                  if (parsed == null || parsed <= 0) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(content: Text('مبلغ باید عدد معتبر و بیشتر از صفر باشد')),
                    );
                    return;
                  }
                  Navigator.pop(dialogContext, parsed);
                },
                child: const Text('ثبت در گردش حساب'),
              ),
            ],
          ),
        ),
      ),
    );
    amountController.dispose();
    if (amount == null || !mounted) return;

    try {
      final cashAccountCode = paymentMethod == 'cash' ? '1000' : '1010';
      final draft = PartyPaymentDraft(
        documentDate: DateTime.now().toIso8601String().substring(0, 10),
        counterpartyName: party['display_name']?.toString() ?? 'طرف حساب',
        counterpartyId: partyId,
        amount: amount,
        idempotencyKey:
            'party-advance-$partyId-${DateTime.now().microsecondsSinceEpoch}',
        cashAccountCode: cashAccountCode,
        paymentMethod: paymentMethod,
      );
      if (isCustomerReceipt) {
        await trades.recordCustomerReceipt(draft);
      } else {
        await trades.recordSupplierPayment(draft);
      }
      await _selectParty(partyId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isCustomerReceipt ? 'بیعانه مشتری در گردش حساب ثبت شد' : 'پیش‌پرداخت فروشنده ثبت شد',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ثبت دریافت / پرداخت ناموفق بود: $error')),
      );
    }
  }

  Future<void> _openCheckEntry({required bool incoming}) async {
    final checks = widget.checks;
    final trades = widget.trades;
    final partyId = _selectedPartyId;
    if (checks == null || trades == null || partyId == null) return;

    final party = _statement?['party'] as Map<String, Object?>?;
    if (party == null) return;
    final displayName = party['display_name']?.toString() ?? 'طرف حساب';
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text(incoming ? 'ثبت چک دریافتی • $displayName' : 'ثبت چک پرداختی • $displayName'),
          ),
          body: CheckPage(
            checks: checks,
            parties: widget.repository,
            trades: trades,
            onChanged: widget.onChanged ?? () {},
            initialPartyId: partyId,
            initialDirection: incoming ? 'incoming' : 'outgoing',
          ),
        ),
      ),
    );
    if (mounted) await _selectParty(partyId);
  }

  Future<void> _loadMore() async {
    final partyId = _selectedPartyId;
    if (partyId == null || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.repository.getPartyStatementPage(
        partyId,
        limit: _pageSize,
        offset: _nextOffset,
      );
      if (!mounted || partyId != _selectedPartyId) return;
      final existing = List<Map<String, Object?>>.from(
        (_statement?['lines'] as List?) ?? const [],
      );
      final incoming = List<Map<String, Object?>>.from(
        (page['lines'] as List?) ?? const [],
      );
      setState(() {
        _statement = {
          ...?_statement,
          ...page,
          'lines': [...existing, ...incoming],
        };
        _nextOffset = (page['next_offset'] as num?)?.toInt() ?? _nextOffset;
        _hasMore = page['has_more'] == true;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('بارگذاری ادامه گردش حساب ناموفق بود: $error')),
      );
    }
  }

  String _partyTypeLabel(Object? type, [List<String> roles = const []]) {
    const labels = {
      'customer': 'مشتری',
      'supplier': 'فروشنده',
      'other': 'سایر',
    };
    if (roles.isNotEmpty) {
      return roles.map((role) => labels[role] ?? role).join('، ');
    }
    return labels[type] ?? 'شخص دیگر';
  }

  String _amount(Object? value) =>
      ((value as num?)?.toInt() ?? 0).toString();

  String _dateLabel(Object? value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    return date == null ? '—' : formatJalaliDate(date);
  }

  String _documentTypeLabel(Object? type) => switch (type) {
        'purchase' => 'فاکتور خرید',
        'sale' => 'فاکتور فروش',
        'supplier_return' => 'برگشت از خرید',
        'customer_return' => 'برگشت از فروش',
        _ => 'سند تجاری',
      };

  @override
  Widget build(BuildContext context) {
    final party = _statement?['party'] as Map<String, Object?>?;
    final lines = (_statement?['lines'] as List<Map<String, Object?>>?) ?? [];
    final closing = (_statement?['closing_balance'] as num?)?.toInt() ?? 0;
    final selectedRoles =
        (_statement?['roles'] as List?)?.cast<String>() ?? const <String>[];
    final partyQuery = _partySearchController.text.trim().toLowerCase();
    final visibleParties = _parties.where((item) {
      final searchable = [
        item['display_name'],
        item['phone'],
        item['party_type'],
        ...((item['roles'] as List?) ?? const []),
      ].whereType<Object>().join(' ').toLowerCase();
      return searchable.contains(partyQuery);
    }).toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: RefreshIndicator(
        onRefresh: _loadParties,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            const Text(
              'دفتر گردش حساب اشخاص',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (_parties.isNotEmpty) ...[
              TextField(
                controller: _partySearchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'جست‌وجو در اشخاص',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _partySearchController.text.isEmpty ? null : IconButton(
                    tooltip: 'پاک کردن جست‌وجو',
                    onPressed: () { _partySearchController.clear(); setState(() {}); },
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: ValueKey(_selectedPartyId),
                initialValue: visibleParties.any((item) => item['id'] == _selectedPartyId) ? _selectedPartyId : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'انتخاب مشتری یا فروشنده'),
                items: [
                  for (final item in visibleParties)
                    DropdownMenuItem(
                      value: item['id'] as String,
                      child: Text(
                        (item['display_name']?.toString() ?? '') +
                            ((item['phone']?.toString().trim().isNotEmpty ?? false)
                                ? ' • ${item['phone']}'
                                : '') +
                            ' — ${_partyTypeLabel(item['party_type'], (item['roles'] as List?)?.cast<String>() ?? const [])}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _selectParty,
              ),
            ],
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_parties.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'هنوز طرف حسابی ثبت نشده است. با ثبت خرید، فروش یا چک، اشخاص به این فهرست افزوده می‌شوند.',
                  ),
                ),
              )
            else if (_statement != null) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        party?['display_name']?.toString() ?? '',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      Text(_partyTypeLabel(
                        party?['party_type'],
                        (_statement?['roles'] as List?)?.cast<String>() ?? const [],
                      )),
                      const Divider(),
                      Text('جمع بدهکار: ${_amount(_statement?['total_debit'])} تومان'),
                      Text('جمع بستانکار: ${_amount(_statement?['total_credit'])} تومان'),
                      const SizedBox(height: 6),
                      Text(
                        '${_statement?['closing_label']}: ${closing.abs()} تومان',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.trades != null &&
                  (selectedRoles.contains('customer') || selectedRoles.contains('supplier'))) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (selectedRoles.contains('customer'))
                      FilledButton.icon(
                        key: const ValueKey('record-customer-advance'),
                        onPressed: () => _recordPartyPayment(isCustomerReceipt: true),
                        icon: const Icon(Icons.savings_outlined),
                        label: const Text('ثبت بیعانه / دریافت'),
                      ),
                    if (selectedRoles.contains('customer') && widget.checks != null)
                      OutlinedButton.icon(
                        key: const ValueKey('record-customer-check'),
                        onPressed: () => _openCheckEntry(incoming: true),
                        icon: const Icon(Icons.request_quote_outlined),
                        label: const Text('ثبت چک دریافتی'),
                      ),
                    if (selectedRoles.contains('supplier'))
                      OutlinedButton.icon(
                        key: const ValueKey('record-supplier-prepayment'),
                        onPressed: () => _recordPartyPayment(isCustomerReceipt: false),
                        icon: const Icon(Icons.payments_outlined),
                        label: const Text('ثبت پیش‌پرداخت به فروشنده'),
                      ),
                    if (selectedRoles.contains('supplier') && widget.checks != null)
                      OutlinedButton.icon(
                        key: const ValueKey('record-supplier-check'),
                        onPressed: () => _openCheckEntry(incoming: false),
                        icon: const Icon(Icons.request_quote_outlined),
                        label: const Text('ثبت چک پرداختی'),
                      ),
                  ],
                ),
              ],
              if (_activityDocuments.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'فاکتورها و برگشت‌ها (${_activityDocuments.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                ),
                for (final document in _activityDocuments)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: Text(
                        '${_documentTypeLabel(document['document_type'])} • ${document['document_number'] ?? ''}',
                      ),
                      subtitle: Text(_dateLabel(document['document_date'])),
                      trailing: Text('${_amount(document['total_amount'])} تومان'),
                    ),
                  ),
              ],
              if (_activityRepairs.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'سابقه تعمیرات (${_activityRepairs.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                ),
                for (final repair in _activityRepairs)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.build_outlined),
                      title: Text(
                        repair['نوع دستگاه']?.toString().isNotEmpty == true
                            ? repair['نوع دستگاه'].toString()
                            : 'پذیرش تعمیر',
                      ),
                      subtitle: Text(
                        [
                          if ((repair['نام دستگاه']?.toString() ?? '').isNotEmpty)
                            repair['نام دستگاه'].toString(),
                          if ((repair['وضعیت']?.toString() ?? '').isNotEmpty)
                            repair['وضعیت'].toString(),
                          _dateLabel(repair['تاریخ'] ?? repair['created_at']),
                        ].join(' • '),
                      ),
                    ),
                  ),
              ],
              if (_activityChecks.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'چک‌های مرتبط (${_activityChecks.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                ),
                for (final check in _activityChecks)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.request_quote_outlined),
                      title: Text(
                        '${check['direction'] == 'incoming' ? 'چک دریافتی' : 'چک پرداختی'} • ${check['check_number']}',
                      ),
                      subtitle: Text(
                        '${check['bank_name']} • سررسید: ${_dateLabel(check['due_date'])} • ${check['status']}',
                      ),
                      trailing: Text('${_amount(check['amount'])} تومان'),
                    ),
                  ),
              ],
              const SizedBox(height: 8),
              const Text('گردش حساب', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              if (lines.isEmpty)
                const Card(child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('برای این شخص هنوز سند مالی ثبت نشده است'),
                )),
              for (final line in lines)
                Card(
                  child: ListTile(
                    title: Text(line['description']?.toString() ?? 'سند مالی'),
                    subtitle: Text(
                      '${_dateLabel(line['entry_date'])} • ${line['account_name']}',
                    ),
                    isThreeLine: true,
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if ((line['debit'] as num).toInt() > 0)
                          Text('بدهکار: ${_amount(line['debit'])}'),
                        if ((line['credit'] as num).toInt() > 0)
                          Text('بستانکار: ${_amount(line['credit'])}'),
                        Text(
                          'مانده: ${_amount((line['running_balance'] as num).abs())}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_hasMore || _loadingMore)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: OutlinedButton.icon(
                      onPressed: _loadingMore ? null : _loadMore,
                      icon: _loadingMore
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.expand_more),
                      label: Text(_loadingMore ? 'در حال بارگذاری...' : 'نمایش گردش‌های بعدی'),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
