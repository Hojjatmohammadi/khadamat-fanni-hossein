import 'package:material_ui/material_ui.dart';

import 'jalali_date_field.dart';
import 'party_repository.dart';

class PartyLedgerPage extends StatefulWidget {
  const PartyLedgerPage({super.key, required this.repository});

  final PartyRepository repository;

  @override
  State<PartyLedgerPage> createState() => _PartyLedgerPageState();
}

class _PartyLedgerPageState extends State<PartyLedgerPage> {
  List<Map<String, Object?>> _parties = [];
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
      final parties = await widget.repository.getParties();
      final selected = parties.any((p) => p['id'] == _selectedPartyId)
          ? _selectedPartyId
          : parties.isEmpty
              ? null
              : parties.first['id'] as String;
      Map<String, Object?>? statement;
      if (selected != null) {
        statement = await widget.repository.getPartyStatementPage(
          selected,
          limit: _pageSize,
        );
      }
      if (!mounted) return;
      setState(() {
        _parties = parties;
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
      if (!mounted) return;
      setState(() {
        _statement = result;
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

  String _partyTypeLabel(Object? type) => switch (type) {
        'customer' => 'مشتری',
        'supplier' => 'فروشنده',
        _ => 'شخص دیگر',
      };

  String _amount(Object? value) =>
      ((value as num?)?.toInt() ?? 0).toString();

  @override
  Widget build(BuildContext context) {
    final party = _statement?['party'] as Map<String, Object?>?;
    final lines = (_statement?['lines'] as List<Map<String, Object?>>?) ?? [];
    final closing = (_statement?['closing_balance'] as num?)?.toInt() ?? 0;
    final partyQuery = _partySearchController.text.trim().toLowerCase();
    final visibleParties = _parties.where((item) => ['display_name', 'phone', 'party_type'].any((key) => (item[key]?.toString() ?? '').toLowerCase().contains(partyQuery))).toList();

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
                        '${item['display_name']}'
                            '${(item['phone']?.toString().trim().isNotEmpty ?? false) ? ' • ${item['phone']}' : ''}'
                            ' — ${_partyTypeLabel(item['party_type'])}',
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
                      Text(_partyTypeLabel(party?['party_type'])),
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
                      '${formatJalaliDate(DateTime.parse(line['entry_date'] as String))} • ${line['account_name']}',
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
