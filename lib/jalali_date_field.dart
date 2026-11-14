import 'package:material_ui/material_ui.dart';
import 'package:shamsi_date/shamsi_date.dart';

const List<String> _jalaliMonthNames = [
  'فروردین',
  'اردیبهشت',
  'خرداد',
  'تیر',
  'مرداد',
  'شهریور',
  'مهر',
  'آبان',
  'آذر',
  'دی',
  'بهمن',
  'اسفند',
];

const List<String> _jalaliWeekdayNames = ['ش', 'ی', 'د', 'س', 'چ', 'پ', 'ج'];

String toPersianDigits(String value) {
  const english = '0123456789';
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  var result = value;
  for (var i = 0; i < english.length; i++) {
    result = result.replaceAll(english[i], persian[i]);
  }
  return result;
}

String formatJalaliDate(DateTime value) {
  final date = Jalali.fromDateTime(value);
  final f = date.formatter;
  return toPersianDigits('${f.yyyy}/${f.mm}/${f.dd}');
}

/// Parse a typed Solar Hijri date and return its Gregorian DateTime value.
/// Storage and accounting continue to use Gregorian ISO dates.
DateTime? parseJalaliDate(String value) {
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  var normalized = value.trim();
  for (var i = 0; i < 10; i++) {
    normalized = normalized.replaceAll(persian[i], '$i');
    normalized = normalized.replaceAll(arabic[i], '$i');
  }
  final match = RegExp(r'^(\\d{4})[/-](\\d{1,2})[/-](\\d{1,2})$')
      .firstMatch(normalized);
  if (match == null) return null;
  try {
    final jalali = Jalali(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
    final gregorian = jalali.toGregorian();
    return DateTime(gregorian.year, gregorian.month, gregorian.day);
  } catch (_) {
    return null;
  }
}

class JalaliDateField extends StatefulWidget {
  const JalaliDateField({
    super.key,
    required this.initialDate,
    required this.onChanged,
    this.label = 'تاریخ',
  });

  final DateTime initialDate;
  final ValueChanged<DateTime> onChanged;
  final String label;

  @override
  State<JalaliDateField> createState() => _JalaliDateFieldState();
}

class _JalaliDateFieldState extends State<JalaliDateField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: formatJalaliDate(widget.initialDate));
  }

  @override
  void didUpdateWidget(covariant JalaliDateField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialDate != widget.initialDate) {
      _controller.text = formatJalaliDate(widget.initialDate);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final selected = await showDialog<DateTime>(
      context: context,
      builder: (context) => _JalaliDatePickerDialog(initialDate: widget.initialDate),
    );
    if (selected == null || !mounted) return;
    _controller.text = formatJalaliDate(selected);
    widget.onChanged(DateTime(selected.year, selected.month, selected.day));
  }

  void _onManualChange(String value) {
    final parsed = parseJalaliDate(value);
    if (parsed != null) widget.onChanged(parsed);
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _controller,
        keyboardType: TextInputType.datetime,
        textDirection: TextDirection.ltr,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: '۱۴۰۵/۰۸/۲۳',
          prefixIcon: IconButton(
            tooltip: 'انتخاب تاریخ شمسی',
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_month),
          ),
        ),
        onChanged: _onManualChange,
      );
}

class _JalaliDatePickerDialog extends StatefulWidget {
  const _JalaliDatePickerDialog({required this.initialDate});

  final DateTime initialDate;

  @override
  State<_JalaliDatePickerDialog> createState() => _JalaliDatePickerDialogState();
}

class _JalaliDatePickerDialogState extends State<_JalaliDatePickerDialog> {
  late Jalali _visibleMonth;

  @override
  void initState() {
    super.initState();
    _visibleMonth = Jalali.fromDateTime(widget.initialDate).withDay(1);
  }

  void _changeMonth(int amount) {
    setState(() => _visibleMonth = _visibleMonth.addMonths(amount).withDay(1));
  }

  @override
  Widget build(BuildContext context) {
    final monthLength = _visibleMonth.monthLength;
    final firstWeekday = _visibleMonth.weekDay;
    final cells = <Widget>[
      for (final weekday in _jalaliWeekdayNames)
        Center(
          child: Text(
            weekday,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      for (var empty = 1; empty < firstWeekday; empty++) const SizedBox.shrink(),
      for (var day = 1; day <= monthLength; day++)
        _buildDay(day),
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
        title: Row(
          children: [
            IconButton(
              tooltip: 'ماه قبل',
              onPressed: () => _changeMonth(-1),
              icon: const Icon(Icons.chevron_right),
            ),
            Expanded(
              child: Center(
                child: Text(
                  '${_jalaliMonthNames[_visibleMonth.month - 1]} ${toPersianDigits(_visibleMonth.year.toString())}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            IconButton(
              tooltip: 'ماه بعد',
              onPressed: () => _changeMonth(1),
              icon: const Icon(Icons.chevron_left),
            ),
          ],
        ),
        content: SizedBox(
          width: 320,
          child: GridView.count(
            shrinkWrap: true,
            crossAxisCount: 7,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            children: cells,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('انصراف'),
          ),
        ],
      ),
    );
  }

  Widget _buildDay(int day) {
    final selected = _visibleMonth.copy(day: day);
    final today = Jalali.now();
    final isToday = selected.year == today.year &&
        selected.month == today.month &&
        selected.day == today.day;
    return TextButton(
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        backgroundColor: isToday
            ? Theme.of(context).colorScheme.primaryContainer
            : null,
        shape: const CircleBorder(),
      ),
      onPressed: () => Navigator.pop(context, selected.toDateTime()),
      child: Text(toPersianDigits(day.toString())),
    );
  }
}
