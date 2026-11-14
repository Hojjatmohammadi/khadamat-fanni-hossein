import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:khadamat_fanni_hosein/invoice_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('builds a PDF from an immutable Persian invoice snapshot', () async {
    final service = InvoicePdfService();
    final bytes = await service.build({
      'shopName': 'خدمات فنی حسین',
      'ownerName': 'حجت محمدی',
      'phone': '09150000000',
      'postalCode': '1234567890',
      'address': 'عشق آباد',
      'documentNumber': 'SAL-1405-0001',
      'documentDate': '1405/08/24',
      'counterpartyName': 'مشتری آزمایشی',
      'subtotal': 120000,
      'discountAmount': 0,
      'chargesAmount': 0,
      'vatAmount': 0,
      'totalAmount': 120000,
      'paidAmount': 60000,
      'outstandingAmount': 60000,
      'items': [
        {
          'productName': 'خازن 100 میکرو',
          'quantity': 2,
          'unitPrice': 60000,
          'lineTotal': 120000,
        },
      ],
      'stampImageBase64': base64Encode([1, 2, 3]),
      'signatureImageBase64': '',
    });

    expect(bytes, isNotEmpty);
    expect(utf8.decode(bytes.take(4).toList()), '%PDF');
  });


  test('builds a PNG image from the same immutable invoice snapshot', () async {
    final bytes = await InvoicePdfService().buildImage({
      'shopName': 'خدمات فنی حسین',
      'documentNumber': 'SAL-1405-0002',
      'documentDate': '1405/08/25',
      'counterpartyName': 'مشتری تصویر',
      'items': [
        {'productName': 'قطعه آزمایشی', 'quantity': 1, 'unitPrice': 25000, 'lineTotal': 25000},
      ],
      'subtotal': 25000,
      'discountAmount': 0,
      'chargesAmount': 0,
      'vatAmount': 0,
      'totalAmount': 25000,
      'paidAmount': 25000,
      'outstandingAmount': 0,
    });

    expect(bytes, isNotEmpty);
    expect(bytes.take(8).toList(), [137, 80, 78, 71, 13, 10, 26, 10]);
  });

  test('rejects an empty snapshot', () async {
    expect(
      () => InvoicePdfService().build({}),
      throwsArgumentError,
    );
  });
}
