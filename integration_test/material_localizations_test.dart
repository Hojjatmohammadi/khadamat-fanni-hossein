import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:khadamat_fanni_hosein/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Persian dashboard starts with MaterialLocalizations available',
    (tester) async {
      await app.DemoStore.init();

      await tester.pumpWidget(const app.HoseinApp());
      await tester.pump(const Duration(seconds: 2));

      expect(tester.takeException(), isNull);

      final homeTitle = find.byKey(const ValueKey('home-brand-title'));
      expect(homeTitle, findsOneWidget);

      final homeContext = tester.element(homeTitle);
      expect(
        Localizations.of<MaterialLocalizations>(
          homeContext,
          MaterialLocalizations,
        ),
        isNotNull,
      );
      expect(
        Localizations.localeOf(homeContext).languageCode,
        'fa',
      );
    },
  );
}
