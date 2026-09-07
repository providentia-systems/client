import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/profile/email_confirmation_dialog.dart';
import 'package:providentia/features/profile/profile_port.dart';

void main() {
  testWidgets(
    'security confirmation requires eight digits and keeps the proof bound to its challenge',
    (tester) async {
      final port = _ConfirmationPort();
      ProfileRecord? result;
      await _open(
        tester,
        port,
        action: 'ownership-transfer',
        onResult: (value) => result = value,
      );
      expect(port.calls.single.operation, 'requestSecurityCode');
      expect(port.calls.single.body, <String, Object?>{
        'action': 'ownership-transfer',
      });
      final field = find.widgetWithText(TextField, 'Eight-digit code');
      expect(tester.widget<TextField>(field).controller?.text, isEmpty);
      await tester.enterText(field, '1234');
      await tester.tap(find.widgetWithText(FilledButton, 'Verify code'));
      await tester.pump();
      expect(find.text('Enter the eight-digit code.'), findsOneWidget);
      expect(port.calls, hasLength(1));
      await tester.enterText(field, '87654321');
      await tester.tap(find.widgetWithText(FilledButton, 'Verify code'));
      await tester.pumpAndSettle();
      expect(port.calls.last.operation, 'verifySecurityCode');
      expect(port.calls.last.body, <String, Object?>{
        'challengeId': 'challenge-1',
        'bindingToken': 'private-binding-token',
        'code': '87654321',
      });
      expect(result?['proofToken'], 'one-time-action-proof');
    },
  );

  testWidgets(
    'new account email is submitted only to the alias verification operations',
    (tester) async {
      final port = _ConfirmationPort();
      await _open(tester, port);
      expect(port.calls, isEmpty);
      await tester.enterText(
        find.widgetWithText(TextField, 'New email address'),
        ' next@example.test ',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Send code'));
      await tester.pumpAndSettle();
      expect(port.calls.single.operation, 'requestAccountEmailCode');
      expect(port.calls.single.body, <String, Object?>{
        'email': 'next@example.test',
      });
      final emailField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'New email address'),
      );
      expect(emailField.enabled, isFalse);
      expect(
        tester
            .widget<TextButton>(
              find.ancestor(
                of: find.textContaining('Resend in'),
                matching: find.byType(TextButton),
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Eight-digit code'),
        '12345678',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Verify code'));
      await tester.pumpAndSettle();
      expect(port.calls.last.operation, 'verifyAccountEmail');
      expect(port.calls.last.body?['code'], '12345678');
    },
  );

  testWidgets('cancelling a requested security code grants no proof', (
    tester,
  ) async {
    final port = _ConfirmationPort();
    ProfileRecord? result;
    var returned = false;
    await _open(
      tester,
      port,
      action: 'email-remove',
      onResult: (value) {
        result = value;
        returned = true;
      },
    );
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(returned, isTrue);
    expect(result, isNull);
    expect(port.calls.map((call) => call.operation), <String>[
      'requestSecurityCode',
    ]);
  });

  testWidgets(
    'rejected code preserves the dialog and does not expose a proof',
    (tester) async {
      final port = _ConfirmationPort(rejectVerification: true);
      ProfileRecord? result;
      await _open(
        tester,
        port,
        action: 'email-remove',
        onResult: (value) => result = value,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Eight-digit code'),
        '12345678',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Verify code'));
      await tester.pumpAndSettle();
      expect(find.text('This code is incorrect or expired.'), findsOneWidget);
      expect(
        find.widgetWithText(TextField, 'Eight-digit code'),
        findsOneWidget,
      );
      expect(result, isNull);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
    },
  );
}

Future<void> _open(
  WidgetTester tester,
  ProfilePort port, {
  String? action,
  void Function(ProfileRecord?)? onResult,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () async {
              final result = await confirmAccountEmail(
                context,
                port,
                action: action,
              );
              onResult?.call(result);
            },
            child: const Text('Open confirmation'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open confirmation'));
  await tester.pumpAndSettle();
}

final class _ConfirmationPort implements ProfilePort {
  _ConfirmationPort({this.rejectVerification = false});
  final bool rejectVerification;
  final List<({String operation, Map<String, Object?>? body})> calls = [];
  @override
  Future<Object?> call(
    String operation, {
    Map<String, String>? path,
    Map<String, String>? query,
    Map<String, Object?>? body,
  }) async {
    calls.add((operation: operation, body: body));
    if (operation.startsWith('request')) {
      return <String, Object?>{
        'challengeId': 'challenge-1',
        'bindingToken': 'private-binding-token',
        'expiresAt': DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 10))
            .toIso8601String(),
        'resendAfterSeconds': 60,
      };
    }
    if (rejectVerification) {
      throw const ProfileFailure('This code is incorrect or expired.');
    }
    return <String, Object?>{'proofToken': 'one-time-action-proof'};
  }
}
