import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/app/configuration_required_app.dart';

void main() {
  testWidgets('invalid API connection configuration renders a usable shell', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ConfigurationRequiredApp(
        safeMessage: 'PROVIDENTIA_API_BASE_URL must be an absolute URI.',
      ),
    );

    expect(
      find.byKey(const Key('configuration-required-shell')),
      findsOneWidget,
    );
    expect(find.text('API connection setup required'), findsOneWidget);
    expect(find.textContaining('PROVIDENTIA_API_BASE_URL'), findsNWidgets(2));
    expect(find.textContaining('authenticated home'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
