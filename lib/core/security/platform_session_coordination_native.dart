import 'package:providentia/features/identity/application/identity_ports.dart';

/// Native processes already serialize session mutations in one manager.
final class PlatformSessionCoordination extends LocalSessionCoordination {
  const PlatformSessionCoordination();
}
