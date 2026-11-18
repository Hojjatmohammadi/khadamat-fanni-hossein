import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khadamat_fanni_hosein/phone_contact_picker.dart';

void main() {
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
