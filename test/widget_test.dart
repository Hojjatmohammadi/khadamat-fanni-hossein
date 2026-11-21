import 'dart:async';
import 'dart:ui' as ui;

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter_test/flutter_test.dart';
import 'package:khadamat_fanni_hosein/main.dart';

void main() {
  testWidgets('startup failure shows an actionable recovery screen', (tester) async {
    await tester.pumpWidget(
      const StartupFailureApp(error: 'database initialization failed'),
    );

    expect(find.text('راه‌اندازی برنامه کامل نشد'), findsOneWidget);
    expect(find.text('database initialization failed'), findsOneWidget);
    expect(find.text('تلاش مجدد'), findsOneWidget);
  });

  testWidgets('Persian date formatter works inside a Flutter text field',
      (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextField(
            controller: controller,
            inputFormatters: [PersianDateInputFormatter()],
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '14050823');
    await tester.pump();

    expect(controller.text, '۱۴۰۵/۰۸/۲۳');
    controller.dispose();
  });

  test('Iranian mobile numbers normalize Persian and Arabic digits and country prefixes', () {
    expect(normalizeIranianMobileNumber('۰۹۱۲ ۳۴۵ ۶۷۸۹'), '09123456789');
    expect(normalizeIranianMobileNumber('٠٩١٢-٣٤٥-٦٧٨٩'), '09123456789');
    expect(normalizeIranianMobileNumber('+98 912 345 6789'), '09123456789');
    expect(normalizeIranianMobileNumber('0098 912 345 6789'), '09123456789');
    expect(normalizeIranianMobileNumber('9123456789'), '09123456789');
    expect(normalizeIranianMobileNumber('123'), '123');
  });

  testWidgets('report boundary capture creates a decodable PNG image', (tester) async {
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: const SizedBox(
                width: 96,
                height: 48,
                child: ColoredBox(color: Colors.blue),
              ),
            ),
          ),
        ),
      ),
    );

    final capture = captureBoundaryPng(boundaryKey, pixelRatio: 1);
    await tester.pump();
    final bytes = await tester.runAsync(
      () => capture.timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw TimeoutException('PNG report capture exceeded 20 seconds.'),
      ),
    );
    expect(bytes, isNotNull);
    expect(
      bytes!.take(8).toList(),
      [137, 80, 78, 71, 13, 10, 26, 10],
    );

    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 96);
      expect(frame.image.height, 48);
      frame.image.dispose();
    } finally {
      codec.dispose();
    }
  });

  test('PDF package produces a readable PDF document', () async {
    final document = pw.Document();
    document.addPage(
      pw.Page(
        build: (_) => pw.Center(child: pw.Text('Report export smoke test')),
      ),
    );
    final bytes = await document.save();
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('Excel package produces a readable XLSX workbook', () {
    final workbook = Excel.createExcel();
    workbook['Sheet1'].appendRow([
      TextCellValue('Report'),
      TextCellValue('Value'),
    ]);
    final bytes = workbook.encode();
    expect(bytes, isNotNull);
    final encoded = bytes!;
    expect(encoded.take(4).toList(), [0x50, 0x4B, 0x03, 0x04]);
    final reopened = Excel.decodeBytes(encoded);
    expect(reopened.tables['Sheet1']?.rows, isNotEmpty);
  });

}
