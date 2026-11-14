import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'accounting_repository.dart';
import 'app_database.dart';

class TradeLineDraft {
  const TradeLineDraft({
    required this.productId,
    required this.quantity,
    required this.unitPrice,
  });

  final int productId;
  final double quantity;
  final int unitPrice;

  Map<String, Object?> toJson() => {
        'productId': productId,
        'quantity': quantity,
        'unitPrice': unitPrice,
      };
}

class TradeDocumentDraft {
  const TradeDocumentDraft({
    required this.documentDate,
    required this.counterpartyName,
    required this.idempotencyKey,
    required this.lines,
    this.counterpartyId,
    this.discountAmount = 0,
    this.shippingCost = 0,
    this.freightCost = 0,
    this.otherCost = 0,
    this.vatRate = 0,
    this.vatExempt = false,
    this.paidAmount = 0,
    this.cashAccountCode = '1000',
  });

  final String documentDate;
  final String counterpartyName;
  final String idempotencyKey;
  final List<TradeLineDraft> lines;
  final String? counterpartyId;
  final int discountAmount;
  final int shippingCost;
  final int freightCost;
  final int otherCost;
  final double vatRate;
  final bool vatExempt;
  final int paidAmount;
  final String cashAccountCode;

  Map<String, Object?> toPayload(String type) => {
        'type': type,
        'documentDate': documentDate,
        'counterpartyName': counterpartyName.trim(),
        'counterpartyId': counterpartyId,
        'idempotencyKey': idempotencyKey,
        'lines': lines.map((line) => line.toJson()).toList(),
        'discountAmount': discountAmount,
        'shippingCost': shippingCost,
        'freightCost': freightCost,
        'otherCost': otherCost,
        'vatRate': vatRate,
        'vatExempt': vatExempt,
        'paidAmount': paidAmount,
        'cashAccountCode': cashAccountCode,
      };
}

class ReturnLineDraft {
  const ReturnLineDraft({
    required this.sourceLineId,
    required this.quantity,
  });

  final int sourceLineId;
  final double quantity;

  Map<String, Object?> toJson() => {
        'sourceLineId': sourceLineId,
        'quantity': quantity,
      };
}

class ReturnDocumentDraft {
  const ReturnDocumentDraft({
    required this.documentDate,
    required this.sourceDocumentId,
    required this.counterpartyName,
    required this.idempotencyKey,
    required this.lines,
    this.counterpartyId,
  });

  final String documentDate;
  final int sourceDocumentId;
  final String counterpartyName;
  final String idempotencyKey;
  final List<ReturnLineDraft> lines;
  final String? counterpartyId;

  Map<String, Object?> toPayload(String type) => {
        'type': type,
        'documentDate': documentDate,
        'sourceDocumentId': sourceDocumentId,
        'counterpartyName': counterpartyName.trim(),
        'counterpartyId': counterpartyId,
        'idempotencyKey': idempotencyKey,
        'lines': lines.map((line) => line.toJson()).toList(),
      };
}

class PartyPaymentDraft {
  const PartyPaymentDraft({
    required this.documentDate,
    required this.counterpartyName,
    required this.amount,
    required this.idempotencyKey,
    this.counterpartyId,
    this.cashAccountCode = '1000',
    this.referenceId,
  });

  final String documentDate;
  final String counterpartyName;
  final int amount;
  final String idempotencyKey;
  final String? counterpartyId;
  final String cashAccountCode;
  final String? referenceId;

  Map<String, Object?> toPayload(String type) => {
        'type': type,
        'documentDate': documentDate,
        'counterpartyName': counterpartyName.trim(),
        'amount': amount,
        'idempotencyKey': idempotencyKey,
        'counterpartyId': counterpartyId,
        'cashAccountCode': cashAccountCode,
        'referenceId': referenceId,
      };
}

/// Records purchasing, selling, returns, repair-part consumption and party
/// settlements. Each business document, its journal entries and its stock
/// movements are committed in one SQLite transaction.
class TradeRepository {
  TradeRepository(this._database)
      : _accounting = AccountingRepository(_database);

  final AppDatabase _database;
  final AccountingRepository _accounting;

  static const Set<String> _cashAccounts = {'1000', '1010'};

