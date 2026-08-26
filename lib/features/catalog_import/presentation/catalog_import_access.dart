import 'package:flutter/foundation.dart';
import 'package:providentia/features/homes/domain/home_models.dart';

/// Spreadsheet import is available only through the selected home's exact
/// catalog-import permission; the backend re-checks every call.
bool mayImportCatalogSpreadsheet(Set<String> permissions) =>
    permissions.contains(HomePermissions.catalogImport);

/// The workflow is a wide, file-system-driven mapping table and is offered
/// on desktop and web form factors only.
bool isSpreadsheetImportFormFactor({
  required bool isWeb,
  required TargetPlatform platform,
}) =>
    isWeb ||
    platform == TargetPlatform.windows ||
    platform == TargetPlatform.macOS ||
    platform == TargetPlatform.linux;

/// [isSpreadsheetImportFormFactor] for the running platform.
bool spreadsheetImportFormFactorSupported() => isSpreadsheetImportFormFactor(
  isWeb: kIsWeb,
  platform: defaultTargetPlatform,
);
