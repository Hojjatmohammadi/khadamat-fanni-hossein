import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Keeps Persian invoice text crisp while splitting a tall rendered invoice
/// into page-sized PNGs for the PDF writer. It avoids shrinking a long invoice
/// into one unreadable A4 page.
class InvoicePdfImagePaginator {
  InvoicePdfImagePaginator._();

  static Future<List<Uint8List>> paginate(
    Uint8List pngBytes, {
    required double pageWidth,
    required double pageHeight,
    double margin = 20,
    required String continuationHeader,
  }) async {
    if (pngBytes.isEmpty ||
        pageWidth <= margin * 2 ||
        pageHeight <= margin * 2) {
      throw ArgumentError('ابعاد تصویر یا صفحه برای ساخت PDF معتبر نیست.');
    }

    final codec = await ui.instantiateImageCodec(pngBytes);
    try {
      final frame = await codec.getNextFrame();
      final sourceImage = frame.image;
      try {
        final sourceWidth = sourceImage.width;
        final sourceHeight = sourceImage.height;
        final contentWidth = pageWidth - margin * 2;
        final contentHeight = pageHeight - margin * 2;
        final pageSliceHeight =
            (sourceWidth * contentHeight / contentWidth).round();

        if (pageSliceHeight <= 0) {
          throw StateError('ارتفاع قابل استفاده صفحه برای فاکتور معتبر نیست.');
        }
        if (sourceHeight <= pageSliceHeight) return [pngBytes];

        final sideMarginPx =
            (margin * sourceWidth / contentWidth).round();
        final headerHeight = (sourceWidth * 0.065).round();
        final maxContentHeight = pageSliceHeight - headerHeight;
        if (headerHeight <= 0 || maxContentHeight <= 0) {
          throw StateError('فضای سربرگ ادامه فاکتور معتبر نیست.');
        }

        final pageCount =
            (sourceHeight + maxContentHeight - 1) ~/ maxContentHeight;
        final balancedContentHeight =
            (sourceHeight + pageCount - 1) ~/ pageCount;
        final output = <Uint8List>[];
        var sourceTop = 0;

        for (var pageIndex = 0; pageIndex < pageCount; pageIndex++) {
          final remaining = sourceHeight - sourceTop;
          final cropHeight = remaining < balancedContentHeight
              ? remaining
              : balancedContentHeight;
          final reservedHeader = pageIndex == 0 ? 0 : headerHeight;

          final recorder = ui.PictureRecorder();
          final canvas = ui.Canvas(recorder);
          final pageRect = ui.Rect.fromLTWH(
            0,
            0,
            sourceWidth.toDouble(),
            pageSliceHeight.toDouble(),
          );
          canvas.drawRect(
            pageRect,
            ui.Paint()..color = Colors.white,
          );

          if (pageIndex > 0 && continuationHeader.trim().isNotEmpty) {
            final textPainter = TextPainter(
              text: TextSpan(
                text: continuationHeader.trim(),
                style: TextStyle(
                  color: Colors.black,
                  fontSize: (sourceWidth * 0.018).clamp(18, 36).toDouble(),
                  fontWeight: FontWeight.bold,
                ),
              ),
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.right,
              maxLines: 1,
              ellipsis: '…',
            );
            textPainter.layout(
              maxWidth: (sourceWidth - sideMarginPx * 2).toDouble(),
            );
            textPainter.paint(
              canvas,
              ui.Offset(
                sideMarginPx.toDouble(),
                ((headerHeight - textPainter.height) / 2).clamp(0, double.infinity),
              ),
            );
            canvas.drawLine(
              ui.Offset(sideMarginPx.toDouble(), headerHeight.toDouble() - 4),
              ui.Offset(
                (sourceWidth - sideMarginPx).toDouble(),
                headerHeight.toDouble() - 4,
              ),
              ui.Paint()
                ..color = Colors.black54
                ..strokeWidth = 2,
            );
          }

          final sourceRect = ui.Rect.fromLTWH(
            0,
            sourceTop.toDouble(),
            sourceWidth.toDouble(),
            cropHeight.toDouble(),
          );
          final destinationRect = ui.Rect.fromLTWH(
            0,
            reservedHeader.toDouble(),
            sourceWidth.toDouble(),
            cropHeight.toDouble(),
          );
          canvas.drawImageRect(
            sourceImage,
            sourceRect,
            destinationRect,
            ui.Paint()..filterQuality = ui.FilterQuality.high,
          );

          final pagePicture = recorder.endRecording();
          final pageImage = await pagePicture.toImage(
            sourceWidth,
            pageSliceHeight,
          );
          try {
            final pageData = await pageImage.toByteData(
              format: ui.ImageByteFormat.png,
            );
            if (pageData == null) {
              throw StateError('تبدیل صفحه فاکتور به تصویر PNG ناموفق بود.');
            }
            output.add(pageData.buffer.asUint8List());
          } finally {
            pageImage.dispose();
          }

          sourceTop += cropHeight;
        }

        return output;
      } finally {
        sourceImage.dispose();
      }
    } finally {
      codec.dispose();
    }
  }
}
