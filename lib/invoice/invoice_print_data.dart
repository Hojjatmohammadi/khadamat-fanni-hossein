import 'dart:convert';

/// Immutable, presentation-ready values read from a sales invoice snapshot.
/// The model deliberately contains no database access so print formatting can
/// be tested independently from Flutter widgets and SQLite.
class InvoicePrintLine {
  final String description;
  final String unit;
  final String kind;
  final double quantity;
  final double unitPrice;
  final double lineTotal;

  const InvoicePrintLine({
    required this.description,
    required this.unit,
    required this.kind,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });

  String get quantityLabel {
    if (quantity == quantity.truncateToDouble()) {
      return quantity.toStringAsFixed(0);
    }
    return quantity.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  static InvoicePrintLine? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final description = (raw['description'] ?? '').toString().trim();
    if (description.isEmpty) return null;

    final quantity = InvoicePrintData.parseAmount(raw['quantity']);
    final lineTotal = InvoicePrintData.parseAmount(raw['line_total']);
    final explicitUnitPrice = InvoicePrintData.parseAmount(raw['unit_price']);
    if (quantity <= 0 || lineTotal < 0) return null;

    return InvoicePrintLine(
      description: description,
      unit: (raw['unit'] ?? 'عدد').toString().trim(),
      kind: (raw['kind'] ?? 'service').toString(),
      quantity: quantity,
      unitPrice: explicitUnitPrice > 0
          ? explicitUnitPrice
          : lineTotal / quantity,
      lineTotal: lineTotal,
    );
  }
}

class InvoicePrintData {
  final String invoiceNumber;
  final String invoiceDate;
  final String issuedAt;
  final String deliveryDate;
  final String customerName;
  final String customerPhone;
  final String customerAddress;
  final String currency;
  final String paymentMethod;
  final String chequeNumber;
  final String chequeBank;
  final String chequeDueDate;
  final List<InvoicePrintLine> lines;
  final double gross;
  final double discount;
  final double tax;
  final double total;
  final double depositApplied;
  final double received;

  const InvoicePrintData({
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.issuedAt,
    required this.deliveryDate,
    required this.customerName,
    required this.customerPhone,
    required this.customerAddress,
    required this.currency,
    required this.paymentMethod,
    required this.chequeNumber,
    required this.chequeBank,
    required this.chequeDueDate,
    required this.lines,
    required this.gross,
    required this.discount,
    required this.tax,
    required this.total,
    required this.depositApplied,
    required this.received,
  });

  double get remaining => total - received - depositApplied;
  double get payableBalance => remaining > 0 ? remaining : 0;
  double get customerCredit => remaining < 0 ? -remaining : 0;

  factory InvoicePrintData.fromSnapshot(
    Map<String, String> snapshot, {
    int fallbackIndex = 0,
  }) {
    final gross = parseAmount(snapshot['مبلغ کل']);
    final discount = parseAmount(snapshot['تخفیف']);
    final tax = parseAmount(snapshot['مبلغ مالیات']);
    final deposit = parseAmount(snapshot['بیعانه تخصیص‌یافته']);
    final received = parseAmount(snapshot['مبلغ دریافتی']);

    final lines = <InvoicePrintLine>[];
    final encodedLines = (snapshot['ردیف‌های فاکتور'] ?? '').trim();
    if (encodedLines.isNotEmpty) {
      try {
        final decoded = jsonDecode(encodedLines);
        if (decoded is List) {
          for (final raw in decoded) {
            final line = InvoicePrintLine.tryParse(raw);
            if (line != null) lines.add(line);
          }
        }
      } on FormatException {
        // Older or damaged snapshots fall back to their original summary row.
      }
    }

    if (lines.isEmpty && (gross > 0 || (snapshot['شرح کالا/خدمت'] ?? '').trim().isNotEmpty)) {
      final quantity = parseAmount(snapshot['تعداد']);
      final safeQuantity = quantity > 0 ? quantity : 1.0;
      lines.add(InvoicePrintLine(
        description: (snapshot['شرح کالا/خدمت'] ?? 'کالا یا خدمت').trim(),
        unit: (snapshot['واحد شمارش'] ?? 'عدد').trim(),
        kind: (snapshot['شناسه کالای انبار'] ?? '').trim().isEmpty
            ? 'service'
            : 'product',
        quantity: safeQuantity,
        unitPrice: gross / safeQuantity,
        lineTotal: gross,
      ));
    }

    return InvoicePrintData(
      invoiceNumber: (snapshot['شماره فاکتور'] ?? 'شماره ${fallbackIndex + 1}').trim(),
      invoiceDate: (snapshot['تاریخ'] ?? '').trim(),
      issuedAt: (snapshot['تاریخ و ساعت صدور'] ?? '').trim(),
      deliveryDate: (snapshot['تاریخ تحویل / اتمام تعمیر'] ?? '').trim(),
      customerName: (snapshot['نام مشتری در زمان صدور'] ??
              snapshot['نام مشتری'] ??
              '—')
          .trim(),
      customerPhone: (snapshot['شماره تماس مشتری در زمان صدور'] ?? '').trim(),
      customerAddress: (snapshot['نشانی مشتری در زمان صدور'] ?? '').trim(),
      currency: (snapshot['واحد پول در زمان صدور'] ?? 'تومان').trim(),
      paymentMethod: (snapshot['روش پرداخت'] ?? 'ثبت نشده').trim(),
      chequeNumber: (snapshot['شماره چک'] ?? '').trim(),
      chequeBank: (snapshot['بانک چک'] ?? '').trim(),
      chequeDueDate: (snapshot['سررسید چک'] ?? '').trim(),
      lines: List<InvoicePrintLine>.unmodifiable(lines),
      gross: gross,
      discount: discount,
      tax: tax,
      total: (gross - discount + tax).clamp(0, double.infinity).toDouble(),
      depositApplied: deposit,
      received: received,
    );
  }

  static double parseAmount(Object? raw) {
    var value = (raw ?? '').toString().trim();
    if (value.isEmpty) return 0;
    const persianDigits = '۰۱۲۳۴۵۶۷۸۹';
    const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
    final normalized = StringBuffer();
    for (final rune in value.runes) {
      final character = String.fromCharCode(rune);
      final persianIndex = persianDigits.indexOf(character);
      final arabicIndex = arabicDigits.indexOf(character);
      if (persianIndex >= 0) {
        normalized.write(persianIndex);
      } else if (arabicIndex >= 0) {
        normalized.write(arabicIndex);
      } else {
        normalized.write(character);
      }
    }
    value = normalized
        .toString()
        .replaceAll(',', '')
        .replaceAll('٬', '')
        .replaceAll('،', '')
        .replaceAll(' ', '')
        .replaceAll('٫', '.');
    return double.tryParse(value) ?? 0;
  }
}
