import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khadamat_fanni_hosein/main.dart';

void main() {
  group('PersianDateInputFormatter', () {
    final formatter = PersianDateInputFormatter();

    test('formats eight Persian digits as a Jalali date', () {
      final result = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(
          text: '۱۴۰۵۰۸۲۳',
          selection: TextSelection.collapsed(offset: 8),
        ),
      );
      expect(result.text, '۱۴۰۵/۰۸/۲۳');
    });

    test('converts western digits to Persian and adds separators', () {
      final result = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(
          text: '14050823',
          selection: TextSelection.collapsed(offset: 8),
        ),
      );
      expect(result.text, '۱۴۰۵/۰۸/۲۳');
    });

    test('rejects non-digit characters and caps input at eight digits', () {
      final result = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(
          text: '1405-08-23abc99',
          selection: TextSelection.collapsed(offset: 14),
        ),
      );
      expect(result.text, '۱۴۰۵/۰۸/۲۳');
    });
  });
}
