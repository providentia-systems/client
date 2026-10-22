import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/presentation/quantity_field.dart';

void main() {
  testWidgets('first pointer focus replaces one and preserves decimal input', (
    tester,
  ) async {
    final controller = TextEditingController(text: '1');
    await _show(tester, controller);
    await tester.tap(find.byType(TextFormField));
    await tester.pump();
    expect(
      controller.selection,
      const TextSelection(baseOffset: 0, extentOffset: 1),
    );
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '4',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );
    await tester.pump();
    expect(controller.text, '4');
    await tester.enterText(find.byType(TextFormField), '2.75');
    expect(controller.text, '2.75');
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('keyboard focus and blur preserve the default without edits', (
    tester,
  ) async {
    final controller = TextEditingController(text: '1');
    await _show(tester, controller);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      controller.selection,
      const TextSelection(baseOffset: 0, extentOffset: 1),
    );
    await tester.tap(find.text('Other control'));
    await tester.pump();
    expect(controller.text, '1');
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets(
    'later focus and taps leave ordinary cursor positioning intact',
    (tester) async {
      final controller = TextEditingController(text: '12.5');
      final focus = FocusNode();
      await _show(tester, controller, focusNode: focus);
      focus.requestFocus();
      await tester.pump();
      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 4),
      );
      controller.selection = const TextSelection.collapsed(offset: 2);
      await tester.pump();
      expect(controller.selection.baseOffset, 2);
      focus.unfocus();
      await tester.pump();
      focus.requestFocus();
      await tester.pump();
      expect(controller.selection, const TextSelection.collapsed(offset: 2));
      await tester.tap(find.byType(TextFormField));
      await tester.pump();
      expect(controller.selection.isCollapsed, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      focus.dispose();
      controller.dispose();
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.android,
      TargetPlatform.linux,
    }),
  );

  testWidgets(
    'a successful draft reset rearms selection without clearing text',
    (tester) async {
      final controller = TextEditingController(text: '1');
      final focus = FocusNode();
      await _show(tester, controller, focusNode: focus, resetToken: 0);
      focus.requestFocus();
      await tester.pump();
      await tester.enterText(find.byType(TextFormField), '4');
      controller.text = '1';
      await _show(tester, controller, focusNode: focus, resetToken: 1);
      await tester.pump();
      expect(controller.text, '1');
      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 1),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      focus.dispose();
      controller.dispose();
    },
  );

  testWidgets('a replacement controller gets its own initial selection', (
    tester,
  ) async {
    final first = TextEditingController(text: '1');
    final replacement = TextEditingController(text: '0.75');
    final focus = FocusNode();
    await _show(tester, first, focusNode: focus);
    focus.requestFocus();
    await tester.pump();
    await _show(tester, replacement, focusNode: focus);
    await tester.pump();
    expect(
      replacement.selection,
      const TextSelection(baseOffset: 0, extentOffset: 4),
    );
    expect(replacement.text, '0.75');
    await tester.pumpWidget(const SizedBox.shrink());
    focus.dispose();
    first.dispose();
    replacement.dispose();
  });
}

Future<void> _show(
  WidgetTester tester,
  TextEditingController controller, {
  FocusNode? focusNode,
  Object? resetToken,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: Column(
        children: <Widget>[
          QuantityField(
            controller: controller,
            focusNode: focusNode,
            resetToken: resetToken,
          ),
          TextButton(
            onPressed: () => FocusManager.instance.primaryFocus?.unfocus(),
            child: const Text('Other control'),
          ),
        ],
      ),
    ),
  ),
);
