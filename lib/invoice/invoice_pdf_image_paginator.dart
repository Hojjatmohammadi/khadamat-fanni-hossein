import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class InvoicePdfPageSlice {
  final int sourceTop;
  final int cropHeight;
  final int reservedHeaderHeight;

  const InvoicePdfPageSlice({
    required this.sourceTop,
    required this.cropHeight,
    required this.reservedHeaderHeight,
  });
}

class InvoicePdfPagePlan {
  final int pageImageHeight;
  final int sideMarginPx;
  final int continuationHeaderHeight;
  final List<InvoicePdfPageSlice> slices;

  const InvoicePdfPagePlan({
    required this.pageImageHeight,
    required this.sideMarginPx,
    required this.continuationHeaderHeight,
    required this.slices,
  });
}

/// Keeps Persian invoice text crisp while splitting a tall rendered invoice
/// into page-sized PNGs for the PDF writer. Geometry planning is pure Dart so
/// all page-boundary rules can be tested without a graphics engine.
class InvoicePdfImagePaginator {
  InvoicePdfImagePaginator._();

  static InvoicePdfPagePlan plan({
    required int sourceWidth,
    required int sourceHeight,
    required double pageWidth,
    required double pageHeight,
    double margin = 20,
  }) {
    if (sourceWidth <= 0 ||
        sourceHeight <= 0 ||
        !pageWidth.isFinite ||
        !pageHeight.isFinite ||
        !margin.isFinite ||
        margin < 0 ||
        pageWidth <= margin * 2 ||
        pageHeight <= margin * 2) {
      throw ArgumentError('ابعاد تصویر یا صفحه برای ساخت PDF معتبر نیست.');
    }

    final contentWidth = pageWidth - margin * 2;
    final contentHeight = pageHeight - margin * 2;
    final pageImageHeight =
        (sourceWidth * contentHeight / contentWidth).round();
    if (pageImageHeight <= 0) {
      throw ArgumentError('ارتفاع قابل استفاده صفحه برای فاکتور معتبر نیست.');
    }

    final sideMarginPx = (margin * sourceWidth / contentWidth).round();
    if (sourceHeight <= pageImageHeight) {
      return InvoicePdfPagePlan(
        pageImageHeight: pageImageHeight,
        sideMarginPx: sideMarginPx,
        continuationHeaderHeight: 0,
        slices: [
          InvoicePdfPageSlice(
            sourceTop: 0,
            cropHeight: sourceHeight,
            reservedHeaderHeight: 0,
          ),
        ],
      );
    }

    final headerHeight = (sourceWidth * 0.065).round();
    final maxContentHeight = pageImageHeight - headerHeight;
    if (headerHeight <= 0 || maxContentHeight <= 0) {
      throw ArgumentError('فضای سربرگ ادامه فاکتور معتبر نیست.');
    }

    final pageCount = (sourceHeight + maxContentHeight - 1) ~/ maxContentHeight;
    final balancedContentHeight = (sourceHeight + pageCount - 1) ~/ pageCount;
    final slices = <InvoicePdfPageSlice>[];
    var sourceTop = 0;

    for (var pageIndex = 0; pageIndex < pageCount; pageIndex++) {
      final remaining = sourceHeight - sourceTop;
      final cropHeight = remaining < balancedContentHeight
          ? remaining
          : balancedContentHeight;
      if (cropHeight <= 0) {
        throw StateError('برش صفحه فاکتور خالی محاسبه شد.');
      }
      slices.add(InvoicePdfPageSlice(
        sourceTop: sourceTop,
        cropHeight: cropHeight,
        reservedHeaderHeight: pageIndex == 0 ? 0 : headerHeight,
      ));
      sourceTop += cropHeight;
    }

    if (sourceTop != sourceHeight) {
      throw StateError('تمام محتوای فاکتور بین صفحات PDF توزیع نشد.');
    }

    return InvoicePdfPagePlan(
      pageImageHeight: pageImageHeight,
      sideMarginPx: sideMarginPx,
      continuationHeaderHeight: headerHeight,
      slices: List<InvoicePdfPageSlice>.unmodifiable(slices),
    );
  }

  static Future<List<Uint8List>> paginate(
    Uint8List pngBytes, {
    required double pageWidth,
    required double pageHeight,
    double margin = 20,
    required String continuationHeader,
  }) async {
    if (pngBytes.isEmpty) {
      throw ArgumentError('تصویر فاکتور خالی است.');
    }

    final codec = await ui.instantiateImageCodec(pngBytes);
    try {
      final frame = await codec.getNextFrame();
      final sourceImage = frame.image;
      try {
        final sourceWidth = sourceImage.width;
        final sourceHeight = sourceImage.height;
        final pagePlan = plan(
          sourceWidth: sourceWidth,
          sourceHeight: sourceHeight,
          pageWidth: pageWidth,
          pageHeight: pageHeight,
          margin: margin,
        );
        if (pagePlan.slices.length == 1) return [pngBytes];

        final output = <Uint8List>[];
        for (var pageIndex = 0;
            pageIndex < pagePlan.slices.length;
            pageIndex++) {
          final slice = pagePlan.slices[pageIndex];
          final recorder = ui.PictureRecorder();
          final canvas = ui.Canvas(recorder);
          final pageRect = ui.Rect.fromLTWH(
            0,
            0,
            sourceWidth.toDouble(),
            pagePlan.pageImageHeight.toDouble(),
          );
          canvas.drawRect(
            pageRect,
            ui.Paint()..color = Colors.white,
          );

          if (slice.reservedHeaderHeight > 0 &&
              continuationHeader.trim().isNotEmpty) {
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
              maxWidth: (sourceWidth - pagePlan.sideMarginPx * 2).toDouble(),
            );
            textPainter.paint(
              canvas,
              ui.Offset(
                pagePlan.sideMarginPx.toDouble(),
                ((slice.reservedHeaderHeight - textPainter.height) / 2)
                    .clamp(0, double.infinity)
                    .toDouble(),
              ),
            );
            canvas.drawLine(
              ui.Offset(
                pagePlan.sideMarginPx.toDouble(),
                slice.reservedHeaderHeight.toDouble() - 4,
              ),
              ui.Offset(
                (sourceWidth - pagePlan.sideMarginPx).toDouble(),
                slice.reservedHeaderHeight.toDouble() - 4,
              ),
              ui.Paint()
                ..color = Colors.black54
                ..strokeWidth = 2,
            );
          }

          final sourceRect = ui.Rect.fromLTWH(
            0,
            slice.sourceTop.toDouble(),
            sourceWidth.toDouble(),
            slice.cropHeight.toDouble(),
          );
          final destinationRect = ui.Rect.fromLTWH(
            0,
            slice.reservedHeaderHeight.toDouble(),
            sourceWidth.toDouble(),
            slice.cropHeight.toDouble(),
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
            pagePlan.pageImageHeight,
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
            pagePicture.dispose();
          }
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
