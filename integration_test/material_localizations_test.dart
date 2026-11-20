import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:khadamat_fanni_hosein/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Persian dashboard starts without missing MaterialLocalizations',
    (tester) async {
      await app.DemoStore.init();

      await tester.pumpWidget(const app.HoseinApp());
      await tester.pump(const Duration(seconds: 2));

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('home-brand-title')),
        findsOneWidget,
      );
    },
  );
}
