import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production synchronization uses the authenticated session device', () {
    final source = File(
      'lib/app/production_bootstrap_app.dart',
    ).readAsStringSync();
    final start = source.indexOf('return _ConnectedHomeWorkspace(');
    final end = source.indexOf('api: _authorizedApi', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final composition = source.substring(start, end);

    expect(composition, contains('identitySnapshot.session!.deviceId'));
    expect(composition, contains('identitySnapshot.session!.userId'));
    expect(composition, isNot(contains('deviceId: _deviceId')));
  });
}
