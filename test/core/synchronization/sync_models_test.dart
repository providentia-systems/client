import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/synchronization/sync_models.dart';

void main() {
  test('push result copies and freezes its remote representation', () {
    final source = <String, Object?>{'revision': 4};
    final result = PushOperationResult(
      operationId: 'operation-1',
      kind: PushResultKind.conflict,
      remotePayload: source,
    );

    source['revision'] = 5;

    expect(result.remotePayload, <String, Object?>{'revision': 4});
    expect(
      () => result.remotePayload!['revision'] = 6,
      throwsA(isA<UnsupportedError>()),
    );
  });
}
