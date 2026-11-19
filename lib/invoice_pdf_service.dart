import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' as painting;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class _RenderedInvoice {
  const _RenderedInvoice({
    required this.pngBytes,
    required this.height,
    required this.pageBreaks,
  });

  final Uint8List pngBytes;
  final int height;
  final List<int> pageBreaks;
}

/// Builds a PDF from the immutable invoice snapshot.
/// Persian text is rasterized by Flutter's text engine first, preserving RTL
/// shaping even when the device has no PDF-embedded Persian font.
class InvoicePdfService {
  static const double _width = 1240;
  static const double _height = 1754;
  static const double _margin = 68;

  double _measureTextHeight(
    String value, {
    double fontSize = 30,
    bool bold = false,
    double maxWidth = _width - 2 * _margin,
  }) {
    final painter = painting.TextPainter(
      text: painting.TextSpan(
        text: value,
        style: painting.TextStyle(
          fontSize: fontSize,
          fontWeight: bold ? ui.FontWeight.bold : ui.FontWeight.normal,
          height: 1.35,
        ),
      ),
      textDirection: ui.TextDirection.rtl,
      textAlign: ui.TextAlign.right,
    )..layout(maxWidth: maxWidth);
    return painter.height;
  }

  Future<_RenderedInvoice> _renderInvoice(
    Map<String, dynamic> snapshot,
  ) async {
    if (snapshot.isEmpty) {
      throw ArgumentError('اطلاعات فاکتور برای ساخت PDF خالی است');
    }

    final isPurchase = snapshot['documentType'] == 'purchase';
    final documentTitle = isPurchase ? 'فاکتور خرید' : 'فاکتور فروش';
    final partyLabel = isPurchase ? 'فروشنده' : 'مشتری';
    final currency = snapshot['currency'] == 'ریال' ? 'ریال' : 'تومان';
    final shopName = snapshot['shopName']?.toString() ?? documentTitle;
    final items = (snapshot['items'] as List? ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    final itemLines = items.indexed.map((entry) {
      final index = entry.$1;
      final item = entry.$2;
      final name = item['productName']?.toString() ?? 'کالا';
      final qty = item['quantity']?.toString() ?? '0';
      final price = item['unitPrice']?.toString() ?? '0';
      final total = item['lineTotal']?.toString() ?? '0';
      return '\${index + 1}. $name   |   تعداد: $qty   |   فی: $price $currency   |   جمع: $total $currency';
    }).toList(growable: false);
    final totals = <(String, Object?)>[
      ('جمع کالاها', snapshot['subtotal']),
      ('تخفیف', snapshot['discountAmount']),
      ('هزینه‌ها', snapshot['chargesAmount']),
      ('ارزش افزوده', snapshot['vatAmount']),
      ('مبلغ نهایی', snapshot['totalAmount']),
      ('پرداخت‌شده', snapshot['paidAmount']),
      ('مانده', snapshot['outstandingAmount']),
    ];

    // Measure the complete invoice before painting so no row is clipped when
    // the invoice contains more items than fit on a standard A4-height image.
    var measuredY = 64.0;
    measuredY += _measureTextHeight(
          shopName,
          fontSize: 48,
          bold: true,
          maxWidth: _width - 2 * _margin - 150,
        ) +
        12;
    measuredY += _measureTextHeight(
          'مسئول: \${snapshot['ownerName'] ?? ''}    تلفن: \${snapshot['phone'] ?? ''}',
          fontSize: 24,
        ) +
        8;
    measuredY += _measureTextHeight(
          'کد پستی: \${snapshot['postalCode'] ?? ''}',
          fontSize: 22,
        ) +
        6;
    measuredY += _measureTextHeight(
          'نشانی: \${snapshot['address'] ?? ''}',
          fontSize: 22,
        ) +
        18;
    measuredY += 2 + 20;
    measuredY += _measureTextHeight(
          '$documentTitle شماره: \${snapshot['documentNumber'] ?? ''}',
          fontSize: 34,
          bold: true,
        ) +
        8;
    measuredY += _measureTextHeight(
          'تاریخ: \${snapshot['documentDate'] ?? ''}    $partyLabel: \${snapshot['counterpartyName'] ?? ''}',
          fontSize: 25,
        ) +
        22;
    measuredY += 2 + 18;
    for (final line in itemLines) {
      measuredY += _measureTextHeight(line, fontSize: 23) + 24;
    }
    measuredY += 12 + 2 + 20;
    for (final entry in totals) {
      measuredY += _measureTextHeight(
            '\${entry.$1}: \${entry.$2 ?? 0} $currency',
            fontSize: entry.$1 == 'مبلغ نهایی' ? 31 : 25,
            bold: entry.$1 == 'مبلغ نهایی',
          ) +
          8;
    }

    var imageHeight = (measuredY + 310).ceil();
    if (imageHeight < _height.toInt()) imageHeight = _height.toInt();

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final background = ui.Paint()..color = const ui.Color(0xFFFFFFFF);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, _width, imageHeight.toDouble()),
      background,
    );

