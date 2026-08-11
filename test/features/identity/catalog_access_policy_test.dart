import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/homes/domain/home_models.dart';
import 'package:providentia/features/identity/domain/identity_models.dart';
import 'package:providentia/features/identity/presentation/account_access_page.dart';

void main() {
  test('catalog-sharing visibility derives from active-home permissions', () {
    expect(
      mayAccessCatalogSharing(const <String>{
        HomePermissions.catalogConsentManage,
      }),
      isTrue,
    );
    expect(
      mayAccessCatalogSharing(const <String>{
        HomePermissions.catalogContribute,
      }),
      isTrue,
    );
    expect(
      mayAccessCatalogSharing(const <String>{HomePermissions.inventoryWrite}),
      isFalse,
    );
  });

  test('per-item contribution requires catalog and inventory read access', () {
    expect(
      mayContributeCatalogProduct(const <String>{
        HomePermissions.catalogContribute,
        HomePermissions.inventoryRead,
      }),
      isTrue,
    );
    expect(
      mayContributeCatalogProduct(const <String>{
        HomePermissions.catalogContribute,
      }),
      isFalse,
    );
    expect(
      mayContributeCatalogProduct(const <String>{
        HomePermissions.catalogConsentManage,
      }),
      isFalse,
    );
    expect(
      mayContributeCatalogProduct(const <String>{
        HomePermissions.inventoryWrite,
      }),
      isFalse,
    );
  });

  test(
    'catalog administration derives only from current-user platform roles',
    () {
      for (final role in const <PlatformRole>{
        PlatformRole.platformAdministrator,
        PlatformRole.catalogCurator,
        PlatformRole.catalogReviewer,
      }) {
        expect(
          mayAccessCatalogAdministration(<PlatformRole>{role}),
          isTrue,
          reason: role.name,
        );
      }
      expect(
        mayAccessCatalogAdministration(const <PlatformRole>{
          PlatformRole.billingOperator,
        }),
        isFalse,
      );
    },
  );

  test('even all household permissions cannot escalate to moderation', () {
    expect(
      HomePermissions.owner,
      contains(HomePermissions.catalogConsentManage),
    );
    expect(HomePermissions.owner, contains(HomePermissions.catalogContribute));
    expect(mayAccessCatalogAdministration(const <PlatformRole>{}), isFalse);
  });
}
