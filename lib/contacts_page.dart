import 'package:flutter/material.dart';

import 'party_ledger_page.dart';
import 'phone_contact_picker.dart';
import 'party_repository.dart';

class ContactsPage extends StatefulWidget {
  const ContactsPage({super.key, required this.repository});

  final PartyRepository repository;

  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  static const _roles = ['customer', 'supplier', 'other'];
  static const _roleLabels = {
    'customer': 'مشتری',
    'supplier': 'فروشنده',
    'other': 'سایر',
  };

  final _searchController = TextEditingController();
  List<Map<String, Object?>> _contacts = [];
  String _roleFilter = 'all';
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final parties = await widget.repository.getParties();
      final contacts = await Future.wait(parties.map((party) async {
        final id = party['id'] as String;
        return <String, Object?>{
          ...party,
          'roles': await widget.repository.getPartyRoles(id),
        };
      }));
      if (!mounted) return;
      setState(() {
        _contacts = contacts;
        _loading = false;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error.toString();
      });
    }
  }

  List<Map<String, Object?>> get _visibleContacts {
    final query = _normalize(_searchController.text);
    return _contacts.where((contact) {
      final roles = (contact['roles'] as List?)?.cast<String>() ?? const [];
      if (_roleFilter != 'all' && !roles.contains(_roleFilter)) return false;
      if (query.isEmpty) return true;
      final searchable = [
        contact['display_name'],
        contact['phone'],
        contact['address'],
        ...roles.map((role) => _roleLabels[role] ?? role),
      ].whereType<Object>().join(' ');
      return _normalize(searchable).contains(query);
    }).toList();
  }

  String _normalize(String value) => value
      .replaceAll('ي', 'ی')
      .replaceAll('ك', 'ک')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toLowerCase();

  Future<void> _editContact({Map<String, Object?>? contact}) async {
    final formKey = GlobalKey<FormState>();
    final name = TextEditingController(
      text: contact?['display_name']?.toString() ?? '',
    );
    final phone = TextEditingController(
      text: contact?['phone']?.toString() ?? '',
    );
    final address = TextEditingController(
      text: contact?['address']?.toString() ?? '',
    );
    final notes = TextEditingController(
      text: contact?['notes']?.toString() ?? '',
    );
    final initialRoles =
        (contact?['roles'] as List?)?.cast<String>().toSet() ?? {'customer'};
    final selectedRoles = <String>{...initialRoles};
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (context, refreshDialog) => AlertDialog(
            title: Text(contact == null ? 'افزودن مخاطب' : 'ویرایش مخاطب'),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: name,
                        autofocus: true,
                        decoration: const InputDecoration(labelText: 'نام و نام خانوادگی'),
                        validator: (value) => value == null || value.trim().isEmpty
                            ? 'نام مخاطب را وارد کنید'
                            : null,
                      ),
                      const SizedBox(height: 10),
                      PhoneContactPickerButton(
                        onSelected: (selected) {
                          name.text = selected.name;
                          phone.text = selected.phone;
                        },
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: phone,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'شماره همراه'),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: address,
                        maxLines: 2,
                        decoration: const InputDecoration(labelText: 'نشانی'),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: notes,
                        maxLines: 2,
                        decoration: const InputDecoration(labelText: 'توضیحات'),
                      ),
                      const SizedBox(height: 14),
                      const Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'نقش‌های این شخص',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      for (final role in _roles)
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(_roleLabels[role]!),
                          value: selectedRoles.contains(role),
                          onChanged: (value) {
                            refreshDialog(() {
                              if (value == true) {
                                selectedRoles.add(role);
                              } else if (selectedRoles.length > 1) {
                                selectedRoles.remove(role);
                              }
                            });
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('انصراف'),
              ),
              FilledButton.icon(
                onPressed: () {
                  if (!formKey.currentState!.validate() || selectedRoles.isEmpty) {
                    return;
                  }
                  Navigator.pop(dialogContext, true);
                },
                icon: const Icon(Icons.save_outlined),
                label: const Text('ذخیره مخاطب'),
              ),
            ],
          ),
        ),
      ),
    );

    if (saved == true && mounted) {
      try {
        final roles = _roles.where(selectedRoles.contains).toList();
        final draft = PartyDraft(
          partyType: roles.first,
          additionalRoles: roles.skip(1).toList(),
          displayName: name.text.trim(),
          phone: phone.text.trim(),
          address: address.text.trim(),
          notes: notes.text.trim(),
        );
        final id = contact?['id']?.toString();
        if (id == null) {
          await widget.repository.ensureParty(draft);
        } else {
          await widget.repository.updateParty(partyId: id, draft: draft);
        }
        await _loadContacts();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('اطلاعات مخاطب ذخیره شد.')),
          );
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('ذخیره مخاطب ناموفق بود: $error')),
          );
        }
      }
    }
    name.dispose();
    phone.dispose();
    address.dispose();
    notes.dispose();
  }

  Future<void> _deleteContact(Map<String, Object?> contact) async {
    final id = contact['id']?.toString();
    if (id == null || id.isEmpty) return;
    final name = contact['display_name']?.toString() ?? 'این مخاطب';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف مخاطب'),
          content: Text('مخاطب «$name» فقط در صورتی حذف می‌شود که هیچ فاکتور، چک یا سند حسابداری وابسته‌ای نداشته باشد. ادامه می‌دهید؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('حذف مخاطب'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.repository.deleteParty(id);
      await _loadContacts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('مخاطب حذف شد.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', ''))),
        );
      }
    }
  }

  Future<void> _showContactActions(Map<String, Object?> contact) async {
    final name = contact['display_name']?.toString() ?? 'مخاطب';
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(name),
          content: const Text('برای این مخاطب چه کاری انجام می‌دهید؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'cancel'),
              child: const Text('بستن'),
            ),
            TextButton.icon(
              onPressed: () => Navigator.pop(dialogContext, 'ledger'),
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: const Text('پرونده و گردش حساب'),
            ),
            TextButton.icon(
              onPressed: () => Navigator.pop(dialogContext, 'edit'),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('ویرایش'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, 'delete'),
              icon: const Icon(Icons.delete_outline),
              label: const Text('حذف'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null || action == 'cancel') return;
    if (action == 'edit') {
      await _editContact(contact: contact);
    } else if (action == 'delete') {
      await _deleteContact(contact);
    } else if (action == 'ledger') {
      _openLedger(contact);
    }
  }

  void _openLedger(Map<String, Object?> contact) {
    final id = contact['id']?.toString();
    if (id == null || id.isEmpty) return;
    final displayName = contact['display_name']?.toString() ?? 'مخاطب';
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text('پرونده $displayName')),
          body: PartyLedgerPage(
            repository: widget.repository,
            initialPartyId: id,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final contacts = _visibleContacts;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'جست‌وجوی نام یا شماره همراه',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'پاک کردن جست‌وجو',
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.close),
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'افزودن مخاطب',
                  onPressed: () => _editContact(),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: DropdownButtonFormField<String>(
              value: _roleFilter,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'فیلتر نقش مخاطب',
                prefixIcon: Icon(Icons.filter_list),
              ),
              items: [
                const DropdownMenuItem(value: 'all', child: Text('همه مخاطبین')),
                for (final role in _roles)
                  DropdownMenuItem(
                    value: role,
                    child: Text(_roleLabels[role]!),
                  ),
              ],
              onChanged: (value) => setState(() => _roleFilter = value ?? 'all'),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _loadError != null
                    ? Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.cloud_off_outlined,
                                size: 48,
                                color: Colors.redAccent,
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'بارگذاری دفتر مخاطبین ناموفق بود',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              SelectableText(
                                _loadError!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 12),
                              ),
                              const SizedBox(height: 14),
                              FilledButton.icon(
                                onPressed: _loadContacts,
                                icon: const Icon(Icons.refresh),
                                label: const Text('تلاش دوباره'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : contacts.isEmpty
                        ? Center(
                            child: Text(
                              _contacts.isEmpty
                                  ? 'هنوز مخاطبی ثبت نشده است.'
                                  : 'مخاطبی با این جست‌وجو یا نقش پیدا نشد.',
                            ),
                          )
                        : RefreshIndicator(
                        onRefresh: _loadContacts,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 28),
                          itemCount: contacts.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 6),
                          itemBuilder: (context, index) {
                            final contact = contacts[index];
                            final roles =
                                (contact['roles'] as List?)?.cast<String>() ?? const [];
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                child: Column(
                                  children: [
                                    ListTile(
                                      onTap: () => _showContactActions(contact),
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(
                                        contact['display_name']?.toString() ?? 'بدون نام',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      subtitle: Text(
                                        [
                                          if ((contact['phone']?.toString() ?? '').isNotEmpty)
                                            contact['phone'].toString(),
                                          if ((contact['address']?.toString() ?? '').isNotEmpty)
                                            contact['address'].toString(),
                                        ].join(' • ').isEmpty
                                            ? 'شماره و نشانی ثبت نشده است'
                                            : [
                                                if ((contact['phone']?.toString() ?? '').isNotEmpty)
                                                  contact['phone'].toString(),
                                                if ((contact['address']?.toString() ?? '').isNotEmpty)
                                                  contact['address'].toString(),
                                              ].join(' • '),
                                      ),
                                      trailing: Wrap(
                                        spacing: 0,
                                        children: [
                                          IconButton(
                                            tooltip: 'پرونده و گردش حساب',
                                            onPressed: () => _openLedger(contact),
                                            icon: const Icon(Icons.account_balance_wallet_outlined),
                                          ),
                                          IconButton(
                                            tooltip: 'ویرایش مخاطب',
                                            onPressed: () => _editContact(contact: contact),
                                            icon: const Icon(Icons.edit_outlined),
                                          ),
                                          IconButton(
                                            tooltip: 'حذف مخاطب',
                                            onPressed: () => _deleteContact(contact),
                                            icon: const Icon(Icons.delete_outline),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          for (final role in roles)
                                            Chip(
                                              visualDensity: VisualDensity.compact,
                                              label: Text(_roleLabels[role] ?? role),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
          ],
        ),
      ),
    );
  }
}