  Future<int> recordPurchase(TradeDocumentDraft draft) async {
    _validateTradeDraft(draft, type: 'purchase');
    final payload = jsonEncode(draft.toPayload('purchase'));
    final db = await _database.database;

    return db.transaction((txn) async {
      final duplicate = await _findDuplicate(txn, draft.idempotencyKey, payload);
      if (duplicate != null) return duplicate;

      final quantities = <double>[];
      final baseAmounts = <int>[];
      for (final line in draft.lines) {
        await _requireProduct(txn, line.productId);
        quantities.add(line.quantity);
        baseAmounts.add((line.quantity * line.unitPrice).round());
      }

      final subtotal = baseAmounts.fold<int>(0, (sum, amount) => sum + amount);
      if (draft.discountAmount > subtotal) {
        throw ArgumentError('تخفیف خرید نمی‌تواند از مبلغ کالاها بیشتر باشد');
      }
      final chargeTotal = draft.shippingCost + draft.freightCost + draft.otherCost;
      final netBase = subtotal - draft.discountAmount;
      final vatAmount = draft.vatExempt
          ? 0
          : (netBase * draft.vatRate / 100).round();
      final discountShares = _allocate(draft.discountAmount, baseAmounts);
      final chargeShares = _allocate(chargeTotal, baseAmounts);

      final landedTotals = <int>[];
      final landedUnitCosts = <int>[];
      for (var i = 0; i < draft.lines.length; i++) {
        final landed = baseAmounts[i] - discountShares[i] + chargeShares[i];
        final unitCost = (landed / quantities[i]).round();
        landedUnitCosts.add(unitCost);
        landedTotals.add((quantities[i] * unitCost).round());
      }
      final inventoryValue =
          landedTotals.fold<int>(0, (sum, amount) => sum + amount);
      final total = inventoryValue + vatAmount;
      _validatePaidAmount(draft.paidAmount, total);
      _validateCashAccount(draft.cashAccountCode);

      final lines = <JournalLineDraft>[];
      if (inventoryValue > 0) {
        lines.add(JournalLineDraft(accountCode: '1200', debit: inventoryValue));
      }
      if (vatAmount > 0) {
        lines.add(JournalLineDraft(accountCode: '2110', debit: vatAmount));
      }
      if (draft.paidAmount > 0) {
        lines.add(JournalLineDraft(
          accountCode: draft.cashAccountCode,
          credit: draft.paidAmount,
        ));
      }
      final payable = total - draft.paidAmount;
      if (payable > 0) {
        lines.add(JournalLineDraft(
          accountCode: '2000',
          credit: payable,
          partyId: draft.counterpartyId,
        ));
      }
      final journalId = total > 0
          ? await _accounting.postJournalEntryInTransaction(
              txn,
              JournalEntryDraft(
                entryDate: draft.documentDate,
                description: 'فاکتور خرید از ${draft.counterpartyName.trim()}',
                idempotencyKey: 'purchase-journal-${draft.idempotencyKey}',
                referenceType: 'purchase',
                referenceId: draft.idempotencyKey,
                lines: lines,
              ),
            )
          : null;

      final documentId = await _insertDocument(
        txn,
        type: 'purchase',
        date: draft.documentDate,
        prefix: 'PUR',
        counterpartyName: draft.counterpartyName,
        counterpartyId: draft.counterpartyId,
        subtotal: subtotal,
        discount: draft.discountAmount,
        charges: chargeTotal,
        vat: vatAmount,
        total: total,
        paid: draft.paidAmount,
        journalEntryId: journalId,
        idempotencyKey: draft.idempotencyKey,
        payload: payload,
      );

      for (var i = 0; i < draft.lines.length; i++) {
        final line = draft.lines[i];
        final productName = await _productName(txn, line.productId);
        await _insertDocumentLine(
          txn,
          documentId: documentId,
          productId: line.productId,
          productName: productName,
          quantity: line.quantity,
          unitPrice: line.unitPrice,
          unitCost: landedUnitCosts[i],
          lineTotal: landedTotals[i],
          taxAmount: _allocate(vatAmount, baseAmounts)[i],
        );
        await _accounting.recordStockMovementInTransaction(
          txn,
          StockMovementDraft(
            productId: line.productId,
            movementType: 'purchase',
            quantityDelta: line.quantity,
            unitCost: landedUnitCosts[i],
            occurredAt: draft.documentDate,
            idempotencyKey: 'purchase-stock-${draft.idempotencyKey}-$i',
            referenceType: 'purchase',
            referenceId: documentId.toString(),
          ),
        );
      }
      return documentId;
    });
  }

