/// Parses Persian and Arabic numeric input consistently across the app.
class LocalizedNumber {
  const LocalizedNumber._();

  static String normalize(String value) {
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    var result = value.trim();
    for (var i = 0; i < 10; i++) {
      result = result.replaceAll(persian[i], '$i');
      result = result.replaceAll(arabic[i], '$i');
    }
    return result
        // Arabic text may include directional marks around a leading sign.
        // Normalize the Unicode minus to the ASCII sign understood by Dart.
        .replaceAll('\u061C', '')
        .replaceAll('\u200E', '')
        .replaceAll('\u200F', '')
        .replaceAll('−', '-')
        .replaceAll(',', '')
        .replaceAll('٬', '')
        .replaceAll('٫', '.')
        .replaceAll('،', '')
        .replaceAll(RegExp(r'[\\s\\u00A0\\u202F]'), '');
  }

  static int? tryParseInt(String value) =>
      int.tryParse(normalize(value));

  static double? tryParseDouble(String value) =>
      double.tryParse(normalize(value));

  static int parseIntOrZero(String value) => tryParseInt(value) ?? 0;

  static double parseDoubleOrZero(String value) =>
      tryParseDouble(value) ?? 0;
}
