import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:providentia/app/configuration_required_app.dart';
import 'package:providentia/app/production_bootstrap_app.dart';
import 'package:providentia/core/config/runtime_configuration.dart';
import 'package:providentia/features/identity/infrastructure/browser_fragment_scrubber.dart';
import 'package:providentia/features/identity/infrastructure/homeowner_app_link_ingress.dart';

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

  final initialAppLink = resolveInitialHomeownerAppLink(
    launchArguments: launchArguments,
    defaultRouteName:
        WidgetsBinding.instance.platformDispatcher.defaultRouteName,
    browserLocation: Uri.base,
    isWeb: kIsWeb,
    expectedBaseUri: configuration.homeownerAppLinkBaseUri,
  );
  if (kIsWeb && initialAppLink != null) scrubBrowserFragment();

  runApp(
    ProductionBootstrapApp(
      configuration: configuration,
      initialAppLink: initialAppLink,
    ),
  );
}
