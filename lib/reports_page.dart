import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' as painting;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:material_ui/material_ui.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'app_database.dart';
import 'jalali_date_field.dart';
import 'report_repository.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  final _repository = ReportRepository(AppDatabase());
  late DateTime _from;
  late DateTime _to;
  String _type = 'all';
  String _report = 'documents';
  bool _loading = false;
  List<Map<String, Object?>> _rows = [];
  final _reportSearchController = TextEditingController();

  @override
  void dispose() {
    _reportSearchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month, now.day);
    _load();
  }

  Future<void> _load() async {
    if (_to.isBefore(_from)) {
      _message('تاریخ پایان نباید قبل از تاریخ شروع باشد');
      return;
    }
    setState(() => _loading = true);
    try {
      final rows = switch (_report) {
        'stock' => await _repository.getInventoryMovements(from: _from, to: _to),
        'stock_prices' => await _repository.getStockPriceList(),
        'profit' => await _repository.getProfitAndLoss(from: _from, to: _to),
        'item_sales' => await _repository.getItemSales(from: _from, to: _to),
        'item_profit' => await _repository.getItemProfit(from: _from, to: _to),
        'expenses' => await _repository.getExpenses(from: _from, to: _to),
        'repair_income' => await _repository.getRepairServiceRevenue(from: _from, to: _to),
        _ => await _repository.getTradeDocuments(
              from: _from,
              to: _to,
              type: _type == 'all' ? null : _type,
            ),
      };
      if (mounted) setState(() => _rows = rows);
    } catch (error) {
      _message('دریافت گزارش ناموفق بود: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _message(String value) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  String _money(Object? value) {
    final number = (value as num?)?.toInt() ?? 0;
    return number.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (match) => ',',
    );
  }

  String _typeName(Object? value) => switch (value) {
    'sale' => 'فروش',
    'purchase' => 'خرید',
    'customer_return' => 'برگشت از فروش',
    'supplier_return' => 'برگشت به فروشنده',
    'opening_balance' => 'موجودی افتتاحیه',
    'adjustment' => 'اصلاح موجودی',
    'repair_consumption' => 'مصرف تعمیر',
    _ => value?.toString() ?? '',
  };

  List<Map<String, Object?>> get _visibleRows {
    final query = _reportSearchController.text.trim().toLowerCase();
    return _rows.where((row) =>
      query.isEmpty ||
      row.values.any((value) =>
        value?.toString().toLowerCase().contains(query) ?? false,
      ),
    ).toList(growable: false);
  }

  String _profitGroupName(Map<String, Object?> row) =>
      switch (row['report_group']) {
        'sales_return' => 'برگشت از فروش',
        'income' => 'درآمد',
        _ => 'هزینه',
      };

  Future<void> _exportExcel() async {
    final exportRows = _visibleRows;
    if (exportRows.isEmpty) {
      _message('داده‌ای برای خروجی وجود ندارد');
      return;
    }
    try {
      final excel = Excel.createExcel();
      final sheet = excel['گزارش'];
      if (_report == 'stock_prices') {
        sheet.appendRow([
          TextCellValue('کالا'), TextCellValue('کد کالا'),
          TextCellValue('گروه'), TextCellValue('موجودی'),
          TextCellValue('قیمت خرید واحد'), TextCellValue('قیمت فروش واحد'),
          TextCellValue('ارزش موجودی'),
        ]);
        for (final row in exportRows) {
          sheet.appendRow([
            TextCellValue(row['product_name']?.toString() ?? ''),
            TextCellValue(row['product_code']?.toString() ?? ''),
            TextCellValue(row['category']?.toString() ?? ''),
            DoubleCellValue((row['stock_quantity'] as num).toDouble()),
            IntCellValue((row['purchase_price'] as num).toInt()),
            IntCellValue((row['sale_price'] as num).toInt()),
            IntCellValue((row['stock_value'] as num).toInt()),
          ]);
        }
      } else if (_report == 'stock') {
        sheet.appendRow([
          TextCellValue('تاریخ'), TextCellValue('کالا'),
          TextCellValue('نوع گردش'), TextCellValue('تغییر تعداد'),
          TextCellValue('بهای واحد'), TextCellValue('ارزش گردش'),
          TextCellValue('موجودی پس از گردش'),
          TextCellValue('علت اصلاح'), TextCellValue('تعداد شمارش‌شده'),
        ]);
        for (final row in exportRows) {
          sheet.appendRow([
            TextCellValue(row['occurred_at']?.toString() ?? ''),
            TextCellValue(row['product_name']?.toString() ?? ''),
            TextCellValue(_typeName(row['movement_type'])),
            DoubleCellValue((row['quantity_delta'] as num).toDouble()),
            IntCellValue((row['unit_cost'] as num).toInt()),
            IntCellValue((row['total_cost'] as num).toInt()),
            DoubleCellValue((row['balance_after'] as num).toDouble()),
            TextCellValue(row['adjustment_reason']?.toString() ?? ''),
            if (row['counted_quantity'] is num)
              DoubleCellValue((row['counted_quantity'] as num).toDouble())
            else
              TextCellValue(''),
          ]);
        }
      } else if (_report == 'profit') {
        sheet.appendRow([TextCellValue('کد حساب'), TextCellValue('نام حساب'), TextCellValue('نوع'), TextCellValue('بدهکار'), TextCellValue('بستانکار'), TextCellValue('مانده')]);
        for (final row in exportRows) {
          sheet.appendRow([
            TextCellValue(row['account_code']?.toString() ?? ''),
            TextCellValue(row['account_name']?.toString() ?? ''),
            TextCellValue(row['account_type'] == 'income' ? 'درآمد' : 'هزینه'),
            IntCellValue((row['total_debit'] as num).toInt()),
            IntCellValue((row['total_credit'] as num).toInt()),
            IntCellValue((row['balance'] as num).toInt()),
          ]);
        }
      } else if (_report == 'expenses' || _report == 'repair_income') {
        sheet.appendRow([TextCellValue('تاریخ'), TextCellValue('شرح'), TextCellValue('کد حساب'), TextCellValue('نام حساب'), TextCellValue('مبلغ')]);
        for (final row in exportRows) {
          sheet.appendRow([
            TextCellValue(row['entry_date']?.toString() ?? ''),
            TextCellValue(row['description']?.toString() ?? ''),
            TextCellValue(row['account_code']?.toString() ?? ''),
            TextCellValue(row['account_name']?.toString() ?? ''),
            IntCellValue((row['amount'] as num).toInt()),
          ]);
        }
      } else if (_report == 'item_sales') {
        sheet.appendRow([
          TextCellValue('کالا'),
          TextCellValue('تعداد خالص فروش'),
          TextCellValue('مبلغ خالص فروش'),
        ]);
        for (final row in exportRows) {
          sheet.appendRow([
            TextCellValue(row['product_name']?.toString() ?? ''),
            DoubleCellValue((row['net_quantity'] as num).toDouble()),
            IntCellValue((row['net_revenue'] as num).toInt()),
          ]);
        }
      } else if (_report == 'item_profit') {
        sheet.appendRow([TextCellValue('کالا'), TextCellValue('تعداد خالص'), TextCellValue('فروش خالص'), TextCellValue('بهای تمام‌شده'), TextCellValue('سود ناخالص')]);
        for (final row in exportRows) {
          sheet.appendRow([
            TextCellValue(row['product_name']?.toString() ?? ''),
            DoubleCellValue((row['net_quantity'] as num).toDouble()),
            IntCellValue((row['net_revenue'] as num).toInt()),
            IntCellValue((row['net_cost'] as num).toInt()),
            IntCellValue((row['gross_profit'] as num).toInt()),
          ]);
        }
      } else {
        sheet.appendRow([
          TextCellValue('تاریخ'), TextCellValue('شماره سند'),
          TextCellValue('نوع سند'), TextCellValue('طرف حساب'),
          TextCellValue('جمع'), TextCellValue('تخفیف'),
          TextCellValue('مالیات'), TextCellValue('مبلغ نهایی'),
          TextCellValue('پرداخت اولیه'),
        ]);
        for (final row in exportRows) {
          sheet.appendRow([
            TextCellValue(row['document_date']?.toString() ?? ''),
            TextCellValue(row['document_number']?.toString() ?? ''),
            TextCellValue(_typeName(row['document_type'])),
            TextCellValue(row['counterparty_name']?.toString() ?? ''),
            IntCellValue((row['subtotal'] as num).toInt()),
            IntCellValue((row['discount_amount'] as num).toInt()),
            IntCellValue((row['vat_amount'] as num).toInt()),
            IntCellValue((row['total_amount'] as num).toInt()),
            IntCellValue((row['paid_amount'] as num).toInt()),
          ]);
        }
      }
      final bytes = excel.save();
      if (bytes == null) throw StateError('ساخت فایل Excel ناموفق بود');
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/report_${DateTime.now().millisecondsSinceEpoch}.xlsx');
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
        text: 'گزارش نرم‌افزار خدمات فنی حسین',
      );
    } catch (error) {
      _message('ساخت یا اشتراک فایل Excel ناموفق بود: $error');
    }
  }


  String get _reportTitle => switch (_report) {
    'stock' => 'گزارش کاردکس و گردش انبار',
    'stock_prices' => 'فهرست قیمت و موجودی کالاها',
    'item_sales' => 'گزارش فروش خالص هر کالا',
    'profit' => 'گزارش سود و زیان',
    'item_profit' => 'گزارش سود هر کالا',
    'expenses' => 'گزارش هزینه‌های ثبت‌شده',
    'repair_income' => 'گزارش درآمد خدمات تعمیر',
    _ => 'گزارش فاکتورهای خرید، فروش و برگشت',
  };

  List<String> _reportExportLines(List<Map<String, Object?>> rows) {
    return rows.map((row) {
      if (_report == 'expenses' || _report == 'repair_income') {
        return "\${row['entry_date']} | \${row['description']} | \${row['account_name']} | \${_money(row['amount'])} تومان";
      }
      if (_report == 'profit') {
        return "\${row['account_code']} - \${row['account_name']} | \${_profitGroupName(row)}: \${_money(row['balance'])} تومان";
      }
      if (_report == 'item_sales') {
        return "\${row['product_name']} | تعداد خالص: \${row['net_quantity']} | فروش خالص: \${_money(row['net_revenue'])} تومان";
      }
      if (_report == 'item_profit') {
        return "\${row['product_name']} | فروش: \${_money(row['net_revenue'])} | بها: \${_money(row['net_cost'])} | سود: \${_money(row['gross_profit'])}";
      }
      if (_report == 'stock_prices') {
        return "\${row['product_name']} | کد: \${row['product_code']} | موجودی: \${row['stock_quantity']} | خرید: \${_money(row['purchase_price'])} | فروش: \${_money(row['sale_price'])} تومان";
      }
      if (_report == 'stock') {
        return "\${row['occurred_at']} | \${row['product_name']} | \${_typeName(row['movement_type'])} | تغییر: \${row['quantity_delta']} | مانده: \${row['balance_after']}\${row['adjustment_reason'] == null ? '' : " | علت: \${row['adjustment_reason']} | شمارش واقعی: \${row['counted_quantity']}"}";
      }
      return "\${row['document_date']} | \${_typeName(row['document_type'])} | \${row['document_number']} | \${_money(row['total_amount'])} تومان";
    }).toList(growable: false);
  }

  Future<Uint8List> _renderReportPagePng(
    List<String> lines, {
    required int pageNumber,
    required int pageCount,
  }) async {
    const width = 1240.0;
    const height = 1754.0;
    const margin = 64.0;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src);
    var y = 64.0;

    double drawText(String value, {double size = 23, bool bold = false}) {
      final painter = painting.TextPainter(
        text: painting.TextSpan(
          text: value,
          style: painting.TextStyle(
            color: const ui.Color(0xFF202124),
            fontSize: size,
            fontWeight: bold ? painting.FontWeight.bold : painting.FontWeight.normal,
          ),
        ),
        textDirection: painting.TextDirection.rtl,
        textAlign: painting.TextAlign.right,
        maxLines: 2,
      )..layout(maxWidth: width - margin * 2);
      painter.paint(canvas, ui.Offset(margin, y));
      return painter.height;
    }

    y += drawText('خدمات فنی حسین', size: 42, bold: true) + 18;
    y += drawText(_reportTitle, size: 32, bold: true) + 12;
    y += drawText(
      'از \${_from.toIso8601String().substring(0, 10)} تا \${_to.toIso8601String().substring(0, 10)}',
      size: 21,
    ) + 12;
    y += drawText('صفحه $pageNumber از $pageCount', size: 18) + 20;
    canvas.drawLine(
      ui.Offset(margin, y),
      ui.Offset(width - margin, y),
      ui.Paint()..color = const ui.Color(0xFFB8BEC5)..strokeWidth = 2,
    );
    y += 22;

    for (var index = 0; index < lines.length; index++) {
      y += drawText('\${(pageNumber - 1) * 18 + index + 1}. \${lines[index]}', size: 21) + 13;
      canvas.drawLine(
        ui.Offset(margin, y),
        ui.Offset(width - margin, y),
        ui.Paint()..color = const ui.Color(0xFFE0E3E7),
      );
      y += 9;
    }

    final picture = recorder.endRecording();
    final raster = await picture.toImage(width.toInt(), height.toInt());
    final png = await raster.toByteData(format: ui.ImageByteFormat.png);
    raster.dispose();
    picture.dispose();
    if (png == null) throw StateError('ساخت تصویر گزارش ناموفق بود');
    return png.buffer.asUint8List();
  }

  Future<void> _exportPdf() async {
    final exportRows = _visibleRows;
    if (exportRows.isEmpty) {
      _message('داده‌ای برای خروجی وجود ندارد');
      return;
    }
    try {
      const pageSize = 18;
      final lines = _reportExportLines(exportRows);
      final pageCount = (lines.length / pageSize).ceil();
      final document = pw.Document();
      for (var page = 0; page < pageCount; page++) {
        final start = page * pageSize;
        final end = (start + pageSize).clamp(0, lines.length);
        final png = await _renderReportPagePng(
          lines.sublist(start, end),
          pageNumber: page + 1,
          pageCount: pageCount,
        );
        document.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.fill),
        ));
      }
      final bytes = await document.save();
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'report_\${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
    } catch (error) {
      _message('ساخت یا اشتراک PDF ناموفق بود: $error');
    }
  }

  Future<void> _exportImage() async {
    final exportRows = _visibleRows;
    if (exportRows.isEmpty) {
      _message('داده‌ای برای خروجی وجود ندارد');
      return;
    }
    final imageFiles = <File>[];
    try {
      const pageSize = 18;
      final lines = _reportExportLines(exportRows);
      final pageCount = (lines.length / pageSize).ceil();
      final directory = await getTemporaryDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      for (var page = 0; page < pageCount; page++) {
        final start = page * pageSize;
        final end = (start + pageSize).clamp(0, lines.length);
        final png = await _renderReportPagePng(
          lines.sublist(start, end),
          pageNumber: page + 1,
          pageCount: pageCount,
        );
        final file = File(
          '\${directory.path}/report_\${stamp}_\${(page + 1).toString().padLeft(2, '0')}.png',
        );
        await file.writeAsBytes(png, flush: true);
        imageFiles.add(file);
      }
      await Share.shareXFiles(
        imageFiles.map((file) => XFile(file.path, mimeType: 'image/png')).toList(),
        text: pageCount == 1
            ? 'تصویر گزارش نرم‌افزار خدمات فنی حسین'
            : 'تصاویر گزارش چندصفحه‌ای نرم‌افزار خدمات فنی حسین ($pageCount صفحه)',
      );
    } catch (error) {
      _message('ساخت یا اشتراک تصویر گزارش ناموفق بود: $error');
    } finally {
      for (final file in imageFiles) {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {
          // The sharing extension may still be reading the temporary file.
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleRows = _visibleRows;
    final total = switch (_report) {
      'stock' => visibleRows.fold<double>(0, (sum, row) => sum + (row['quantity_delta'] as num).toDouble()),
      'stock_prices' => visibleRows.fold<int>(
          0, (sum, row) => sum + (row['stock_value'] as num).toInt()),
      'profit' => visibleRows.fold<int>(0, (sum, row) => sum + (row['balance'] as num).toInt() * (row['account_type'] == 'income' ? 1 : -1)),
      'item_sales' => visibleRows.fold<int>(0, (sum, row) => sum + (row['net_revenue'] as num).toInt()),
      'item_profit' => visibleRows.fold<int>(0, (sum, row) => sum + (row['gross_profit'] as num).toInt()),
      'expenses' => visibleRows.fold<int>(0, (sum, row) => sum + (row['amount'] as num).toInt()),
      'repair_income' => visibleRows.fold<int>(0, (sum, row) => sum + (row['amount'] as num).toInt()),
      _ => visibleRows.fold<int>(0, (sum, row) => sum + (row['total_amount'] as num).toInt()),
    };
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('گزارش‌های عملیاتی', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        JalaliDateField(
          initialDate: _from,
          label: 'از تاریخ شمسی',
          onChanged: (value) { setState(() => _from = value); _load(); },
        ),
        const SizedBox(height: 8),
        JalaliDateField(
          initialDate: _to,
          label: 'تا تاریخ شمسی',
          onChanged: (value) { setState(() => _to = value); _load(); },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _report,
          decoration: const InputDecoration(labelText: 'نوع گزارش'),
          items: const [
            DropdownMenuItem(value: 'documents', child: Text('فاکتورهای خرید، فروش و برگشت')),
            DropdownMenuItem(value: 'stock', child: Text('کاردکس و گردش انبار')),
            DropdownMenuItem(value: 'stock_prices', child: Text('فهرست قیمت و موجودی کالاها')),
            DropdownMenuItem(value: 'profit', child: Text('سود و زیان حسابداری')),
            DropdownMenuItem(value: 'item_sales', child: Text('فروش خالص هر کالا')),
            DropdownMenuItem(value: 'item_profit', child: Text('سود هر کالا')),
            DropdownMenuItem(value: 'expenses', child: Text('هزینه‌های ثبت‌شده')),
            DropdownMenuItem(value: 'repair_income', child: Text('درآمد خدمات تعمیر')),
          ],
          onChanged: (value) { if (value != null) setState(() { _report = value; }); _load(); },
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _reportSearchController,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'جست‌وجو در همین گزارش',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _reportSearchController.text.isEmpty ? null : IconButton(
              tooltip: 'پاک کردن جست‌وجو',
              onPressed: () { _reportSearchController.clear(); setState(() {}); },
              icon: const Icon(Icons.close),
            ),
          ),
        ),
        if (_report == 'documents') ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'فیلتر نوع سند'),
            items: const [
              DropdownMenuItem(value: 'all', child: Text('همه اسناد')),
              DropdownMenuItem(value: 'sale', child: Text('فروش')),
              DropdownMenuItem(value: 'purchase', child: Text('خرید')),
              DropdownMenuItem(value: 'customer_return', child: Text('برگشت از فروش')),
              DropdownMenuItem(value: 'supplier_return', child: Text('برگشت به فروشنده')),
            ],
            onChanged: (value) { if (value != null) setState(() => _type = value); _load(); },
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: FilledButton.icon(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
              label: const Text('به‌روزرسانی گزارش'),
            )),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(
              onPressed: _loading ? null : _exportExcel,
              icon: const Icon(Icons.table_view),
              label: const Text('Excel'),
            )),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(
              onPressed: _loading ? null : _exportPdf,
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('PDF'),
            )),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _loading ? null : _exportImage,
            icon: const Icon(Icons.image_outlined),
            label: const Text('خروجی تصویر PNG'),
          ),
        ),
        const SizedBox(height: 8),
        Card(child: ListTile(
          title: Text('تعداد ردیف‌ها: ${visibleRows.length}'),
          subtitle: Text(_report == 'stock'
              ? 'خالص تغییر موجودی در بازه: $total'
              : _report == 'stock_prices'
                  ? 'ارزش کل موجودی به بهای تمام‌شده: ${_money(total)} تومان'
                  : _report == 'documents'
                  ? 'جمع مبلغ اسناد: ${_money(total)} تومان'
                  : _report == 'item_sales'
                      ? 'جمع فروش خالص کالاها: ${_money(total)} تومان'
                      : _report == 'expenses'
                      ? 'جمع هزینه‌ها: ${_money(total)} تومان'
                      : _report == 'repair_income'
                          ? 'جمع درآمد خدمات: ${_money(total)} تومان'
                          : 'نتیجه خالص دوره (سود مثبت، زیان منفی): ${_money(total)} تومان'),
        )),
        if (_loading) const Center(child: Padding(
          padding: EdgeInsets.all(20), child: CircularProgressIndicator(),
        )),
        if (!_loading && _rows.isEmpty)
          const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('در این بازه اطلاعاتی ثبت نشده است'))),
        if (!_loading && _rows.isNotEmpty && visibleRows.isEmpty)
          const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('با این عبارت نتیجه‌ای پیدا نشد'))),
        if (_report == 'documents')
          for (final row in visibleRows)
            Card(child: ListTile(
              title: Text('${_typeName(row['document_type'])} — ${row['document_number']}'),
              subtitle: Text('${row['document_date']} • ${row['counterparty_name']}'),
              trailing: Text('${_money(row['total_amount'])} تومان'),
            )),
        if (_report == 'profit')
          for (final row in visibleRows)
            Card(child: ListTile(
              title: Text('${row['account_code']} — ${row['account_name']}'),
              subtitle: Text(_profitGroupName(row)),
              trailing: Text('${_money(row['balance'])} تومان'),
            )),
        if (_report == 'expenses' || _report == 'repair_income')
          for (final row in visibleRows)
            Card(child: ListTile(
              title: Text(row['description']?.toString() ?? ''),
              subtitle: Text('${row['entry_date']} • ${row['account_name']}'),
              trailing: Text('${_money(row['amount'])} تومان'),
            )),
        if (_report == 'item_sales')
          for (final row in visibleRows)
            Card(child: ListTile(
              title: Text(row['product_name']?.toString() ?? ''),
              subtitle: Text('تعداد خالص فروش: ${row['net_quantity']}'),
              trailing: Text('${_money(row['net_revenue'])} تومان'),
            )),
        if (_report == 'item_profit')
          for (final row in visibleRows)
            Card(child: ListTile(
              title: Text('${row['product_name']}'),
              subtitle: Text('فروش خالص: ${_money(row['net_revenue'])} • بهای تمام‌شده: ${_money(row['net_cost'])}'),
              trailing: Text('سود: ${_money(row['gross_profit'])} تومان'),
            )),
        if (_report == 'stock_prices')
          for (final row in visibleRows)
            Card(child: ListTile(
              title: Text(row['product_name']?.toString() ?? ''),
              subtitle: Text(
                'کد: ${row['product_code']} • گروه: ${row['category']} • موجودی: ${row['stock_quantity']}'
                '\nخرید واحد: ${_money(row['purchase_price'])} • فروش واحد: ${_money(row['sale_price'])} تومان'
                '\nارزش موجودی: ${_money(row['stock_value'])} تومان',
              ),
            )),
        if (_report == 'stock')
          for (final row in visibleRows)
            Card(child: ListTile(
              title: Text('${row['product_name']}'),
              subtitle: Text(
                '${row['occurred_at']} • ${_typeName(row['movement_type'])}'
                '\\nتغییر: ${row['quantity_delta']} • موجودی پس از گردش: ${row['balance_after']}'
                "${row['adjustment_reason'] == null ? '' : '\\nعلت اصلاح: ${row['adjustment_reason']} • شمارش واقعی: ${row['counted_quantity']}'}",
              ),
              trailing: Text('${(row['quantity_delta'] as num) > 0 ? '+' : ''}${(row['quantity_delta'] as num).toString()}'),
            )),
        const SizedBox(height: 12),
        const Text(
          'گزارش سود و زیان از دفترکل ثبت‌شده محاسبه می‌شود. هزینه‌ها از بدهکار حساب هزینه و درآمد خدمات تعمیر از بستانکار حساب درآمد خدمات خوانده می‌شود؛ بنابراین پرداخت بعدی هزینه یا دریافت طلب مشتری دوباره شمرده نمی‌شود. سود هر کالا نیز برگشت مشتری و بهای تمام‌شده ثبت‌شده را لحاظ می‌کند.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    );
  }
}
