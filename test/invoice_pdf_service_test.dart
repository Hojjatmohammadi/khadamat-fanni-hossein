import 'dart:convert';
import 'dart:ui' as ui;

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

  test('long invoices keep every item in the PNG and span multiple PDF pages', () async {
    final snapshot = <String, dynamic>{
      'shopName': 'خدمات فنی حسین',
      'documentNumber': 'SAL-LONG-0040',
      'documentDate': '1405/09/01',
      'counterpartyName': 'مشتری فاکتور بلند',
      'subtotal': 400000,
      'discountAmount': 0,
      'chargesAmount': 0,
      'vatAmount': 0,
      'totalAmount': 400000,
      'paidAmount': 0,
      'outstandingAmount': 400000,
      'items': List.generate(
        40,
        (index) => {
          'productName': 'قطعه شماره ${index + 1}',
          'quantity': 1,
          'unitPrice': 10000,
          'lineTotal': 10000,
        },
      ),
    };

    final service = InvoicePdfService();
    final imageBytes = await service.buildImage(snapshot);
    final imageCodec = await ui.instantiateImageCodec(imageBytes);
    final imageFrame = await imageCodec.getNextFrame();
    expect(imageFrame.image.width, 1240);
    expect(
      imageFrame.image.height,
      greaterThan(1754),
      reason: 'Long invoice images must grow instead of silently dropping product rows',
    );
    imageFrame.image.dispose();
    imageCodec.dispose();

    final pdfBytes = await service.build(snapshot);
    expect(utf8.decode(pdfBytes.take(4).toList()), '%PDF');
    final pdfSource = String.fromCharCodes(pdfBytes);
    final pageCount = RegExp(r'/Type\s*/Page\b').allMatches(pdfSource).length;
    expect(
      pageCount,
      greaterThan(1),
      reason: 'Long invoice PDFs must be split into multiple A4 pages',
    );
  });

  test('rejects an empty snapshot', () async {
    expect(
      () => InvoicePdfService().build({}),
      throwsArgumentError,
    );
  });
}
