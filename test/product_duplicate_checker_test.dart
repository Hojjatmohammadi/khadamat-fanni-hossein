import 'package:flutter_test/flutter_test.dart';
import 'package:khadamat_fanni_hosein/product_duplicate_checker.dart';

void main() {
  test('detects same item even when quantity and prices differ', () {
    final existing = [
      {'نام کالا': 'خازن 100 میکرو', 'گروه اصلی': 'الکترونیک', 'زیرگروه': 'خازن', 'کد کالا': 'C-10', 'موجودی': '5'},
    ];

    final duplicates = ProductDuplicateChecker.findDuplicates(existing, {
      'نام کالا': 'خازن 100 میکرو',
      'گروه اصلی': 'الکترونیک',
      'زیرگروه': 'خازن',
      'کد کالا': 'C-11',
      'موجودی': '20',
      'قیمت فروش': '50000',
    });

    expect(duplicates, hasLength(1));
  });

  test('detects duplicate by matching non-empty code', () {
    final duplicates = ProductDuplicateChecker.findDuplicates([
      {'نام کالا': 'قطعه قدیمی', 'کد کالا': 'AB۱۲۳'},
    ], {
      'نام کالا': 'قطعه جدید',
      'کد کالا': 'AB123',
    });

    expect(duplicates, hasLength(1));
  });

  test('normalizes Arabic and Persian character variants and whitespace', () {
    final duplicates = ProductDuplicateChecker.findDuplicates([
      {'نام کالا': 'آی سی   کاربردی', 'گروه اصلی': 'الکترونیک', 'زیرگروه': ''},
    ], {
      'نام کالا': 'آی سی كاربردی',
      'گروه اصلی': 'الکترونیک',
      'زیرگروه': '',
    });

    expect(duplicates, hasLength(1));
  });

  test('does not mark different subgroups as duplicates', () {
    final duplicates = ProductDuplicateChecker.findDuplicates([
      {'نام کالا': 'دیود', 'گروه اصلی': 'الکترونیک', 'زیرگروه': 'معمولی'},
    ], {
      'نام کالا': 'دیود',
      'گروه اصلی': 'الکترونیک',
      'زیرگروه': 'زنر',
    });

    expect(duplicates, isEmpty);
  });

  test('does not treat empty identifying fields as a duplicate', () {
    expect(ProductDuplicateChecker.findDuplicates([
      {'نام کالا': '', 'کد کالا': ''},
    ], {'نام کالا': '', 'کد کالا': ''}), isEmpty);
  });
}
