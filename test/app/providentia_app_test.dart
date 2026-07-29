import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/app/providentia_app.dart';

void main() {
  testWidgets('foundation shell identifies product and bounded features', (
    tester,
  ) async {
    await tester.pumpWidget(const ProvidentiaApp());

    expect(find.text('Providentia'), findsOneWidget);
    expect(find.text('9 bounded feature areas registered'), findsOneWidget);
  });
}
