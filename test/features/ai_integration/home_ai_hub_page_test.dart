import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/ai_integration/presentation/home_ai_hub_page.dart';

void main() {
  testWidgets('hub routes to server and local settings explicitly', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeAiHubPage(
          mayManageLocalProfiles: true,
          serverProxyPageBuilder: (_) =>
              const Scaffold(body: Text('server destination')),
          strictLocalSettingsPageBuilder: (_) =>
              const Scaffold(body: Text('local destination')),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('home-ai-strict-local')));
    await tester.pumpAndSettle();
    expect(find.text('local destination'), findsOne);
  });

  testWidgets('local management is disabled without permission', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeAiHubPage(
          mayManageLocalProfiles: false,
          serverProxyPageBuilder: (_) => const SizedBox.shrink(),
          strictLocalSettingsPageBuilder: (_) => const SizedBox.shrink(),
        ),
      ),
    );

    final tile = tester.widget<ListTile>(
      find.byKey(const Key('home-ai-strict-local')),
    );
    expect(tile.onTap, isNull);
  });
}
