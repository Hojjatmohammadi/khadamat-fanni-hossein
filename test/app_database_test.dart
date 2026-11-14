import 'package:flutter_test/flutter_test.dart';
import 'package:khadamat_fanni_hosein/data/app_database.dart';

void main() {
  test('newId returns unique UUID-shaped identifiers', () {
    final first = AppDatabase.newId();
    final second = AppDatabase.newId();

    final uuidPattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );

    expect(first, matches(uuidPattern));
    expect(second, matches(uuidPattern));
    expect(first, isNot(equals(second)));
  });
}
