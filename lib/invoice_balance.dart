import 'package:sqflite/sqflite.dart';

/// Computes invoice balances from posted payments, checks, returns and
/// advances allocated from the same party. Shared by invoice entry,
/// check entry and the party ledger so their balance rules cannot drift.
class InvoiceBalance {
  static Future<int> getOutstandingAmount(
    DatabaseExecutor executor,
    int invoiceDocumentId,
  ) async {
    final rows = await executor.query(
      'business_documents',
      where: 'id = ?',
      whereArgs: [invoiceDocumentId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('فاکتور پیدا نشد');
    final invoice = rows.single;
    final type = invoice['document_type'];
    final paymentType = type == 'sale'
        ? 'customer_receipt'
        : type == 'purchase'
            ? 'supplier_payment'
            : null;
    if (paymentType == null) {
      throw ArgumentError('این نوع سند تسویه دریافت یا پرداخت ندارد');
    }

    final payments = await executor.rawQuery(
      'SELECT COALESCE(SUM(paid_amount), 0) AS paid '
      'FROM business_documents WHERE source_document_id = ? AND document_type = ?',
      [invoiceDocumentId, paymentType],
    );
    final checks = await executor.rawQuery(
      "SELECT COALESCE(SUM(amount), 0) AS amount FROM check_records "
      "WHERE source_document_id = ? AND direction = ? "
      "AND status NOT IN ('bounced', 'cancelled')",
      [invoiceDocumentId, type == 'sale' ? 'incoming' : 'outgoing'],
    );
    final returns = await executor.rawQuery(
      'SELECT COALESCE(SUM(total_amount), 0) AS returned '
      'FROM business_documents WHERE source_document_id = ? AND document_type = ?',
      [
        invoiceDocumentId,
        type == 'sale' ? 'customer_return' : 'supplier_return',
      ],
    );
    final advances = await getAllocatedAdvanceAmount(
      executor,
      invoiceDocumentId,
    );

    final initiallyPaid = (invoice['paid_amount'] as num).toInt();
    final linkedPayments = (payments.single['paid'] as num).toInt();
    final linkedChecks = (checks.single['amount'] as num).toInt();
    final returned = (returns.single['returned'] as num).toInt();
    final total = (invoice['total_amount'] as num).toInt();
    return total - initiallyPaid - linkedPayments - linkedChecks -
        advances - returned;
  }

  static Future<int> getAllocatedAdvanceAmount(
    DatabaseExecutor executor,
    int invoiceDocumentId,
  ) async {
    final rows = await executor.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) AS allocated '
      'FROM invoice_payment_allocations WHERE invoice_document_id = ?',
      [invoiceDocumentId],
    );
    return (rows.single['allocated'] as num).toInt();
  }

  /// Applies unlinked earlier advances to the new invoice in date order.
  /// Directly linked receipts/payments are deliberately excluded so they
  /// cannot be counted a second time.
  static Future<int> allocateAvailableAdvances(
    DatabaseExecutor executor, {
    required int invoiceDocumentId,
    required String invoiceType,
    required String? partyId,
  }) async {
    if (partyId == null || partyId.trim().isEmpty) return 0;
    if (invoiceType != 'sale' && invoiceType != 'purchase') {
      throw ArgumentError('نوع فاکتور برای تخصیص بیعانه معتبر نیست');
    }

    final invoiceRows = await executor.query(
      'business_documents',
      where: 'id = ?',
      whereArgs: [invoiceDocumentId],
      limit: 1,
    );
    if (invoiceRows.isEmpty) {
      throw StateError('فاکتور برای تخصیص بیعانه پیدا نشد');
    }
    final invoice = invoiceRows.single;
    if (invoice['document_type'] != invoiceType ||
        invoice['counterparty_id']?.toString() != partyId) {
      throw StateError('طرف حساب بیعانه با طرف حساب فاکتور یکسان نیست');
    }

    var outstanding = await getOutstandingAmount(
      executor,
      invoiceDocumentId,
    );
    if (outstanding <= 0) return 0;

    final paymentType =
        invoiceType == 'sale' ? 'customer_receipt' : 'supplier_payment';
    final advances = await executor.query(
      'business_documents',
      where: 'document_type = ? AND counterparty_id = ? '
          'AND source_document_id IS NULL AND document_date <= ? '
          'AND paid_amount > 0',
      whereArgs: [paymentType, partyId, invoice['document_date']],
      orderBy: 'document_date ASC, id ASC',
    );

    var appliedTotal = 0;
    for (final advance in advances) {
      if (outstanding <= 0) break;
      final paymentId = advance['id'] as int;
      final allocatedRows = await executor.rawQuery(
        'SELECT COALESCE(SUM(amount), 0) AS allocated '
        'FROM invoice_payment_allocations WHERE payment_document_id = ?',
        [paymentId],
      );
      final alreadyAllocated =
          (allocatedRows.single['allocated'] as num).toInt();
      final advanceAmount = (advance['paid_amount'] as num).toInt();
      final available = advanceAmount - alreadyAllocated;
      if (available <= 0) continue;

      final amount = available < outstanding ? available : outstanding;
      await executor.insert('invoice_payment_allocations', {
        'payment_document_id': paymentId,
        'invoice_document_id': invoiceDocumentId,
        'amount': amount,
        'created_at': DateTime.now().toIso8601String(),
      });
      appliedTotal += amount;
      outstanding -= amount;
    }
    return appliedTotal;
  }
}