  Future<int> recordSale(TradeDocumentDraft draft) async {
    _validateTradeDraft(draft, type: 'sale');
    if (draft.shippingCost != 0 ||
        draft.freightCost != 0 ||
        draft.otherCost != 0) {
      throw ArgumentError('هزینه‌های حمل در این نسخه برای خرید تعریف شده‌اند');
    }
    final payload = jsonEncode(draft.toPayload('sale'));
    final db = await _database.database;

    return db.transaction((txn) async {
      final duplicate = await _findDuplicate(txn, draft.idempotencyKey, payload);
      if (duplicate != null) return duplicate;

      final baseAmounts = <int>[];
      for (final line in draft.lines) {
        await _requireProduct(txn, line.productId);
        baseAmounts.add((line.quantity * line.unitPrice).round());
      }
      final subtotal = baseAmounts.fold<int>(0, (sum, amount) => sum + amount);
      if (draft.discountAmount > subtotal) {
        throw ArgumentError('تخفیف فروش نمی‌تواند از مبلغ کالاها بیشتر باشد');
      }
      final netSales = subtotal - draft.discountAmount;
      final vatAmount = draft.vatExempt
          ? 0
          : (netSales * draft.vatRate / 100).round();
      final total = netSales + vatAmount;
      _validatePaidAmount(draft.paidAmount, total);
      _validateCashAccount(draft.cashAccountCode);

      final revenueLines = <JournalLineDraft>[];
      if (draft.paidAmount > 0) {
        revenueLines.add(JournalLineDraft(
          accountCode: draft.cashAccountCode,
          debit: draft.paidAmount,
        ));
      }
      final receivable = total - draft.paidAmount;
      if (receivable > 0) {
        revenueLines.add(JournalLineDraft(
          accountCode: '1100',
          debit: receivable,
          partyId: draft.counterpartyId,
        ));
      }
      if (netSales > 0) {
        revenueLines.add(JournalLineDraft(accountCode: '4000', credit: netSales));
      }
      if (vatAmount > 0) {
        revenueLines.add(JournalLineDraft(accountCode: '2100', credit: vatAmount));
      }
      final revenueJournalId = total > 0
          ? await _accounting.postJournalEntryInTransaction(
              txn,
              JournalEntryDraft(
                entryDate: draft.documentDate,
                description: 'فاکتور فروش به ${draft.counterpartyName.trim()}',
                idempotencyKey: 'sale-journal-${draft.idempotencyKey}',
                referenceType: 'sale',
                referenceId: draft.idempotencyKey,
                lines: revenueLines,
              ),
            )
          : null;

      final documentId = await _insertDocument(
        txn,
        type: 'sale',
        date: draft.documentDate,
        prefix: 'SAL',
        counterpartyName: draft.counterpartyName,
        counterpartyId: draft.counterpartyId,
        subtotal: subtotal,
        discount: draft.discountAmount,
        charges: 0,
        vat: vatAmount,
        total: total,
        paid: draft.paidAmount,
        journalEntryId: revenueJournalId,
        idempotencyKey: draft.idempotencyKey,
        payload: payload,
      );

      final taxShares = _allocate(vatAmount, baseAmounts);
      final netShares = _allocate(netSales, baseAmounts);
      for (var i = 0; i < draft.lines.length; i++) {
        final line = draft.lines[i];
        final valuation = await _stockValuation(txn, line.productId);
        if (valuation.quantity + 0.0000001 < line.quantity) {
          throw StateError(
            'موجودی کالا کافی نیست؛ شناسه کالا: ${line.productId}، موجودی: ${valuation.quantity}',
          );
        }
        final unitCost = valuation.quantity <= 0
            ? 0
            : (valuation.value / valuation.quantity).round();
        final costAmount = (line.quantity * unitCost).round();
        final productName = await _productName(txn, line.productId);

        await _insertDocumentLine(
          txn,
          documentId: documentId,
          productId: line.productId,
          productName: productName,
          quantity: line.quantity,
          unitPrice: line.unitPrice,
          unitCost: unitCost,
          lineTotal: netShares[i],
          taxAmount: taxShares[i],
        );

        JournalEntryDraft? costJournal;
        if (costAmount > 0) {
          costJournal = JournalEntryDraft(
            entryDate: draft.documentDate,
            description: 'بهای تمام‌شده فروش کالای $productName',
            idempotencyKey: 'sale-cogs-${draft.idempotencyKey}-$i',
            referenceType: 'sale_cogs',
            referenceId: documentId.toString(),
            lines: [
              JournalLineDraft(accountCode: '5000', debit: costAmount),
              JournalLineDraft(accountCode: '1200', credit: costAmount),
            ],
          );
        }
        await _accounting.recordStockMovementInTransaction(
          txn,
          StockMovementDraft(
            productId: line.productId,
            movementType: 'sale',
            quantityDelta: -line.quantity,
            unitCost: unitCost,
            occurredAt: draft.documentDate,
            idempotencyKey: 'sale-stock-${draft.idempotencyKey}-$i',
            referenceType: 'sale',
            referenceId: documentId.toString(),
            journalEntry: costJournal,
          ),
        );
      }
      return documentId;
    });
  }

