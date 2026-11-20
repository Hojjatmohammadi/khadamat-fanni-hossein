import 'package:flutter_test/flutter_test.dart';
import 'package:khadamat_fanni_hosein/jalali_date_field.dart';

void main() {
  group('Solar Hijri date formatting and parsing', () {
    test('formats Gregorian dates as Persian yyyy/mm/dd', () {
      expect(formatJalaliDate(DateTime(2026, 11, 17)), '۱۴۰۵/۰۸/۲۶');
    });

    test('parses Persian and Arabic numerals into Gregorian dates', () {
      expect(parseJalaliDate('۱۴۰۵/۰۸/۲۶'), DateTime(2026, 11, 17));
      expect(parseJalaliDate('١٤٠٥/٠٨/٢٦'), DateTime(2026, 11, 17));
    });

    test('requires four-digit year and two-digit month and day separated by slashes', () {
      expect(parseJalaliDate('1405/8/26'), isNull);
      expect(parseJalaliDate('1405-08-26'), isNull);
      expect(parseJalaliDate('1405/08/2'), isNull);
    });

    test('rejects invalid month and day values', () {
      expect(parseJalaliDate('1405/13/01'), isNull);
      expect(parseJalaliDate('1405/08/32'), isNull);
    });
  });
}
