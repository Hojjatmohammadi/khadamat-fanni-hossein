import 'package:material_ui/material_ui.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khadamat_fanni_hosein/phone_contact_picker.dart';

void main() {
  test('prefers mobile number even when a home phone appears first', () {
    final phone = preferredMobilePhoneNumber([
      Phone(number: '02112345678', label: Label(PhoneLabel.home)),
      Phone(number: '09123456789', label: Label(PhoneLabel.mobile)),
    ]);

    expect(phone, '09123456789');
  });

  test('uses work-mobile before other numbers when no personal mobile exists', () {
    final phone = preferredMobilePhoneNumber([
      Phone(number: '02112345678', label: Label(PhoneLabel.home)),
      Phone(number: '09129876543', label: Label(PhoneLabel.workMobile)),
    ]);

    expect(phone, '09129876543');
  });

  test('falls back to the first non-empty number if no mobile label exists', () {
    final phone = preferredMobilePhoneNumber([
      Phone(number: '   ', label: Label(PhoneLabel.home)),
      Phone(number: '02112345678', label: Label(PhoneLabel.home)),
      Phone(number: '04412345678', label: Label(PhoneLabel.work)),
    ]);

    expect(phone, '02112345678');
  });

  test('returns an empty value when a contact has no phone numbers', () {
    expect(preferredMobilePhoneNumber(const []), isEmpty);
  });

  testWidgets('picker button returns the selected phone contact', (tester) async {
    PhoneContactSelection? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PhoneContactPickerButton(
            loader: () async => const PhoneContactSelection(
              name: 'احمد رضایی',
              phone: '09123456789',
            ),
            onSelected: (contact) => selected = contact,
          ),
        ),
      ),
    );

    await tester.tap(find.text('انتخاب از مخاطبین گوشی'));
    await tester.pumpAndSettle();

    expect(selected?.name, 'احمد رضایی');
    expect(selected?.phone, '09123456789');
  });

  testWidgets('selected name is kept when phone permission is denied', (tester) async {
    PhoneContactSelection? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PhoneContactPickerButton(
            loader: () async => const PhoneContactSelection(
              name: 'احمد رضایی',
              phone: '',
              phonePermissionDenied: true,
            ),
            onSelected: (contact) => selected = contact,
          ),
        ),
      ),
    );

    await tester.tap(find.text('انتخاب از مخاطبین گوشی'));
    await tester.pumpAndSettle();

    expect(selected?.name, 'احمد رضایی');
    expect(selected?.phone, isEmpty);
    expect(
      find.text('نام انتخاب شد؛ برای خواندن شماره، مجوز مخاطبین گوشی را فعال کنید.'),
      findsOneWidget,
    );
  });

  testWidgets('cancelling the system picker does not change the selection', (tester) async {
    var called = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PhoneContactPickerButton(
            loader: () async => null,
            onSelected: (_) => called = true,
          ),
        ),
      ),
    );

    await tester.tap(find.text('انتخاب از مخاطبین گوشی'));
    await tester.pumpAndSettle();

    expect(called, isFalse);
  });
}