  Future<int> recordRepairConsumption({
    required String documentDate,
    required String repairId,
    required String customerName,
    required List<TradeLineDraft> parts,
    required String idempotencyKey,
    String? customerId,
  }) async {
    if (DateTime.tryParse(documentDate) == null ||
        repairId.trim().isEmpty ||
        customerName.trim().isEmpty ||
        idempotencyKey.trim().isEmpty ||
        parts.isEmpty) {
      throw ArgumentError('اطلاعات مصرف قطعه در تعمیر کامل نیست');
    }
    for (final line in parts) {
      if (line.productId <= 0 ||
          !line.quantity.isFinite ||
          line.quantity <= 0) {
        throw ArgumentError('تعداد یا شناسه قطعه معتبر نیست');
      }
    }
    final payload = jsonEncode({
      'type': 'repair_consumption',
      'documentDate': documentDate,
      'repairId': repairId,
      'customerName': customerName.trim(),
      'customerId': customerId,
      'idempotencyKey': idempotencyKey,
      'parts': parts.map((line) => line.toJson()).toList(),
    });
    final db = await _database.database;
    return db.transaction((txn) async {
      final duplicate = await _findDuplicate(txn, idempotencyKey, payload);
      if (duplicate != null) return duplicate;

      final prepared = <Map<String, Object?>>[];
      var totalCost = 0;
      for (final part in parts) {
        final valuation = await _stockValuation(txn, part.productId);
        if (valuation.quantity + 0.0000001 < part.quantity) {
          throw StateError('موجودی قطعه برای مصرف در تعمیر کافی نیست');
        }
        final unitCost = valuation.quantity <= 0
            ? 0
            : (valuation.value / valuation.quantity).round();
        final amount = (part.quantity * unitCost).round();
        totalCost += amount;
        prepared.add({
          'productId': part.productId,
          'quantity': part.quantity,
          'unitCost': unitCost,
          'amount': amount,
          'productName': await _productName(txn, part.productId),
        });
      }

      final documentId = await _insertDocument(
        txn,
        type: 'repair_consumption',
        date: documentDate,
        prefix: 'REP',
        counterpartyName: customerName,
        counterpartyId: customerId,
        subtotal: totalCost,
        discount: 0,
        charges: 0,
        vat: 0,
        total: totalCost,
        paid: 0,
        journalEntryId: null,
        sourceDocumentId: null,
        idempotencyKey: idempotencyKey,
        payload: payload,
      );

      for (var i = 0; i < prepared.length; i++) {
        final part = prepared[i];
        final productId = part['productId'] as int;
        final quantity = part['quantity'] as double;
        final unitCost = part['unitCost'] as int;
        final amount = part['amount'] as int;
        final productName = part['productName'] as String;
        await _insertDocumentLine(
          txn,
          documentId: documentId,
          productId: productId,
          productName: productName,
          quantity: quantity,
          unitPrice: 0,
          unitCost: unitCost,
          lineTotal: amount,
          taxAmount: 0,
        );

        JournalEntryDraft? costJournal;
        if (amount > 0) {
          costJournal = JournalEntryDraft(
            entryDate: documentDate,
            description: 'مصرف قطعه در تعمیر شماره $repairId',
            idempotencyKey: 'repair-cost-$idempotencyKey-$i',
            referenceType: 'repair_consumption',
            referenceId: repairId,
            lines: [
              JournalLineDraft(accountCode: '5100', debit: amount),
              JournalLineDraft(accountCode: '1200', credit: amount),
            ],
          );
        }
        await _accounting.recordStockMovementInTransaction(
          txn,
          StockMovementDraft(
            productId: productId,
            movementType: 'repair_consumption',
            quantityDelta: -quantity,
            unitCost: unitCost,
            occurredAt: documentDate,
            idempotencyKey: 'repair-stock-$idempotencyKey-$i',
            referenceType: 'repair_consumption',
            referenceId: repairId,
            journalEntry: costJournal,
          ),
        );
      }
      return documentId;
    });
  }

  Future<int> recordCustomerReturn(ReturnDocumentDraft draft) {
    return _recordReturn(draft, isCustomerReturn: true);
  }

  Future<int> recordSupplierReturn(ReturnDocumentDraft draft) {
    return _recordReturn(draft, isCustomerReturn: false);
  }

