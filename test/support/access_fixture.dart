import 'package:providentia/features/homes/domain/home_models.dart';
import 'package:providentia/features/profile/profile_port.dart';

Set<String> fixtureHomePermissions(HomeRole role) {
  if (role == HomeRole.owner)
    return <String>{...HomePermissions.owner, 'ai.credentials.use'};
  if (role == HomeRole.manager)
    return <String>{...HomePermissions.owner, 'ai.credentials.use'}
      ..removeAll(<String>{
        'ownership.transfer',
        'permissions.manage',
        'data.erasure',
        'billing.manage',
      });
  final permissions = <String>{
    'home.read',
    'members.read',
    'inventory.read',
    'purchases.read',
    'shopping.read',
    'ai.read',
    'reports.read',
  };
  if (role == HomeRole.member)
    permissions.addAll(<String>{
      'inventory.write',
      'purchases.write',
      'shopping.write',
      'ai.use',
      'ai.credentials.use',
    });
  return permissions;
}

Map<String, Object?> fixtureHomeAccess() => <String, Object?>{
  'features': <String, bool>{
    for (final permission in <String>{
      ...HomePermissions.owner,
      'ai.credentials.use',
    })
      permission: true,
  },
  'delegablePermissions': <String>[
    ...HomePermissions.owner,
    'ai.credentials.use',
  ],
  'limits': <String, int>{
    'members.total': -1,
    'members.owners': -1,
    'members.managers': -1,
    'members.members': -1,
  },
};

final class FixtureProfilePort implements ProfilePort {
  final List<String> operations = <String>[];
  @override
  Future<Object?> call(
    String operation, {
    Map<String, String>? path,
    Map<String, String>? query,
    Map<String, Object?>? body,
  }) async {
    operations.add(operation);
    if (operation == 'requestSecurityCode')
      return <String, Object?>{
        'challengeId': '0198a0b1-c2d3-7e4f-8123-456789abcdef',
        'bindingToken': 'test-binding-0000000000000000000000000000000',
        'expiresAt': DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 10))
            .toIso8601String(),
        'resendAfterSeconds': 60,
      };
    if (operation == 'verifySecurityCode')
      return <String, Object?>{
        'proofToken': 'step-up-token-00000000000000000000000000000000',
        'action': 'ownership-transfer',
      };
    return <String, Object?>{};
  }
}
