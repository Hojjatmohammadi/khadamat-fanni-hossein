import 'dart:io';
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
        'profit' => await _repository.getProfitAndLoss(from: _from, to: _to),
        'item_profit' => await _repository.getItemProfit(from: _from, to: _to),
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

  Future<void> _exportExcel() async {
    if (_rows.isEmpty) {
      _message('داده‌ای برای خروجی وجود ندارد');
      return;
    }
    try {
      final excel = Excel.createExcel();
      final sheet = excel['گزارش'];
      if (_report == 'stock') {
        sheet.appendRow([
          TextCellValue('تاریخ'), TextCellValue('کالا'),
          TextCellValue('نوع گردش'), TextCellValue('تغییر تعداد'),
          TextCellValue('بهای واحد'), TextCellValue('ارزش گردش'),
        ]);
        for (final row in _rows) {
          sheet.appendRow([
            TextCellValue(row['occurred_at']?.toString() ?? ''),
            TextCellValue(row['product_name']?.toString() ?? ''),
            TextCellValue(_typeName(row['movement_type'])),
            DoubleCellValue((row['quantity_delta'] as num).toDouble()),
            IntCellValue((row['unit_cost'] as num).toInt()),
            IntCellValue((row['total_cost'] as num).toInt()),
          ]);
        }
      } else if (_report == 'profit') {
        sheet.appendRow([TextCellValue('کد حساب'), TextCellValue('نام حساب'), TextCellValue('نوع'), TextCellValue('بدهکار'), TextCellValue('بستانکار'), TextCellValue('مانده')]);
        for (final row in _rows) {
          sheet.appendRow([
            TextCellValue(row['account_code']?.toString() ?? ''),
            TextCellValue(row['account_name']?.toString() ?? ''),
            TextCellValue(row['account_type'] == 'income' ? 'درآمد' : 'هزینه'),
            IntCellValue((row['total_debit'] as num).toInt()),
            IntCellValue((row['total_credit'] as num).toInt()),
            IntCellValue((row['balance'] as num).toInt()),
          ]);
        }
      } else if (_report == 'item_profit') {
        sheet.appendRow([TextCellValue('کالا'), TextCellValue('تعداد خالص'), TextCellValue('فروش خالص'), TextCellValue('بهای تمام‌شده'), TextCellValue('سود ناخالص')]);
        for (final row in _rows) {
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
        for (final row in _rows) {
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


  Future<void> _exportPdf() async {
    if (_rows.isEmpty) {
      _message('داده‌ای برای خروجی وجود ندارد');
      return;
    }
    try {
      const width = 1240.0;
      const height = 1754.0;
      const margin = 64.0;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src);
      var y = 70.0;

      double drawText(String value, {double size = 25, bool bold = false}) {
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

      final title = switch (_report) {
        'stock' => 'گزارش کاردکس و گردش انبار',
        'profit' => 'گزارش سود و زیان',
        'item_profit' => 'گزارش سود هر کالا',
        _ => 'گزارش فاکتورهای خرید، فروش و برگشت',
      };
      y += drawText('خدمات فنی حسین', size: 40, bold: true) + 12;
      y += drawText(title, size: 32, bold: true) + 10;
      y += drawText('از ${_from.toIso8601String().substring(0, 10)} تا ${_to.toIso8601String().substring(0, 10)}', size: 20) + 20;
      canvas.drawLine(ui.Offset(margin, y), ui.Offset(width - margin, y), ui.Paint()..color = const ui.Color(0xFFB8BEC5)..strokeWidth = 2);
      y += 20;

      final lines = <String>[];
      for (final row in _rows.take(27)) {
        if (_report == 'profit') {
          lines.add('${row['account_code']} - ${row['account_name']} | ${row['account_type'] == 'income' ? 'درآمد' : 'هزینه'}: ${_money(row['balance'])} تومان');
        } else if (_report == 'item_profit') {
          lines.add('${row['product_name']} | فروش: ${_money(row['net_revenue'])} | بها: ${_money(row['net_cost'])} | سود: ${_money(row['gross_profit'])}');
        } else if (_report == 'stock') {
          lines.add('${row['occurred_at']} | ${row['product_name']} | ${_typeName(row['movement_type'])} | تعداد: ${row['quantity_delta']}');
        } else {
          lines.add('${row['document_date']} | ${_typeName(row['document_type'])} | ${row['document_number']} | ${_money(row['total_amount'])} تومان');
        }
      }
      for (var i = 0; i < lines.length; i++) {
        final h = drawText('${i + 1}. ${lines[i]}', size: 21);
        y += h + 15;
        canvas.drawLine(ui.Offset(margin, y), ui.Offset(width - margin, y), ui.Paint()..color = const ui.Color(0xFFE0E3E7));
        y += 8;
        if (y > height - 100) break;
      }
      if (_rows.length > lines.length) {
        y += 8;
        drawText('برای کوتاه ماندن فایل، فقط ${lines.length} ردیف نخست نمایش داده شد.', size: 18);
      }

      final picture = recorder.endRecording();
      final raster = await picture.toImage(width.toInt(), height.toInt());
      final png = await raster.toByteData(format: ui.ImageByteFormat.png);
      raster.dispose();
      picture.dispose();
      if (png == null) throw StateError('ساخت تصویر گزارش ناموفق بود');

      final document = pw.Document();
      document.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(
          pw.MemoryImage(png.buffer.asUint8List()),
          fit: pw.BoxFit.fill,
        ),
      ));
      final bytes = await document.save();
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'report_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
    } catch (error) {
      _message('ساخت یا اشتراک PDF ناموفق بود: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = switch (_report) {
      'stock' => _rows.fold<double>(0, (sum, row) => sum + (row['quantity_delta'] as num).toDouble()),
      'profit' => _rows.fold<int>(0, (sum, row) => sum + (row['balance'] as num).toInt() * (row['account_type'] == 'income' ? 1 : -1)),
      'item_profit' => _rows.fold<int>(0, (sum, row) => sum + (row['gross_profit'] as num).toInt()),
      _ => _rows.fold<int>(0, (sum, row) => sum + (row['total_amount'] as num).toInt()),
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
            DropdownMenuItem(value: 'profit', child: Text('سود و زیان حسابداری')),
            DropdownMenuItem(value: 'item_profit', child: Text('سود هر کالا')),
          ],
          onChanged: (value) { if (value != null) setState(() { _report = value; }); _load(); },
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
        Card(child: ListTile(
          title: Text('تعداد ردیف‌ها: ${_rows.length}'),
          subtitle: Text(_report == 'stock'
              ? 'خالص تغییر موجودی در بازه: $total'
              : _report == 'documents'
                  ? 'جمع مبلغ اسناد: ${_money(total)} تومان'
                  : 'سود خالص/ناخالص گزارش: ${_money(total)} تومان'),
        )),
        if (_loading) const Center(child: Padding(
          padding: EdgeInsets.all(20), child: CircularProgressIndicator(),
        )),
        if (!_loading && _rows.isEmpty)
          const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('در این بازه اطلاعاتی ثبت نشده است'))),
        if (_report == 'documents')
          for (final row in _rows)
            Card(child: ListTile(
              title: Text('${_typeName(row['document_type'])} — ${row['document_number']}'),
              subtitle: Text('${row['document_date']} • ${row['counterparty_name']}'),
              trailing: Text('${_money(row['total_amount'])} تومان'),
            )),
        if (_report == 'profit')
          for (final row in _rows)
            Card(child: ListTile(
              title: Text('${row['account_code']} — ${row['account_name']}'),
              subtitle: Text(row['account_type'] == 'income' ? 'درآمد' : 'هزینه'),
              trailing: Text('${_money(row['balance'])} تومان'),
            )),
        if (_report == 'item_profit')
          for (final row in _rows)
            Card(child: ListTile(
              title: Text('${row['product_name']}'),
              subtitle: Text('فروش خالص: ${_money(row['net_revenue'])} • بهای تمام‌شده: ${_money(row['net_cost'])}'),
              trailing: Text('سود: ${_money(row['gross_profit'])} تومان'),
            )),
        if (_report == 'stock')
          for (final row in _rows)
            Card(child: ListTile(
              title: Text('${row['product_name']}'),
              subtitle: Text('${row['occurred_at']} • ${_typeName(row['movement_type'])}'),
              trailing: Text('${(row['quantity_delta'] as num).toString()}'),
            )),
        const SizedBox(height: 12),
        const Text(
          'گزارش سود و زیان از اسناد حسابداری ثبت‌شده و برگشت‌های حسابداری محاسبه می‌شود. سود هر کالا بر پایه فروش خالص، برگشت مشتری و بهای تمام‌شده ثبت‌شده در ردیف فاکتور است. هزینه‌های عملیاتی فقط در صورت ثبت در حساب‌های درآمد/هزینه دفترکل لحاظ می‌شوند.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    );
  }
}
