import 'package:flutter_test/flutter_test.dart';
import 'package:khadamat_fanni_hosein/numeric_input.dart';

void main() {
  group('NumericInputFormatter', () {
    test('converts Persian/Arabic digits and filters pasted text', () {
      const f = NumericInputFormatter();
      expect(f.formatEditUpdate(const TextEditingValue(), const TextEditingValue(text: '۱۲ab٣۴x')).text, '1234');
    });
    test('limits phone to 11 and postal/national codes to 10 digits', () {
      const phone = NumericInputFormatter(maxLength: 11);
      const ten = NumericInputFormatter(maxLength: 10);
      expect(phone.formatEditUpdate(const TextEditingValue(), const TextEditingValue(text: '۰۹۱۲۳۴۵۶۷۸۹۰')).text, '09123456789');
      expect(ten.formatEditUpdate(const TextEditingValue(), const TextEditingValue(text: '۱۲۳۴۵۶۷۸۹۰۱')).text, '1234567890');
    });
    test('permits a single decimal point only when configured', () {
      const f = NumericInputFormatter(allowDecimal: true);
      expect(f.formatEditUpdate(const TextEditingValue(), const TextEditingValue(text: '۱۲٫۵٫۶abc')).text, '12.56');
    });
  });
  group('Numeric field validation', () {
    test('requires 11 phone digits and accepts localized digits', () {
      expect(validateNumericField('شماره تماس', '۰۹۱۲۳۴۵۶۷۸۹'), isNull);
      expect(validateNumericField('شماره همراه', '٠٩١٢٣٤٥٦٧٨٩'), isNull);
      expect(validateNumericField('شماره تماس', '0912345678'), contains('۱۱ رقم'));
      expect(validateNumericField('شماره تماس', '0912abc6789'), contains('۱۱ رقم'));
    });
    test('requires 10 postal code digits', () {
      expect(validateNumericField('کد پستی', '۱۲۳۴۵۶۷۸۹۰'), isNull);
      expect(validateNumericField('کد پستی', '۱۲۳۴۵۶۷۸۹'), contains('۱۰ رقم'));
    });
    test('requires 10 national code digits', () {
      expect(validateNumericField('کد ملی', '۱۲۳۴۵۶۷۸۹۰'), isNull);
      expect(validateNumericField('کد ملی', '۱۲۳۴۵۶۷۸۹۰۱'), contains('۱۰ رقم'));
    });
    test('rejects text in numeric fields and normalizes digits for storage', () {
      expect(validateNumericField('مبلغ', '۱۲۳۴۵'), isNull);
      expect(validateNumericField('مبلغ', '۱۲۳الف'), contains('فقط عدد'));
      expect(normalizeNumericField('مبلغ', '۱۲۳۴۵'), '12345');
    });
  });
}
