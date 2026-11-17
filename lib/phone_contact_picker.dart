import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

@immutable
class PhoneContactSelection {
  const PhoneContactSelection({
    required this.name,
    required this.phone,
    this.phonePermissionDenied = false,
  });

  final String name;
  final String phone;
  final bool phonePermissionDenied;
}

/// Opens the system picker first, without requesting access to the full
/// address book. After the user selects one contact, requests read access only
/// to load that contact's phone number.
Future<PhoneContactSelection?> pickDevicePhoneContact() async {
  final picked = await FlutterContacts.native.showPicker();
  if (picked == null) return null;

  final name = (picked.displayName ?? '').trim();
  final contactId = picked.id?.trim() ?? '';
  if (contactId.isEmpty) {
    return PhoneContactSelection(name: name, phone: '');
  }

  final permission = await FlutterContacts.permissions.request(PermissionType.read);
  if (permission != PermissionStatus.granted) {
    return PhoneContactSelection(
      name: name,
      phone: '',
      phonePermissionDenied: true,
    );
  }

  final selectedContact = await FlutterContacts.get(
    contactId,
    properties: {ContactProperty.phone},
  );
  final phone = selectedContact?.phones
      .map((entry) => entry.number.trim())
      .firstWhere((number) => number.isNotEmpty, orElse: () => '') ?? '';

  return PhoneContactSelection(name: name, phone: phone);
}

typedef PhoneContactLoader = Future<PhoneContactSelection?> Function();

class PhoneContactPickerButton extends StatefulWidget {
  const PhoneContactPickerButton({
    super.key,
    required this.onSelected,
    this.loader,
    this.label = 'انتخاب از مخاطبین گوشی',
  });

  final ValueChanged<PhoneContactSelection> onSelected;
  final PhoneContactLoader? loader;
  final String label;

  @override
  State<PhoneContactPickerButton> createState() => _PhoneContactPickerButtonState();
}

class _PhoneContactPickerButtonState extends State<PhoneContactPickerButton> {
  bool _loading = false;

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _pick() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final contact = await (widget.loader ?? pickDevicePhoneContact)();
      if (!mounted || contact == null) return;
      if (contact.name.isEmpty && contact.phone.isEmpty) {
        _showMessage('مخاطب انتخاب‌شده نام یا شمارهٔ قابل استفاده ندارد.');
        return;
      }
      widget.onSelected(contact);
      if (contact.phonePermissionDenied) {
        _showMessage('نام انتخاب شد؛ برای خواندن شماره، مجوز مخاطبین گوشی را فعال کنید.');
      } else if (contact.phone.isEmpty) {
        _showMessage('نام انتخاب شد؛ برای این مخاطب شمارهٔ همراه ثبت نشده است.');
      }
    } on PlatformException catch (error) {
      _showMessage('باز کردن مخاطبین گوشی ناموفق بود: ${error.message ?? error.code}');
    } catch (error) {
      _showMessage('انتخاب مخاطب ناموفق بود: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: OutlinedButton.icon(
        onPressed: _loading ? null : _pick,
        icon: _loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.contacts_outlined),
        label: Text(widget.label),
      ),
    );
  }
}
