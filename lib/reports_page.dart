import 'dart:io';

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
      final rows = _report == 'stock'
          ? await _repository.getInventoryMovements(from: _from, to: _to)
          : await _repository.getTradeDocuments(
              from: _from,
              to: _to,
              type: _type == 'all' ? null : _type,
            );
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

  @override
  Widget build(BuildContext context) {
    final total = _report == 'stock'
        ? _rows.fold<double>(0, (sum, row) => sum + (row['quantity_delta'] as num).toDouble())
        : _rows.fold<int>(0, (sum, row) => sum + (row['total_amount'] as num).toInt());
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
          value: _report,
          decoration: const InputDecoration(labelText: 'نوع گزارش'),
          items: const [
            DropdownMenuItem(value: 'documents', child: Text('فاکتورهای خرید، فروش و برگشت')),
            DropdownMenuItem(value: 'stock', child: Text('کاردکس و گردش انبار')),
          ],
          onChanged: (value) { if (value != null) setState(() { _report = value; }); _load(); },
        ),
        if (_report == 'documents') ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _type,
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
              label: const Text('خروجی Excel'),
            )),
          ],
        ),
        const SizedBox(height: 8),
        Card(child: ListTile(
          title: Text('تعداد ردیف‌ها: ${_rows.length}'),
          subtitle: Text(_report == 'stock'
              ? 'خالص تغییر موجودی در بازه: $total'
              : 'جمع مبلغ اسناد: ${_money(total)} تومان'),
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
        if (_report == 'stock')
          for (final row in _rows)
            Card(child: ListTile(
              title: Text('${row['product_name']}'),
              subtitle: Text('${row['occurred_at']} • ${_typeName(row['movement_type'])}'),
              trailing: Text('${(row['quantity_delta'] as num).toString()}'),
            )),
        const SizedBox(height: 12),
        const Text(
          'مبالغ بر اساس اسناد ثبت‌شده در پایگاه داده محلی هستند. گزارش سود خالص در این بخش محاسبه نمی‌شود؛ برای آن باید بهای تمام‌شده، برگشت‌ها و هزینه‌ها با هم تطبیق داده شوند.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    );
  }
}
