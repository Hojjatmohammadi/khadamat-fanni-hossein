import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khadamat_fanni_hosein/invoice/invoice_pdf_image_paginator.dart';

Future<Uint8List> _solidPng(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = Colors.white,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('PNG test image was not encoded.');
    return data.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

void main() {
  testWidgets('keeps short invoice images on one page', (tester) async {
    final source = await _solidPng(560, 500);
    final pages = await InvoicePdfImagePaginator.paginate(
      source,
      pageWidth: 595,
      pageHeight: 842,
      margin: 20,
      continuationHeader: 'ادامه فاکتور HOS-00001',
    );

    expect(pages, hasLength(1));
    expect(pages.single, same(source));
  });

  testWidgets('splits tall invoice images into A4-sized pages', (tester) async {
    final source = await _solidPng(560, 4000);
    final pages = await InvoicePdfImagePaginator.paginate(
      source,
      pageWidth: 595,
      pageHeight: 842,
      margin: 20,
      continuationHeader: 'ادامه فاکتور HOS-00001',
    );

    expect(pages.length, greaterThan(1));
    for (final page in pages) {
      final codec = await ui.instantiateImageCodec(page);
      try {
        final frame = await codec.getNextFrame();
        expect(frame.image.width, 560);
        expect(frame.image.height, greaterThan(500));
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
    }
  });

  testWidgets('rejects empty images and invalid page dimensions', (tester) async {
    await expectLater(
      InvoicePdfImagePaginator.paginate(
        Uint8List(0),
        pageWidth: 595,
        pageHeight: 842,
        continuationHeader: 'ادامه فاکتور',
      ),
      throwsArgumentError,
    );

    final source = await _solidPng(560, 500);
    await expectLater(
      InvoicePdfImagePaginator.paginate(
        source,
        pageWidth: 30,
        pageHeight: 842,
        margin: 20,
        continuationHeader: 'ادامه فاکتور',
      ),
      throwsArgumentError,
    );
  });
}
