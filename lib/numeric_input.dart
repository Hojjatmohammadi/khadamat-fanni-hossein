import 'package:flutter/services.dart';

class NumericInputFormatter extends TextInputFormatter {
  const NumericInputFormatter({this.allowDecimal = false, this.maxLength});
  final bool allowDecimal;
  final int? maxLength;

  static int? _digit(int rune) {
    if (rune >= 48 && rune <= 57) return rune;
    if (rune >= 0x06F0 && rune <= 0x06F9) return rune - 0x06F0 + 48;
    if (rune >= 0x0660 && rune <= 0x0669) return rune - 0x0660 + 48;
    return null;
  }

  String _filter(String value) {
    final out = StringBuffer();
    var count = 0;
    var hasDecimal = false;
    for (final rune in value.runes) {
      final digit = _digit(rune);
      if (digit != null) {
        if (maxLength != null && count >= maxLength!) continue;
        out.writeCharCode(digit);
        count++;
      } else if (allowDecimal && (rune == 46 || rune == 0x066B) && !hasDecimal) {
        out.write('.');
        hasDecimal = true;
      }
    }
    return out.toString();
  }

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final filtered = _filter(newValue.text);
    final offsetRaw = newValue.selection.extentOffset.clamp(0, newValue.text.length).toInt();
    final offsetBefore = _filter(newValue.text.substring(0, offsetRaw)).length;
    final offset = offsetBefore > filtered.length ? filtered.length : offsetBefore;
    return TextEditingValue(
      text: filtered,
      selection: TextSelection.collapsed(offset: offset),
      composing: TextRange.empty,
    );
  }
}

String normalizeDigitGlyphs(String value) {
  const fa = '۰۱۲۳۴۵۶۷۸۹';
  const ar = '٠١٢٣٤٥٦٧٨٩';
  var result = value;
  for (var i = 0; i < 10; i++) {
    result = result.replaceAll(fa[i], '$i').replaceAll(ar[i], '$i');
  }
  return result.replaceAll('\u061C', '').replaceAll('\u200E', '').replaceAll('\u200F', '');
}

String normalizePhoneNumber(String value) {
  var digits = normalizeDigitGlyphs(value).replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.startsWith('0098') && digits.length == 14) {
    digits = '0${digits.substring(4)}';
  } else if (digits.startsWith('98') && digits.length == 12) {
    digits = '0${digits.substring(2)}';
  } else if (digits.length == 10 && digits.startsWith('9')) {
    digits = '0$digits';
  }
  return digits;
}

String _normalizedFieldLabel(String label) => label
    .replaceAll('ي', 'ی')
    .replaceAll('ك', 'ک')
    .replaceAll('\u200c', '')
    .replaceAll('\u200e', '')
    .replaceAll('\u200f', '')
    .replaceAll(RegExp(r'\\s+'), '');

bool isPhoneFieldLabel(String label) {
  final value = _normalizedFieldLabel(label);
  return value.contains('شمارههمراه') ||
      value.contains('شمارهتماس') ||
      value.contains('شمارهتلفن') ||
      value.contains('موبایل') ||
      value.contains('موبايل') ||
      value == 'تلفن' ||
      value == 'تلفنهمراه';
}

bool isPostalCodeFieldLabel(String label) =>
    _normalizedFieldLabel(label).contains('کدپستی');

bool isNationalCodeFieldLabel(String label) =>
    _normalizedFieldLabel(label).contains('کدملی') ||
    _normalizedFieldLabel(label).contains('شمارهملی');

bool isNumericFieldLabel(String label) {
  final value = _normalizedFieldLabel(label);
  if (isPhoneFieldLabel(value) ||
      isPostalCodeFieldLabel(value) ||
      isNationalCodeFieldLabel(value)) {
    return true;
  }
  const terms = [
    'مبلغ', 'قیمت', 'تعداد', 'موجودی', 'درصد', 'اجرت', 'شمارهچک',
    'مانده', 'هزینه', 'پرداخت', 'دریافت', 'اصلمبلغ', 'قسط',
    'شمارهکارت', 'شمارهحساب', 'وزن', 'متراژ', 'طول', 'عرض',
    'ارتفاع', 'بدهی', 'طلب', 'سود', 'زیان', 'مالیات',
    'بیعانه', 'پیشپرداخت', 'سرمایه', 'کیلومتر', 'مسافت',
    'مدت', 'دقیقه', 'ساعت',
  ];
  return terms.any(value.contains);
}

bool allowsDecimalForField(String label) {
  final value = _normalizedFieldLabel(label);
  if (value.contains('اقساط') || value.contains('شماره')) return false;
  return [
    'تعداد', 'موجودی', 'قیمت', 'درصد', 'وزن', 'متراژ',
    'طول', 'عرض', 'ارتفاع',
  ].any(value.contains);
}

TextInputType? numericKeyboardTypeForField(String label) {
  if (isPhoneFieldLabel(label)) return TextInputType.phone;
  if (isNumericFieldLabel(label)) {
    return TextInputType.numberWithOptions(decimal: allowsDecimalForField(label));
  }
  return null;
}

List<TextInputFormatter> numericInputFormattersForField(
  String label, {
  bool forceNumeric = false,
  bool? allowDecimal,
}) {
  if (!forceNumeric && !isNumericFieldLabel(label)) return const [];
  final exactLength = isPhoneFieldLabel(label) ? 11 :
      (isPostalCodeFieldLabel(label) || isNationalCodeFieldLabel(label)) ? 10 : null;
  return [NumericInputFormatter(
    allowDecimal: exactLength == null && (allowDecimal ?? allowsDecimalForField(label)),
    maxLength: exactLength,
  )];
}

String? validateNumericField(String label, String? value, {
  bool forceNumeric = false,
  bool? allowDecimal,
}) {
  final raw = value?.trim() ?? '';
  if (raw.isEmpty) return null;
  if (isPhoneFieldLabel(label)) {
    return normalizePhoneNumber(raw).length == 11 ? null : 'شماره تماس باید دقیقاً ۱۱ رقم باشد.';
  }
  if (isPostalCodeFieldLabel(label)) {
    return RegExp(r'^\d{10}$').hasMatch(normalizeDigitGlyphs(raw))
        ? null : 'کد پستی باید دقیقاً ۱۰ رقم باشد.';
  }
  if (isNationalCodeFieldLabel(label)) {
    return RegExp(r'^\d{10}$').hasMatch(normalizeDigitGlyphs(raw))
        ? null : 'کد ملی باید دقیقاً ۱۰ رقم باشد.';
  }
  if (!forceNumeric && !isNumericFieldLabel(label)) return null;
  final normalized = normalizeDigitGlyphs(raw).replaceAll('٫', '.')
      .replaceAll('٬', '').replaceAll(',', '').replaceAll('،', '')
      .replaceAll(RegExp(r'[\s\u00A0\u202F]'), '');
  final decimal = allowDecimal ?? allowsDecimalForField(label);
  final pattern = decimal ? RegExp(r'^\d+(?:\.\d+)?$') : RegExp(r'^\d+$');
  return pattern.hasMatch(normalized) ? null : 'لطفاً فقط عدد وارد کنید.';
}

String normalizeNumericField(String label, String value) {
  if (isPhoneFieldLabel(label)) return normalizePhoneNumber(value);
  if (!isNumericFieldLabel(label)) return value.trim();
  return normalizeDigitGlyphs(value).replaceAll('٫', '.').replaceAll('٬', '')
      .replaceAll(',', '').replaceAll('،', '').replaceAll(RegExp(r'[\s\u00A0\u202F]'), '');
}
