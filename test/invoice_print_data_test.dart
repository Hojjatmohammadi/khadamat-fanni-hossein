import 'package:flutter_test/flutter_test.dart';
import 'package:khadamat_fanni_hosein/invoice/invoice_print_data.dart';

void main() {
  test('parses itemized invoice rows and localized Persian amounts', () {
    final invoice = InvoicePrintData.fromSnapshot({
      'شماره فاکتور': 'HOS-00042',
      'مبلغ کل': '۸۰۰٬۰۰۰',
      'تخفیف': '۵۰٬۰۰۰',
      'مبلغ مالیات': '۰',
      'مبلغ دریافتی': '۳۰۰۰۰۰',
      'بیعانه تخصیص‌یافته': '۱۰۰۰۰۰',
      'ردیف‌های فاکتور': '''
        [
          {"kind":"product","description":"قطعه پمپ","unit":"عدد","quantity":"2","unit_price":"200000","line_total":"400000"},
          {"kind":"service","description":"اجرت تعمیر","unit":"خدمت","quantity":"1","unit_price":"400000","line_total":"400000"}
        ]
      ''',
    });

    expect(invoice.invoiceNumber, 'HOS-00042');
    expect(invoice.lines, hasLength(2));
    expect(invoice.lines.first.description, 'قطعه پمپ');
    expect(invoice.lines.first.quantityLabel, '2');
    expect(invoice.lines.last.kind, 'service');
    expect(invoice.gross, 800000);
    expect(invoice.discount, 50000);
    expect(invoice.total, 750000);
    expect(invoice.payableBalance, 350000);
    expect(invoice.customerCredit, 0);
  });

  test('uses a legacy summary row when archived item details are absent', () {
    final invoice = InvoicePrintData.fromSnapshot({
      'شماره فاکتور': 'HOS-00010',
      'شرح کالا/خدمت': 'تعمیر اتو',
      'تعداد': '۲',
      'مبلغ کل': '۶۰۰۰۰۰',
      'مبلغ دریافتی': '۶۰۰۰۰۰',
    });

    expect(invoice.lines, hasLength(1));
    expect(invoice.lines.single.description, 'تعمیر اتو');
    expect(invoice.lines.single.quantity, 2);
    expect(invoice.lines.single.unitPrice, 300000);
    expect(invoice.payableBalance, 0);
  });

  test('shows customer credit instead of a negative payable balance', () {
    final invoice = InvoicePrintData.fromSnapshot({
      'مبلغ کل': '100000',
      'مبلغ دریافتی': '120000',
      'بیعانه تخصیص‌یافته': '0',
    });

    expect(invoice.payableBalance, 0);
    expect(invoice.customerCredit, 20000);
  });

  test('retains customer, issue, delivery and cheque details from the snapshot', () {
    final invoice = InvoicePrintData.fromSnapshot({
      'نام مشتری': 'مشتری قدیمی',
      'نام مشتری در زمان صدور': 'احمد رضایی',
      'شماره تماس مشتری در زمان صدور': '09120000000',
      'نشانی مشتری در زمان صدور': 'خیابان نمونه',
      'تاریخ و ساعت صدور': '2026-11-27T10:15:00.000',
      'تاریخ تحویل / اتمام تعمیر': '۱۴۰۵/۰۹/۰۷',
      'روش پرداخت': 'چک',
      'شماره چک': '123456',
      'بانک چک': 'بانک نمونه',
      'سررسید چک': '۱۴۰۵/۱۰/۰۷',
    });

    expect(invoice.customerName, 'احمد رضایی');
    expect(invoice.customerPhone, '09120000000');
    expect(invoice.customerAddress, 'خیابان نمونه');
    expect(invoice.issuedAt, '2026-11-27T10:15:00.000');
    expect(invoice.deliveryDate, '۱۴۰۵/۰۹/۰۷');
    expect(invoice.paymentMethod, 'چک');
    expect(invoice.chequeNumber, '123456');
    expect(invoice.chequeBank, 'بانک نمونه');
    expect(invoice.chequeDueDate, '۱۴۰۵/۱۰/۰۷');
  });

  test('rejects malformed item json and still provides a safe summary', () {
    final invoice = InvoicePrintData.fromSnapshot({
      'ردیف‌های فاکتور': '{broken',
      'شرح کالا/خدمت': 'خدمت تعمیر',
      'مبلغ کل': '250000',
    });

    expect(invoice.lines, hasLength(1));
    expect(invoice.lines.single.description, 'خدمت تعمیر');
  });

  test('identifies a correction document and preserves its original reference', () {
    final invoice = InvoicePrintData.fromSnapshot({
      'نوع سند': 'فاکتور اصلاحی',
      'شماره فاکتور': 'COR-00001',
      'شماره فاکتور مرجع': 'HOS-00017',
      'علت اصلاح': 'اصلاح نشانی مشتری',
      'مبلغ کل': '800000',
    });

    expect(invoice.documentType, 'فاکتور اصلاحی');
    expect(invoice.invoiceNumber, 'COR-00001');
    expect(invoice.originalInvoiceNumber, 'HOS-00017');
    expect(invoice.correctionReason, 'اصلاح نشانی مشتری');
    expect(invoice.total, 800000);
  });
}
