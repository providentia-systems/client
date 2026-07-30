import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:providentia/app/app_controller.dart';
import 'package:providentia/app/configuration_required_app.dart';
import 'package:providentia/app/providentia_app.dart';
import 'package:providentia/core/config/runtime_configuration.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/drift_local_sync_repository.dart';
import 'package:providentia/core/networking/api_client_factory.dart';
import 'package:providentia/core/networking/generated_api_connectivity_probe.dart';
import 'package:providentia/core/synchronization/generated_sync_gateway.dart';
import 'package:providentia/core/synchronization/sync_coordinator.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  late final RuntimeConfiguration configuration;
  late final String bootstrapHomeId;
  try {
    configuration = RuntimeConfiguration.fromEnvironment();
    bootstrapHomeId = configuration.requireBootstrapHomeId();
  } on FormatException catch (error) {
    runApp(ConfigurationRequiredApp(safeMessage: error.message.toString()));
    return;
  }
  final database = AppDatabase.defaults();
  final repository = DriftLocalSyncRepository(database);
  final apiClient = const ApiClientFactory().create(
    configuration: configuration,
  );
  final synchronization = SyncCoordinator(
    local: repository,
    remote: GeneratedSyncGateway(apiClient),
    connectivity: GeneratedApiConnectivityProbe(apiClient),
  );
  final controller = AppController(
    synchronization: synchronization,
    // This development value only chooses the client partition. The backend
    // independently resolves membership and authorization from the session.
    activeHomeId: bootstrapHomeId,
  );

  runApp(
    ProvidentiaApp(
      controller: controller,
      onDispose: () {
        apiClient.close();
        unawaited(database.close());
      },
    ),
  );
}
