import 'package:flutter_test/flutter_test.dart';
import 'package:khadamat_fanni_hosein/invoice/invoice_pdf_image_paginator.dart';

void main() {
  group('InvoicePdfImagePaginator.plan', () {
    test('keeps a short invoice on one page', () {
      final plan = InvoicePdfImagePaginator.plan(
        sourceWidth: 560,
        sourceHeight: 500,
        pageWidth: 595,
        pageHeight: 842,
        margin: 20,
      );

      expect(plan.slices, hasLength(1));
      expect(plan.slices.single.sourceTop, 0);
      expect(plan.slices.single.cropHeight, 500);
      expect(plan.slices.single.reservedHeaderHeight, 0);
    });

    test('splits tall invoices into balanced A4 page slices', () {
      const sourceHeight = 4000;
      final plan = InvoicePdfImagePaginator.plan(
        sourceWidth: 560,
        sourceHeight: sourceHeight,
        pageWidth: 595,
        pageHeight: 842,
        margin: 20,
      );

      expect(plan.slices.length, greaterThan(1));
      expect(plan.pageImageHeight, greaterThan(500));
      expect(plan.continuationHeaderHeight, greaterThan(0));
      expect(plan.slices.first.reservedHeaderHeight, 0);
      expect(
        plan.slices.skip(1).every(
          (slice) => slice.reservedHeaderHeight ==
              plan.continuationHeaderHeight,
        ),
        isTrue,
      );

      var expectedTop = 0;
      final cropHeights = <int>[];
      for (final slice in plan.slices) {
        expect(slice.sourceTop, expectedTop);
        expect(slice.cropHeight, greaterThan(0));
        expect(
          slice.cropHeight + slice.reservedHeaderHeight,
          lessThanOrEqualTo(plan.pageImageHeight),
        );
        expectedTop += slice.cropHeight;
        cropHeights.add(slice.cropHeight);
      }

      expect(expectedTop, sourceHeight);
      expect(cropHeights.reduce((a, b) => a > b ? a : b) -
          cropHeights.reduce((a, b) => a < b ? a : b), lessThanOrEqualTo(1));
    });

    test('rejects invalid image and page geometry', () {
      expect(
        () => InvoicePdfImagePaginator.plan(
          sourceWidth: 0,
          sourceHeight: 500,
          pageWidth: 595,
          pageHeight: 842,
        ),
        throwsArgumentError,
      );
      expect(
        () => InvoicePdfImagePaginator.plan(
          sourceWidth: 560,
          sourceHeight: 500,
          pageWidth: 30,
          pageHeight: 842,
          margin: 20,
        ),
        throwsArgumentError,
      );
      expect(
        () => InvoicePdfImagePaginator.plan(
          sourceWidth: 560,
          sourceHeight: 500,
          pageWidth: double.infinity,
          pageHeight: 842,
        ),
        throwsArgumentError,
      );
    });

    test('never drops the last pixels on a very tall invoice', () {
      for (final sourceHeight in [810, 811, 1540, 1541, 4097, 10001]) {
        final plan = InvoicePdfImagePaginator.plan(
          sourceWidth: 560,
          sourceHeight: sourceHeight,
          pageWidth: 595,
          pageHeight: 842,
          margin: 20,
        );
        final total = plan.slices.fold<int>(
          0,
          (sum, slice) => sum + slice.cropHeight,
        );
        expect(total, sourceHeight);
        expect(plan.slices.last.cropHeight, greaterThan(0));
      }
    });
  });
}