    var y = 64.0;
    final right = _width - _margin;
    final muted = const ui.Color(0xFF5F6368);
    final borderPaint = ui.Paint()
      ..color = const ui.Color(0xFFB8BEC5)
      ..strokeWidth = 2;

    double drawText(
      String value, {
      double fontSize = 30,
      bool bold = false,
      ui.Color color = const ui.Color(0xFF202124),
      double top = 0,
      double maxWidth = _width - 2 * _margin,
    }) {
      final painter = painting.TextPainter(
        text: painting.TextSpan(
          text: value,
          style: painting.TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: bold ? ui.FontWeight.bold : ui.FontWeight.normal,
            height: 1.35,
          ),
        ),
        textDirection: ui.TextDirection.rtl,
        textAlign: ui.TextAlign.right,
      )..layout(maxWidth: maxWidth);
      painter.paint(canvas, ui.Offset(right - maxWidth, top));
      return painter.height;
    }

    Future<void> drawEncodedImage(
      String? encoded,
      double x,
      double top,
      double width,
      double height,
    ) async {
      if (encoded == null || encoded.isEmpty) return;
      ui.Codec? codec;
      ui.Image? image;
      try {
        codec = await ui.instantiateImageCodec(base64Decode(encoded));
        final frame = await codec.getNextFrame();
        image = frame.image;
        final src = ui.Rect.fromLTWH(
          0,
          0,
          image.width.toDouble(),
          image.height.toDouble(),
        );
        final dst = ui.Rect.fromLTWH(x, top, width, height);
        canvas.drawImageRect(
          image,
          src,
          dst,
          ui.Paint()..filterQuality = ui.FilterQuality.high,
        );
      } catch (_) {
        // A corrupt optional logo/stamp/signature must not block invoice export.
      } finally {
        image?.dispose();
        codec?.dispose();
      }
    }

    final headerHeight = drawText(
      shopName,
      fontSize: 48,
      bold: true,
      top: y,
      maxWidth: _width - 2 * _margin - 150,
    );
    await drawEncodedImage(
      snapshot['appLogoBase64']?.toString(),
      _margin,
      y - 4,
      112,
      112,
    );
    y += headerHeight + 12;
    y += drawText(
      'مسئول: \${snapshot['ownerName'] ?? ''}    تلفن: \${snapshot['phone'] ?? ''}',
      fontSize: 24,
      top: y,
      color: muted,
    ) + 8;
    y += drawText(
      'کد پستی: \${snapshot['postalCode'] ?? ''}',
      fontSize: 22,
      top: y,
      color: muted,
    ) + 6;
    y += drawText(
      'نشانی: \${snapshot['address'] ?? ''}',
      fontSize: 22,
      top: y,
      color: muted,
    ) + 18;

    canvas.drawLine(ui.Offset(_margin, y), ui.Offset(right, y), borderPaint);
    y += 20;
    y += drawText(
      '$documentTitle شماره: \${snapshot['documentNumber'] ?? ''}',
      fontSize: 34,
      bold: true,
      top: y,
    ) + 8;
    y += drawText(
      'تاریخ: \${snapshot['documentDate'] ?? ''}    $partyLabel: \${snapshot['counterpartyName'] ?? ''}',
      fontSize: 25,
      top: y,
    ) + 22;

    canvas.drawLine(ui.Offset(_margin, y), ui.Offset(right, y), borderPaint);
    y += 18;

    // PDF pages are cut only between product rows. The PNG export remains a
    // single tall image, while the PDF keeps every item across A4 pages.
    final pageBreaks = <int>[];
    var pageStart = 0.0;
    for (final line in itemLines) {
      final estimatedRowHeight = _measureTextHeight(line, fontSize: 23) + 24;
      if (y + estimatedRowHeight > pageStart + _height && y > pageStart) {
        pageBreaks.add(y.round());
        pageStart = y;
      }

      final h = drawText(line, fontSize: 23, top: y);
      y += h + 14;
      canvas.drawLine(
        ui.Offset(_margin, y),
        ui.Offset(right, y),
        ui.Paint()
          ..color = const ui.Color(0xFFE0E3E7)
          ..strokeWidth = 1,
      );
      y += 10;
    }

    final totalsHeight = totals.fold<double>(
      0,
      (sum, entry) =>
          sum +
          _measureTextHeight(
            '\${entry.$1}: \${entry.$2 ?? 0} $currency',
            fontSize: entry.$1 == 'مبلغ نهایی' ? 31 : 25,
            bold: entry.$1 == 'مبلغ نهایی',
          ) +
          8,
    );
    if (y + totalsHeight + 300 > pageStart + _height && y > pageStart) {
      pageBreaks.add(y.round());
      pageStart = y;
    }

    y += 12;
    canvas.drawLine(ui.Offset(_margin, y), ui.Offset(right, y), borderPaint);
    y += 20;
    for (final entry in totals) {
      final h = drawText(
        '\${entry.$1}: \${entry.$2 ?? 0} $currency',
        fontSize: entry.$1 == 'مبلغ نهایی' ? 31 : 25,
        bold: entry.$1 == 'مبلغ نهایی',
        top: y,
      );
      y += h + 8;
    }

    final imageTop = imageHeight - 250.0;
    await drawEncodedImage(
      snapshot['stampImageBase64']?.toString(),
      _margin + 40,
      imageTop,
      180,
      120,
    );
    await drawEncodedImage(
      snapshot['signatureImageBase64']?.toString(),
      right - 220,
      imageTop,
      180,
      120,
    );
    drawText(
      'مهر فروشگاه',
      fontSize: 18,
      color: muted,
      top: imageTop + 125,
      maxWidth: 260,
    );
    drawText(
      'امضای مسئول',
      fontSize: 18,
      color: muted,
      top: imageTop + 125,
      maxWidth: 220,
    );

    final picture = recorder.endRecording();
    final raster = await picture.toImage(_width.toInt(), imageHeight);
    final png = await raster.toByteData(format: ui.ImageByteFormat.png);
    raster.dispose();
    picture.dispose();
    if (png == null) throw StateError('ساخت تصویر فاکتور ناموفق بود');

    return _RenderedInvoice(
      pngBytes: png.buffer.asUint8List(),
      height: imageHeight,
      pageBreaks: pageBreaks,
    );
  }

  Future<Uint8List> buildImage(Map<String, dynamic> snapshot) async =>
      (await _renderInvoice(snapshot)).pngBytes;

  Future<Uint8List> build(Map<String, dynamic> snapshot) async {
    final rendered = await _renderInvoice(snapshot);
    final codec = await ui.instantiateImageCodec(rendered.pngBytes);
    final frame = await codec.getNextFrame();
    final sourceImage = frame.image;
    final document = pw.Document();
    try {
      final boundaries = <int>[
        0,
        ...rendered.pageBreaks,
        rendered.height,
      ];
      for (var page = 0; page < boundaries.length - 1; page++) {
        final top = boundaries[page];
        final bottom = boundaries[page + 1];
        final pageHeight = bottom - top;
        if (pageHeight <= 0) continue;

        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        canvas.drawImageRect(
          sourceImage,
          ui.Rect.fromLTWH(
            0,
            top.toDouble(),
            _width,
            pageHeight.toDouble(),
          ),
          ui.Rect.fromLTWH(
            0,
            0,
            _width,
            pageHeight.toDouble(),
          ),
          ui.Paint()..filterQuality = ui.FilterQuality.high,
        );
        final picture = recorder.endRecording();
        final pageRaster = await picture.toImage(
          _width.toInt(),
          pageHeight,
        );
        final pagePng = await pageRaster.toByteData(
          format: ui.ImageByteFormat.png,
        );
        pageRaster.dispose();
        picture.dispose();
        if (pagePng == null) {
          throw StateError('ساخت صفحهٔ فاکتور ناموفق بود');
        }

        document.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: pw.EdgeInsets.zero,
            build: (_) => pw.Align(
              alignment: pw.Alignment.topCenter,
              child: pw.Image(
                pw.MemoryImage(pagePng.buffer.asUint8List()),
                fit: pw.BoxFit.contain,
              ),
            ),
          ),
        );
      }
      return document.save();
    } finally {
      sourceImage.dispose();
      codec.dispose();
    }
  }

  Future<void> shareImage(Map<String, dynamic> snapshot) async {
    final bytes = await buildImage(snapshot);
    final directory = await getTemporaryDirectory();
    final number = (snapshot['documentNumber']?.toString() ?? 'invoice')
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final file = File('${directory.path}/invoice_$number.png');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'image/png')],
      text: '${snapshot['documentType'] == 'purchase' ? 'تصویر فاکتور خرید' : 'تصویر فاکتور فروش'} $number',
    );
  }

  Future<void> share(Map<String, dynamic> snapshot) async {
    final bytes = await build(snapshot);
    final number = (snapshot['documentNumber']?.toString() ?? 'invoice')
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'invoice_$number.pdf',
    );
  }
}
