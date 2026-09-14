from pathlib import Path

def edit(path, old, new):
    p=Path(path);s=p.read_text()
    assert s.count(old)==1, (path,old[:70],s.count(old))
    p.write_text(s.replace(old,new))
p='lib/features/ai_integration/domain/ai_transmission_plan.dart'
edit(p,'(id != null && (id is! String || id.isEmpty))',"(id is! String || !RegExp(r'^[A-Za-z0-9-]{1,36}$').hasMatch(id))")
edit(p,'revision < 0 ||','revision < 1 ||')
edit(p,'profileId: id as String?,','profileId: id,')
edit(p,'final String? profileId;','final String profileId;')
p='test/features/ai_integration/server_ai_workspace_controller_test.dart'
edit(p,"expect(find.textContaining('No provider profile'), findsOneWidget);", "expect(find.byKey(const Key('ai-configuration-required')), findsOneWidget);\n        await _captureStep2(tester, 'household-ai-setup-required');\n        await _scrollTo(tester, const Key('ai-add-profile'));\n        expect(find.textContaining('No provider profile'), findsOneWidget);")
edit(p,"""testWidgets('manager controls send exact revisioned write-only requests', (
      tester,
    ) async {
      final repository = _ServerRepository(_workspace());""", """testWidgets('manager controls send exact revisioned write-only requests', (
      tester,
    ) async {
      final repository = _ServerRepository(_workspace(profiles: <AiProviderProfile>[
        serverProvider(ownerScope: AiProfileOwnerScope.home),
      ]));""")
edit(p,"""expect(controller.status, ServerAiWorkspaceStatus.failed);
        expect(controller.safeMessage, contains('active primary provider'));""", """expect(controller.status, ServerAiWorkspaceStatus.ready);
        expect(tester.widget<FilledButton>(find.byKey(const Key('ai-pick-receipt'))).onPressed, isNull);
        // Management selection must not enable a different recipient behind consent.
        await _captureStep2(tester, 'household-ai-recipient-selection-blocked');""")
edit(p,"import 'dart:convert';", "import 'dart:convert';\nimport 'dart:io';\nimport 'dart:ui' as ui;")
edit(p,"import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\nimport 'package:flutter/rendering.dart';")
p=Path(p);s=p.read_text();a=s.index('Future<void> _pumpPage(');b=s.index('Future<void> _scrollTo(',a)
s=s[:a]+"""Future<void> _pumpPage(
  WidgetTester tester,
  ServerAiWorkspaceController controller, {
  AiSingleImagePicker? picker,
  AiPreparedImageReader? readPreparedImage,
  ValueChanged<AiReviewHandoff>? onReviewHandoff,
}) => tester.pumpWidget(
  RepaintBoundary(
    key: const Key('step2-ui-evidence'),
    child: MaterialApp(
      home: ServerAiWorkspacePage(
        key: UniqueKey(),
        controller: controller,
        pickSingleImage: picker ?? (_) async => _asset(),
        readPreparedImage: readPreparedImage ?? (_) async => _transparentPixel,
        onReviewHandoff: onReviewHandoff,
      ),
    ),
  ),
);

Future<void> _captureStep2(WidgetTester tester, String name) async {
  final directory = Platform.environment['PROVIDENTIA_UI_EVIDENCE'];
  if (directory == null) return;
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('step2-ui-evidence')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('UI evidence encoding failed.');
    await Directory(directory).create(recursive: true);
    await File('$directory/$name.png').writeAsBytes(bytes.buffer.asUint8List());
    image.dispose();
  });
}

"""+s[b:];p.write_text(s)
p=Path('test/integration/step_2_configuration_contract_test.dart');s=p.read_text().replace("import 'dart:io';", "import 'dart:io';\n\nimport 'package:providentia/features/ai_integration/domain/ai_transmission_plan.dart';")
s=s.replace('void main() {',"""void main() {
  for (final invalid in <Map<String, Object?>>[
    {'profileId': null, 'revision': 1},
    {'profileId': '', 'revision': 1},
    {'profileId': 'saved-profile', 'revision': 0},
  ]) {
    test('Step 2 rejects unsaved recipient $invalid', () {
      expect(() => AiTransmissionRecipient.fromJson({
        ...invalid, 'provider': 'ollama', 'model': 'synthetic', 'endpoint': null,
      }), throwsFormatException);
    });
  }
""");p.write_text(s)
