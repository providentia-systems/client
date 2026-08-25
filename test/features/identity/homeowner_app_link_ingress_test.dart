import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/identity/infrastructure/homeowner_app_link_ingress.dart';

void main() {
  const requestId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  const token = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN_1234567890';
  final customBase = Uri.parse('providentia://login-link/homeowner');
  final customLink = Uri.parse(
    'providentia://login-link/homeowner#requestId=$requestId&approval=$token',
  );

  test('cold-start envelope consumes a matching command-line link once', () {
    final envelope = resolveInitialHomeownerAppLink(
      launchArguments: <String>['--verbose', customLink.toString()],
      defaultRouteName: '/',
      browserLocation: Uri.parse('https://app.example.test/'),
      isWeb: false,
      expectedBaseUri: customBase,
    );

    expect(envelope?.take(), customLink);
    expect(envelope?.take(), isNull);
  });

  test('web bootstrap accepts only its configured HTTPS origin and path', () {
    final webBase = Uri.parse('https://app.example.test/homeowner');
    final webLink = webBase.replace(
      fragment: 'requestId=$requestId&approval=$token',
    );

    expect(
      resolveInitialHomeownerAppLink(
        launchArguments: const <String>[],
        defaultRouteName: '/',
        browserLocation: webLink,
        isWeb: true,
        expectedBaseUri: webBase,
      )?.take(),
      webLink,
    );
    expect(
      resolveInitialHomeownerAppLink(
        launchArguments: const <String>[],
        defaultRouteName: '/',
        browserLocation: Uri.parse(
          'https://admin.example.test/homeowner#requestId=$requestId&approval=$token',
        ),
        isWeb: true,
        expectedBaseUri: webBase,
      ),
      isNull,
    );
  });

  test('admin, query-secret, and ordinary routes are never consumed', () {
    for (final value in <String>[
      'providentia://login-link/admin#requestId=$requestId&approval=$token',
      'providentia://login-link/homeowner?approval=$token#requestId=$requestId',
      '/inventory',
    ]) {
      expect(
        resolveInitialHomeownerAppLink(
          launchArguments: <String>[value],
          defaultRouteName: '/',
          browserLocation: Uri.parse('https://app.example.test/'),
          isWeb: false,
          expectedBaseUri: customBase,
        ),
        isNull,
      );
    }
  });
}