  Future<int> _recordReturn(
    ReturnDocumentDraft draft, {
    required bool isCustomerReturn,
  }) async {
    if (DateTime.tryParse(draft.documentDate) == null ||
        draft.sourceDocumentId <= 0 ||
        draft.counterpartyName.trim().isEmpty ||
        draft.idempotencyKey.trim().isEmpty ||
        draft.lines.isEmpty) {
      throw ArgumentError('اطلاعات برگشت کالا کامل نیست');
    }
    final seenSourceLines = <int>{};
    for (final line in draft.lines) {
      if (line.sourceLineId <= 0 ||
          !line.quantity.isFinite ||
          line.quantity <= 0 ||
          !seenSourceLines.add(line.sourceLineId)) {
        throw ArgumentError('مقدار برگشت یا سطر مبدا معتبر نیست؛ هر سطر مبدا فقط یک‌بار در سند برگشت بیاید');
      }
    }

    final type = isCustomerReturn ? 'customer_return' : 'supplier_return';
    final payload = jsonEncode(draft.toPayload(type));
    final db = await _database.database;
    return db.transaction((txn) async {
      final duplicate = await _findDuplicate(txn, draft.idempotencyKey, payload);
      if (duplicate != null) return duplicate;

      final sourceRows = await txn.query(
        'business_documents',
        where: 'id = ?',
        whereArgs: [draft.sourceDocumentId],
        limit: 1,
      );
      if (sourceRows.isEmpty) throw StateError('فاکتور مبدا پیدا نشد');
      final source = sourceRows.single;
      final requiredSourceType = isCustomerReturn ? 'sale' : 'purchase';
      if (source['document_type'] != requiredSourceType) {
        throw StateError('نوع فاکتور مبدا با نوع برگشت سازگار نیست');
      }

      final prepared = <Map<String, Object?>>[];
      var baseTotal = 0;
      var taxTotal = 0;

      for (final returnLine in draft.lines) {
        final sourceLines = await txn.query(
          'business_document_lines',
          where: 'id = ? AND document_id = ?',
          whereArgs: [returnLine.sourceLineId, draft.sourceDocumentId],
          limit: 1,
        );
        if (sourceLines.isEmpty) throw StateError('سطر فاکتور مبدا پیدا نشد');
        final sourceLine = sourceLines.single;
        final originalQuantity = (sourceLine['quantity'] as num).toDouble();
        final returnedRows = await txn.rawQuery('''
          SELECT
            COALESCE(SUM(return_line.quantity), 0) AS returned_quantity,
            COALESCE(SUM(return_line.line_total), 0) AS returned_base,
            COALESCE(SUM(return_line.tax_amount), 0) AS returned_tax
          FROM business_document_lines return_line
          INNER JOIN business_documents return_doc
            ON return_doc.id = return_line.document_id
          WHERE return_line.source_line_id = ?
            AND return_doc.document_type = ?
        ''', [returnLine.sourceLineId, type]);
        final alreadyReturned =
            (returnedRows.single['returned_quantity'] as num).toDouble();
        final remaining = originalQuantity - alreadyReturned;
        if (returnLine.quantity > remaining + 0.0000001) {
          throw StateError('مقدار برگشت از مقدار باقی‌مانده فاکتور بیشتر است');
        }

        final productId = sourceLine['product_id'] as int;
        final unitCost = sourceLine['unit_cost'] as int;
        final lineBase = sourceLine['line_total'] as int;
        final lineTax = sourceLine['tax_amount'] as int;
        final isFinalReturn = (returnLine.quantity - remaining).abs() < 0.0000001;
        final costAmount = (unitCost * returnLine.quantity).round();
        final baseAmount = isCustomerReturn
            ? (isFinalReturn
                ? lineBase - (returnedRows.single['returned_base'] as num).toInt()
                : (lineBase * returnLine.quantity / originalQuantity).round())
            : costAmount;
        final taxAmount = isFinalReturn
            ? lineTax - (returnedRows.single['returned_tax'] as num).toInt()
            : (lineTax * returnLine.quantity / originalQuantity).round();
        baseTotal += baseAmount;
        taxTotal += taxAmount;
        prepared.add({
          'productId': productId,
          'productName': sourceLine['product_name'] as String,
          'quantity': returnLine.quantity,
          'unitPrice': sourceLine['unit_price'] as int,
          'unitCost': unitCost,
          'baseAmount': baseAmount,
          'taxAmount': taxAmount,
          'costAmount': costAmount,
          'sourceLineId': returnLine.sourceLineId,
        });
      }

      int? mainJournalId;
      if (isCustomerReturn) {
        final lines = <JournalLineDraft>[];
        if (baseTotal > 0) {
          lines.add(JournalLineDraft(accountCode: '4050', debit: baseTotal));
        }
        if (taxTotal > 0) {
          lines.add(JournalLineDraft(accountCode: '2100', debit: taxTotal));
        }
        final settlement = baseTotal + taxTotal;
        if (settlement > 0) {
          lines.add(JournalLineDraft(
            accountCode: '1100',
            credit: settlement,
            partyId: draft.counterpartyId,
          ));
        }
        if (lines.isNotEmpty) {
          mainJournalId = await _accounting.postJournalEntryInTransaction(
            txn,
            JournalEntryDraft(
              entryDate: draft.documentDate,
              description: 'برگشت از فروش به ${draft.counterpartyName.trim()}',
              idempotencyKey: 'customer-return-journal-${draft.idempotencyKey}',
              referenceType: 'customer_return',
              referenceId: draft.sourceDocumentId.toString(),
              lines: lines,
            ),
          );
        }
      }

      final total = baseTotal + taxTotal;
      final documentId = await _insertDocument(
        txn,
        type: type,
        date: draft.documentDate,
        prefix: isCustomerReturn ? 'SRT' : 'PRT',
        counterpartyName: draft.counterpartyName,
        counterpartyId: draft.counterpartyId,
        subtotal: baseTotal,
        discount: 0,
        charges: 0,
        vat: taxTotal,
        total: total,
        paid: 0,
        journalEntryId: mainJournalId,
        sourceDocumentId: draft.sourceDocumentId,
        idempotencyKey: draft.idempotencyKey,
        payload: payload,
      );

      for (var i = 0; i < prepared.length; i++) {
        final line = prepared[i];
        final productId = line['productId'] as int;
        final quantity = line['quantity'] as double;
        final unitCost = line['unitCost'] as int;
        final costAmount = line['costAmount'] as int;
        await _insertDocumentLine(
          txn,
          documentId: documentId,
          sourceLineId: line['sourceLineId'] as int,
          productId: productId,
          productName: line['productName'] as String,
          quantity: quantity,
          unitPrice: line['unitPrice'] as int,
          unitCost: unitCost,
          lineTotal: line['baseAmount'] as int,
          taxAmount: line['taxAmount'] as int,
        );

        JournalEntryDraft? stockJournal;
        if (costAmount > 0) {
          stockJournal = isCustomerReturn
              ? JournalEntryDraft(
                  entryDate: draft.documentDate,
                  description: 'بازگشت بهای تمام‌شده کالای مرجوعی',
                  idempotencyKey: 'customer-return-cogs-${draft.idempotencyKey}-$i',
                  referenceType: type,
                  referenceId: documentId.toString(),
                  lines: [
                    JournalLineDraft(accountCode: '1200', debit: costAmount),
                    JournalLineDraft(accountCode: '5000', credit: costAmount),
                  ],
                )
              : null;
        }

        if (isCustomerReturn) {
          await _accounting.recordStockMovementInTransaction(
            txn,
            StockMovementDraft(
              productId: productId,
              movementType: 'customer_return',
              quantityDelta: quantity,
              unitCost: unitCost,
              occurredAt: draft.documentDate,
              idempotencyKey: 'customer-return-stock-${draft.idempotencyKey}-$i',
              referenceType: type,
              referenceId: documentId.toString(),
              journalEntry: stockJournal,
            ),
          );
        } else {
          final supplierReturnAmount = costAmount + (line['taxAmount'] as int);
          JournalEntryDraft? supplierReturnJournal;
          if (supplierReturnAmount > 0) {
            supplierReturnJournal = JournalEntryDraft(
              entryDate: draft.documentDate,
              description: 'برگشت موجودی به فروشنده',
              idempotencyKey: 'supplier-return-stock-${draft.idempotencyKey}-$i',
              referenceType: type,
              referenceId: documentId.toString(),
              lines: [
                JournalLineDraft(
                  accountCode: '2000',
                  debit: supplierReturnAmount,
                  partyId: draft.counterpartyId,
                ),
                if (costAmount > 0)
                  JournalLineDraft(accountCode: '1200', credit: costAmount),
                if ((line['taxAmount'] as int) > 0)
                  JournalLineDraft(
                    accountCode: '2110',
                    credit: line['taxAmount'] as int,
                  ),
              ],
            );
          }
          await _accounting.recordStockMovementInTransaction(
            txn,
            StockMovementDraft(
              productId: productId,
              movementType: 'supplier_return',
              quantityDelta: -quantity,
              unitCost: unitCost,
              occurredAt: draft.documentDate,
              idempotencyKey: 'supplier-return-stock-${draft.idempotencyKey}-$i',
              referenceType: type,
              referenceId: documentId.toString(),
              journalEntry: supplierReturnJournal,
            ),
          );
        }
      }
      return documentId;
    });
  }

