import 'localized_number.dart';

/// Detects likely duplicate inventory items before they are added.
class ProductDuplicateChecker {
  const ProductDuplicateChecker._();

  static String normalize(String? value) {
    return LocalizedNumber.normalize(value ?? '')
        .toLowerCase()
        .replaceAll('ي', 'ی')
        .replaceAll('ك', 'ک');
  }

  /// A matching non-empty item code is a duplicate. Otherwise, name,
  /// main group and subgroup must all match. Quantity and prices are
  /// deliberately ignored because they describe stock/value, not identity.
  static List<Map<String, String>> findDuplicates(
    Iterable<Map<String, String>> existing,
    Map<String, String> candidate,
  ) {
    final candidateCode = normalize(candidate['کد کالا']);
    final candidateName = normalize(candidate['نام کالا']);
    if (candidateCode.isEmpty && candidateName.isEmpty) {
      return const [];
    }

    return existing.where((item) {
      final existingCode = normalize(item['کد کالا']);
      if (candidateCode.isNotEmpty && existingCode.isNotEmpty) {
        return candidateCode == existingCode;
      }

      if (candidateName.isEmpty ||
          candidateName != normalize(item['نام کالا'])) {
        return false;
      }

      return normalize(candidate['گروه اصلی']) ==
              normalize(item['گروه اصلی']) &&
          normalize(candidate['زیرگروه']) ==
              normalize(item['زیرگروه']);
    }).toList(growable: false);
  }
}
