import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Builds a PDF from the immutable invoice snapshot.
/// Persian text is rasterized by Flutter's text engine first, preserving RTL
/// shaping even when the device has no PDF-embedded Persian font.
class InvoicePdfService {
  static const double _width = 1240;
  static const double _height = 1754;
  static const double _margin = 68;

  Future<Uint8List> build(Map<String, dynamic> snapshot) async {
    if (snapshot.isEmpty) {
      throw ArgumentError('اطلاعات فاکتور برای ساخت PDF خالی است');
    }

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final background = ui.Paint()..color = const ui.Color(0xFFFFFFFF);
    canvas.drawRect(const ui.Rect.fromLTWH(0, 0, _width, _height), background);

    var y = 64.0;
    final right = _width - _margin;
    final textColor = const ui.Color(0xFF202124);
    final muted = const ui.Color(0xFF5F6368);
    final borderPaint = ui.Paint()
      ..color = const ui.Color(0xFFB8BEC5)
      ..strokeWidth = 2;

    double drawText(
      String value, {
      double fontSize = 30,
      bool bold = false,
      ui.Color color = textColor,
      double top = 0,
      double maxWidth = _width - 2 * _margin,
    }) {
      final painter = ui.TextPainter(
        text: ui.TextSpan(
          text: value,
          style: ui.TextStyle(
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

    Future<void> drawEncodedImage(String? encoded, double x, double top,
        double width, double height) async {
      if (encoded == null || encoded.isEmpty) return;
      try {
        final codec = await ui.instantiateImageCodec(base64Decode(encoded));
        final frame = await codec.getNextFrame();
        final image = frame.image;
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
        image.dispose();
        codec.dispose();
      } catch (_) {
        // A corrupt optional stamp/signature must not prevent invoice export.
      }
    }

    final shopName = snapshot['shopName']?.toString() ?? 'فاکتور فروش';
    final headerHeight = drawText(
      shopName,
      fontSize: 48,
      bold: true,
      top: y,
    );
    y += headerHeight + 12;
    y += drawText(
      'مسئول: ${snapshot['ownerName'] ?? ''}    تلفن: ${snapshot['phone'] ?? ''}',
      fontSize: 24,
      top: y,
      color: muted,
    ) + 8;
    y += drawText(
      'کد پستی: ${snapshot['postalCode'] ?? ''}',
      fontSize: 22,
      top: y,
      color: muted,
    ) + 6;
    y += drawText(
      'نشانی: ${snapshot['address'] ?? ''}',
      fontSize: 22,
      top: y,
      color: muted,
    ) + 18;

    canvas.drawLine(ui.Offset(_margin, y), ui.Offset(right, y), borderPaint);
    y += 20;
    y += drawText(
      'فاکتور فروش شماره: ${snapshot['documentNumber'] ?? ''}',
      fontSize: 34,
      bold: true,
      top: y,
    ) + 8;
    y += drawText(
      'تاریخ: ${snapshot['documentDate'] ?? ''}    مشتری: ${snapshot['counterpartyName'] ?? ''}',
      fontSize: 25,
      top: y,
    ) + 22;

    canvas.drawLine(ui.Offset(_margin, y), ui.Offset(right, y), borderPaint);
    y += 18;
    final items = (snapshot['items'] as List? ?? const [])
        .whereType<Map>()
        .toList(growable: false);
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final name = item['productName']?.toString() ?? 'کالا';
      final qty = item['quantity']?.toString() ?? '0';
      final price = item['unitPrice']?.toString() ?? '0';
      final total = item['lineTotal']?.toString() ?? '0';
      final line = '${i + 1}. $name   |   تعداد: $qty   |   فی: $price تومان   |   جمع: $total تومان';
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
      if (y > _height - 370) break;
    }

    y += 12;
    canvas.drawLine(ui.Offset(_margin, y), ui.Offset(right, y), borderPaint);
    y += 20;
    for (final entry in [
      ('جمع کالاها', snapshot['subtotal']),
      ('تخفیف', snapshot['discountAmount']),
      ('هزینه‌ها', snapshot['chargesAmount']),
      ('ارزش افزوده', snapshot['vatAmount']),
      ('مبلغ نهایی', snapshot['totalAmount']),
      ('پرداخت‌شده', snapshot['paidAmount']),
      ('مانده', snapshot['outstandingAmount']),
    ]) {
      final h = drawText(
        '${entry.$1}: ${entry.$2 ?? 0} تومان',
        fontSize: entry.$1 == 'مبلغ نهایی' ? 31 : 25,
        bold: entry.$1 == 'مبلغ نهایی',
        top: y,
      );
      y += h + 8;
    }

    final imageTop = _height - 250;
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
    drawText('مهر فروشگاه', fontSize: 18, color: muted, top: imageTop + 125, maxWidth: 260);
    drawText('امضای مسئول', fontSize: 18, color: muted, top: imageTop + 125, maxWidth: 220);

    final picture = recorder.endRecording();
    final raster = await picture.toImage(_width.toInt(), _height.toInt());
    final png = await raster.toByteData(format: ui.ImageByteFormat.png);
    raster.dispose();
    picture.dispose();
    if (png == null) throw StateError('ساخت تصویر فاکتور ناموفق بود');

    final document = pw.Document();
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(
          pw.MemoryImage(png.buffer.asUint8List()),
          fit: pw.BoxFit.fill,
        ),
      ),
    );
    return document.save();
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
