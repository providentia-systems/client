import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/catalog_import/presentation/catalog_import_access.dart';
import 'package:providentia/features/homes/domain/home_models.dart';

void main() {
  test('spreadsheet import requires the exact catalog-import permission', () {
    expect(
      mayImportCatalogSpreadsheet(const <String>{
        HomePermissions.catalogImport,
      }),
      isTrue,
    );
    expect(mayImportCatalogSpreadsheet(HomePermissions.owner), isTrue);
    expect(
      mayImportCatalogSpreadsheet(const <String>{
        HomePermissions.catalogContribute,
        HomePermissions.inventoryWrite,
      }),
      isFalse,
    );
    expect(mayImportCatalogSpreadsheet(const <String>{}), isFalse);
  });

  test('the workflow is offered on desktop and web form factors only', () {
    for (final desktop in <TargetPlatform>[
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    ]) {
      expect(
        isSpreadsheetImportFormFactor(isWeb: false, platform: desktop),
        isTrue,
      );
    }
    for (final mobile in <TargetPlatform>[
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.fuchsia,
    ]) {
      expect(
        isSpreadsheetImportFormFactor(isWeb: false, platform: mobile),
        isFalse,
      );
      expect(
        isSpreadsheetImportFormFactor(isWeb: true, platform: mobile),
        isTrue,
        reason: 'authenticated web is a supported import surface',
      );
    }
  });

  test('the runtime helper follows the overridable default platform', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(spreadsheetImportFormFactorSupported(), isTrue);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(spreadsheetImportFormFactorSupported(), kIsWeb);
  });
}