  Future<int> recordCustomerReceipt(PartyPaymentDraft draft) {
    return _recordPartyPayment(draft, isCustomerReceipt: true);
  }

  Future<int> recordSupplierPayment(PartyPaymentDraft draft) {
    return _recordPartyPayment(draft, isCustomerReceipt: false);
  }

  Future<int> _recordPartyPayment(
    PartyPaymentDraft draft, {
    required bool isCustomerReceipt,
  }) async {
    if (DateTime.tryParse(draft.documentDate) == null ||
        draft.counterpartyName.trim().isEmpty ||
        draft.amount <= 0 ||
        draft.idempotencyKey.trim().isEmpty) {
      throw ArgumentError('اطلاعات دریافت یا پرداخت معتبر نیست');
    }
    _validateCashAccount(draft.cashAccountCode);
    final type = isCustomerReceipt ? 'customer_receipt' : 'supplier_payment';
    final payload = jsonEncode(draft.toPayload(type));
    final db = await _database.database;
    return db.transaction((txn) async {
      final duplicate = await _findDuplicate(txn, draft.idempotencyKey, payload);
      if (duplicate != null) return duplicate;

      final sourceDocumentId = int.tryParse(draft.referenceId ?? '');
      if (draft.referenceId != null && sourceDocumentId == null) {
        throw ArgumentError('شناسه فاکتور مرتبط با دریافت یا پرداخت معتبر نیست');
      }
      if (sourceDocumentId != null) {
        final sourceRows = await txn.query(
          'business_documents',
          where: 'id = ?',
          whereArgs: [sourceDocumentId],
          limit: 1,
        );
        if (sourceRows.isEmpty) throw StateError('فاکتور مرتبط پیدا نشد');
        final source = sourceRows.single;
        final requiredSourceType = isCustomerReceipt ? 'sale' : 'purchase';
        if (source['document_type'] != requiredSourceType) {
          throw StateError('نوع فاکتور با نوع دریافت یا پرداخت سازگار نیست');
        }
        if (draft.counterpartyId != null &&
            source['counterparty_id'] != null &&
            draft.counterpartyId != source['counterparty_id']) {
          throw StateError('شخص انتخاب‌شده با شخص فاکتور یکسان نیست');
        }
        final paymentRows = await txn.rawQuery(
          'SELECT COALESCE(SUM(paid_amount), 0) AS paid '
          'FROM business_documents WHERE source_document_id = ? AND document_type = ?',
          [
            sourceDocumentId,
            isCustomerReceipt ? 'customer_receipt' : 'supplier_payment',
          ],
        );
        final returnRows = await txn.rawQuery(
          'SELECT COALESCE(SUM(total_amount), 0) AS returned '
          'FROM business_documents WHERE source_document_id = ? AND document_type = ?',
          [
            sourceDocumentId,
            isCustomerReceipt ? 'customer_return' : 'supplier_return',
          ],
        );
        final checkRows = await txn.rawQuery(
          "SELECT COALESCE(SUM(amount), 0) AS amount FROM check_records "
          "WHERE source_document_id = ? AND status NOT IN ('bounced', 'cancelled')",
          [sourceDocumentId],
        );
        final alreadySettled =
            (source['paid_amount'] as num).toInt() +
            (paymentRows.single['paid'] as num).toInt() +
            (checkRows.single['amount'] as num).toInt();
        final returnedAmount = (returnRows.single['returned'] as num).toInt();
        final outstanding =
            (source['total_amount'] as num).toInt() -
            alreadySettled -
            returnedAmount;
        if (draft.amount > outstanding) {
          throw StateError('مبلغ دریافت یا پرداخت از مانده فاکتور بیشتر است');
        }
      }

      final lines = isCustomerReceipt
          ? [
              JournalLineDraft(
                accountCode: draft.cashAccountCode,
                debit: draft.amount,
              ),
              JournalLineDraft(
                accountCode: '1100',
                credit: draft.amount,
                partyId: draft.counterpartyId,
              ),
            ]
          : [
              JournalLineDraft(
                accountCode: '2000',
                debit: draft.amount,
                partyId: draft.counterpartyId,
              ),
              JournalLineDraft(
                accountCode: draft.cashAccountCode,
                credit: draft.amount,
              ),
            ];
      final journalId = await _accounting.postJournalEntryInTransaction(
        txn,
        JournalEntryDraft(
          entryDate: draft.documentDate,
          description: isCustomerReceipt
              ? 'دریافت از مشتری ${draft.counterpartyName.trim()}'
              : 'پرداخت به فروشنده ${draft.counterpartyName.trim()}',
          idempotencyKey: '${type}-journal-${draft.idempotencyKey}',
          referenceType: type,
          referenceId: draft.referenceId,
          lines: lines,
        ),
      );
      return _insertDocument(
        txn,
        type: type,
        date: draft.documentDate,
        prefix: isCustomerReceipt ? 'RCV' : 'PAY',
        counterpartyName: draft.counterpartyName,
        counterpartyId: draft.counterpartyId,
        subtotal: draft.amount,
        discount: 0,
        charges: 0,
        vat: 0,
        total: draft.amount,
        paid: draft.amount,
        journalEntryId: journalId,
        sourceDocumentId: sourceDocumentId,
        idempotencyKey: draft.idempotencyKey,
        payload: payload,
      );
    });
  }

