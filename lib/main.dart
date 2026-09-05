import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:providentia/app/configuration_required_app.dart';
import 'package:providentia/app/production_bootstrap_app.dart';
import 'package:providentia/core/config/runtime_configuration.dart';

void main(List<String> launchArguments) {
  WidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();

  late final RuntimeConfiguration configuration;
  try {
    configuration = RuntimeConfiguration.fromEnvironment();
  } on FormatException catch (error) {
    runApp(ConfigurationRequiredApp(safeMessage: error.message.toString()));
    return;
  }

  runApp(ProductionBootstrapApp(configuration: configuration));
}
