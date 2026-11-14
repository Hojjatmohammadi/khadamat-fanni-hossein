import 'package:flutter_test/flutter_test.dart';
import 'package:khadamat_fanni_hosein/localized_number.dart';
import 'package:khadamat_fanni_hosein/product_duplicate_checker.dart';

void main() {
  group('LocalizedNumber', () {
    test('parses Persian digits and separators', () {
      expect(LocalizedNumber.parseIntOrZero('۱۲۳٬۴۵۶'), 123456);
      expect(LocalizedNumber.parseDoubleOrZero('۱۲۳٫۵'), 123.5);
    });

    test('parses Arabic-Indic digits and separators', () {
      expect(LocalizedNumber.parseIntOrZero('١٢٣,٤٥٦'), 123456);
      expect(LocalizedNumber.parseDoubleOrZero('١٢٫٧٥'), 12.75);
    });

    test('returns null for invalid values and zero from safe parsers', () {
      expect(LocalizedNumber.tryParseDouble('نامعتبر'), isNull);
      expect(LocalizedNumber.parseDoubleOrZero('نامعتبر'), 0);
    });
  });

  group('ProductDuplicateChecker', () {
    final existing = <Map<String, String>>[
      {
        'نام کالا': 'خازن ۱۰۰ میکرو',
        'گروه اصلی': 'الکترونیک',
        'زیرگروه': 'خازن‌ها',
        'کد کالا': 'CAP-100',
        'موجودی': '5',
      },
    ];

    test('recognizes Persian and Arabic numeral variants in names', () {
      final candidate = {
        'نام کالا': 'خازن ١٠٠ میکرو',
        'گروه اصلی': 'الکترونیک',
        'زیرگروه': 'خازن‌ها',
        'کد کالا': '',
      };
      expect(
        ProductDuplicateChecker.findDuplicates(existing, candidate),
        hasLength(1),
      );
    });

    test('does not flag same name and group when both item codes differ', () {
      final candidate = {
        'نام کالا': 'خازن ۱۰۰ میکرو',
        'گروه اصلی': 'الکترونیک',
        'زیرگروه': 'خازن‌ها',
        'کد کالا': 'CAP-100V',
      };
      expect(
        ProductDuplicateChecker.findDuplicates(existing, candidate),
        isEmpty,
      );
    });

    test('matches equal non-empty item codes even if names differ', () {
      final candidate = {
        'نام کالا': 'خازن مدل دیگر',
        'گروه اصلی': 'قطعات',
        'زیرگروه': 'متفرقه',
        'کد کالا': 'CAP-100',
      };
      expect(
        ProductDuplicateChecker.findDuplicates(existing, candidate),
        hasLength(1),
      );
    });
  });
}