  Future<int> getOutstandingAmount(int documentId) async {
    final db = await _database.database;
    final rows = await db.query(
      'business_documents',
      where: 'id = ?',
      whereArgs: [documentId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('فاکتور پیدا نشد');
    final document = rows.single;
    final type = document['document_type'];
    final paymentType = type == 'sale'
        ? 'customer_receipt'
        : type == 'purchase'
            ? 'supplier_payment'
            : null;
    if (paymentType == null) {
      throw ArgumentError('این نوع سند تسویه دریافت یا پرداخت ندارد');
    }
    final payments = await db.rawQuery(
      'SELECT COALESCE(SUM(paid_amount), 0) AS paid '
      'FROM business_documents WHERE source_document_id = ? AND document_type = ?',
      [documentId, paymentType],
    );
    final returnType = type == 'sale' ? 'customer_return' : 'supplier_return';
    final returns = await db.rawQuery(
      'SELECT COALESCE(SUM(total_amount), 0) AS returned '
      'FROM business_documents WHERE source_document_id = ? AND document_type = ?',
      [documentId, returnType],
    );
    final checks = await db.rawQuery(
      "SELECT COALESCE(SUM(amount), 0) AS amount FROM check_records "
      "WHERE source_document_id = ? AND status NOT IN ('bounced', 'cancelled')",
      [documentId],
    );
    final totalPaid = (document['paid_amount'] as num).toInt() +
        (payments.single['paid'] as num).toInt() +
        (checks.single['amount'] as num).toInt();
    final totalReturned = (returns.single['returned'] as num).toInt();
    final total = (document['total_amount'] as num).toInt();
    return total - totalPaid - totalReturned;
  }

  Future<List<Map<String, Object?>>> getDocuments({
    String? type,
    String? counterpartyId,
  }) async {
    final db = await _database.database;
    return db.query(
      'business_documents',
      where: [
        if (type != null) 'document_type = ?',
        if (counterpartyId != null) 'counterparty_id = ?',
      ].join(' AND ').isEmpty
          ? null
          : [
              if (type != null) 'document_type = ?',
              if (counterpartyId != null) 'counterparty_id = ?',
            ].join(' AND '),
      whereArgs: [
        if (type != null) type,
        if (counterpartyId != null) counterpartyId,
      ],
      orderBy: 'document_date DESC, id DESC',
    );
  }

  Future<List<Map<String, Object?>>> getDocumentLines(int documentId) async {
    final db = await _database.database;
    return db.query(
      'business_document_lines',
      where: 'document_id = ?',
      whereArgs: [documentId],
      orderBy: 'id ASC',
    );
  }

  void _validateTradeDraft(
    TradeDocumentDraft draft, {
    required String type,
  }) {
    if (DateTime.tryParse(draft.documentDate) == null ||
        draft.counterpartyName.trim().isEmpty ||
        draft.idempotencyKey.trim().isEmpty ||
        draft.lines.isEmpty ||
        draft.discountAmount < 0 ||
        draft.shippingCost < 0 ||
        draft.freightCost < 0 ||
        draft.otherCost < 0 ||
        !draft.vatRate.isFinite ||
        draft.vatRate < 0 ||
        draft.vatRate > 100 ||
        draft.paidAmount < 0) {
      throw ArgumentError('اطلاعات فاکتور خرید یا فروش معتبر نیست');
    }
    if (type == 'sale' &&
        (draft.shippingCost != 0 ||
            draft.freightCost != 0 ||
            draft.otherCost != 0)) {
      throw ArgumentError('هزینه‌های اضافی فقط برای فاکتور خرید پشتیبانی می‌شوند');
    }
    for (final line in draft.lines) {
      if (line.productId <= 0 ||
          !line.quantity.isFinite ||
          line.quantity <= 0 ||
          line.unitPrice < 0) {
        throw ArgumentError('اطلاعات یکی از ردیف‌های فاکتور معتبر نیست');
      }
    }
  }

  void _validatePaidAmount(int paid, int total) {
    if (paid < 0 || paid > total) {
      throw ArgumentError('مبلغ پرداخت‌شده نمی‌تواند از مبلغ فاکتور بیشتر باشد');
    }
  }

  void _validateCashAccount(String code) {
    if (!_cashAccounts.contains(code)) {
      throw ArgumentError('حساب دریافت یا پرداخت باید صندوق یا بانک باشد');
    }
  }

  List<int> _allocate(int amount, List<int> weights) {
    if (weights.isEmpty) return const [];
    final weightTotal = weights.fold<int>(0, (sum, value) => sum + value);
    if (amount == 0) {
      return List<int>.filled(weights.length, 0);
    }
    if (weightTotal == 0) {
      final result = List<int>.filled(weights.length, 0);
      result[result.length - 1] = amount;
      return result;
    }
    final result = List<int>.filled(weights.length, 0);
    var assigned = 0;
    for (var i = 0; i < weights.length; i++) {
      if (i == weights.length - 1) {
        result[i] = amount - assigned;
      } else {
        result[i] = (amount * weights[i] / weightTotal).round();
        assigned += result[i];
      }
    }
    return result;
  }

  Future<int?> _findDuplicate(
    DatabaseExecutor txn,
    String idempotencyKey,
    String payload,
  ) async {
    final rows = await txn.query(
      'business_documents',
      where: 'idempotency_key = ?',
      whereArgs: [idempotencyKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    if (rows.single['payload_json'] != payload) {
      throw StateError('کلید یکتای سند با اطلاعات دیگری استفاده شده است');
    }
    return rows.single['id'] as int;
  }

  Future<void> _requireProduct(DatabaseExecutor txn, int productId) async {
    final rows = await txn.query(
      'products',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [productId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('کالای موردنظر پیدا نشد');
  }

  Future<String> _productName(DatabaseExecutor txn, int productId) async {
    final rows = await txn.query(
      'products',
      columns: ['data_json'],
      where: 'id = ?',
      whereArgs: [productId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('کالای موردنظر پیدا نشد');
    final decoded = jsonDecode(rows.single['data_json'] as String);
    if (decoded is Map<String, dynamic>) {
      final name = decoded['نام کالا'] ?? decoded['name'];
      if (name != null && name.toString().trim().isNotEmpty) {
        return name.toString();
      }
    }
    return 'کالای شماره $productId';
  }

  Future<_StockValuation> _stockValuation(
    DatabaseExecutor txn,
    int productId,
  ) async {
    final rows = await txn.rawQuery('''
      SELECT
        COALESCE(SUM(quantity_delta), 0) AS quantity,
        COALESCE(SUM(CASE
          WHEN quantity_delta > 0 THEN total_cost
          ELSE -total_cost
        END), 0) AS value
      FROM inventory_movements
      WHERE product_id = ?
    ''', [productId]);
    return _StockValuation(
      (rows.single['quantity'] as num).toDouble(),
      (rows.single['value'] as num).toInt(),
    );
  }

  Future<int> _insertDocument(
    DatabaseExecutor txn, {
    required String type,
    required String date,
    required String prefix,
    required String counterpartyName,
    required String? counterpartyId,
    required int subtotal,
    required int discount,
    required int charges,
    required int vat,
    required int total,
    required int paid,
    required int? journalEntryId,
    required String idempotencyKey,
    required String payload,
    int? sourceDocumentId,
  }) {
    final now = DateTime.now().toIso8601String();
    return txn.insert('business_documents', {
      'document_type': type,
      'document_date': date,
      'document_number': '$prefix-${DateTime.now().microsecondsSinceEpoch}',
      'counterparty_id': counterpartyId,
      'counterparty_name': counterpartyName.trim(),
      'subtotal': subtotal,
      'discount_amount': discount,
      'charges_amount': charges,
      'vat_amount': vat,
      'total_amount': total,
      'paid_amount': paid,
      'source_document_id': sourceDocumentId,
      'journal_entry_id': journalEntryId,
      'idempotency_key': idempotencyKey,
      'payload_json': payload,
      'created_at': now,
    });
  }

  Future<void> _insertDocumentLine(
    DatabaseExecutor txn, {
    required int documentId,
    required int productId,
    required String productName,
    required double quantity,
    required int unitPrice,
    required int unitCost,
    required int lineTotal,
    required int taxAmount,
    int? sourceLineId,
  }) async {
    await txn.insert('business_document_lines', {
      'document_id': documentId,
      'source_line_id': sourceLineId,
      'product_id': productId,
      'product_name': productName,
      'quantity': quantity,
      'unit_price': unitPrice,
      'unit_cost': unitCost,
      'line_total': lineTotal,
      'tax_amount': taxAmount,
      'created_at': DateTime.now().toIso8601String(),
    });
  }
}

class _StockValuation {
  const _StockValuation(this.quantity, this.value);

  final double quantity;
  final int value;
}
