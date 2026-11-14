import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:khadamat_fanni_hosein/app_database.dart';
import 'package:khadamat_fanni_hosein/report_repository.dart';
import 'package:khadamat_fanni_hosein/trade_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late AppDatabase database;
  late TradeRepository trades;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('reports_test_');
    database = AppDatabase(databasePath: '${tempDir.path}/reports.db');
    trades = TradeRepository(database);
    await database.database;
  });

  tearDown(() async {
    await database.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('trade report filters by inclusive date range and document type', () async {
    final productId = await database.insert('products', {
      'نام کالا': 'قطعه گزارش',
      'موجودی': '10',
      'بهای تمام‌شده هر واحد': '100',
    });
    await trades.recordSale(TradeDocumentDraft(
      documentDate: '2026-11-10',
      counterpartyName: 'مشتری اول',
      idempotencyKey: 'report-sale-1',
      lines: [TradeLineDraft(productId: productId, quantity: 1, unitPrice: 500)],
    ));
    await trades.recordSale(TradeDocumentDraft(
      documentDate: '2026-11-12',
      counterpartyName: 'مشتری دوم',
      idempotencyKey: 'report-sale-2',
      lines: [TradeLineDraft(productId: productId, quantity: 1, unitPrice: 600)],
    ));

    final repository = ReportRepository(database);
    final rows = await repository.getTradeDocuments(
      from: DateTime(2026, 11, 11),
      to: DateTime(2026, 11, 12),
      type: 'sale',
    );
    expect(rows, hasLength(1));
    expect(rows.single['counterparty_name'], 'مشتری دوم');
    expect(rows.single['total_amount'], 600);
  });

  test('stock report returns ledger movements with product names', () async {
    final productId = await database.insert('products', {
      'نام کالا': 'خازن گزارش',
      'موجودی': '4',
      'بهای تمام‌شده هر واحد': '200',
    });
    final rows = await ReportRepository(database).getInventoryMovements(
      from: DateTime(2026, 11, 1),
      to: DateTime(2026, 11, 30),
    );
    expect(rows, isNotEmpty);
    expect(rows.any((row) => row['product_name'] == 'خازن گزارش'), isTrue);
    expect(rows.any((row) => row['product_id'] == productId), isTrue);
  });
}
