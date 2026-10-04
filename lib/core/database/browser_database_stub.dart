import 'package:providentia/core/database/browser_database_contract.dart';

BrowserDatabaseVault createBrowserDatabaseVault() =>
    throw const BrowserDatabaseProtectionException('unsupported_browser');
