import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/app/configuration_required_app.dart';

void main() {
  testWidgets('missing launch configuration renders a usable shell', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ConfigurationRequiredApp(
        safeMessage: 'Set the development home UUID to continue.',
      ),
    );

    expect(
      find.byKey(const Key('configuration-required-shell')),
      findsOneWidget,
    );
    expect(find.text('Sign-in setup required'), findsOneWidget);
    expect(find.textContaining('development home UUID'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
