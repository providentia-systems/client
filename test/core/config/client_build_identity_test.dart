import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/config/client_build_identity.dart';
import 'package:providentia/core/config/publish_build_identity.dart';

void main() {
  test('unconfigured development build cannot claim an installed source', () {
    const identity = ClientBuildIdentity.fromEnvironment();
    expect(identity.isVerifiable, isFalse);
    expect(identity.toJson()['clientRevision'], isEmpty);
    publishBuildIdentity(identity);
  });

  test(
    'build identity contains only compiled source and contract metadata',
    () {
      final identity = ClientBuildIdentity(
        clientRevision: 'a' * 40,
        contractVersion: '2.4.0',
        contractSha256: 'b' * 64,
      );
      expect(identity.isVerifiable, isTrue);
      expect(identity.toJson(), {
        'schemaVersion': 1,
        'clientRevision': 'a' * 40,
        'contractVersion': '2.4.0',
        'contractSha256': 'b' * 64,
      });
      expect(
        const ClientBuildIdentity(
          clientRevision: 'main',
          contractVersion: '2.4.0',
          contractSha256: 'unknown',
        ).isVerifiable,
        isFalse,
      );
    },
  );
}
