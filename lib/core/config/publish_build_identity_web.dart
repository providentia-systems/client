import 'dart:js_interop';

import 'package:providentia/core/config/client_build_identity.dart';

@JS('globalThis.providentiaBuildIdentity')
external set _runningBuildIdentity(JSObject identity);

void publishBuildIdentity([
  ClientBuildIdentity identity = const ClientBuildIdentity.fromEnvironment(),
]) {
  _runningBuildIdentity = identity.toJson().jsify()! as JSObject;
}
