import '../application/data_export_ports.dart';
import 'platform_data_export_saver_native.dart'
    if (dart.library.js_interop) 'platform_data_export_saver_web.dart'
    as platform;

DataExportSaver createPlatformDataExportSaver() =>
    platform.PlatformDataExportSaver();
