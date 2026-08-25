import 'package:providentia/features/identity/domain/login_link_approval_models.dart';

/// A single-use cold-start link envelope. Taking the URI clears the only
/// launch-owned reference before the application begins network review.
final class InitialHomeownerAppLink {
  InitialHomeownerAppLink(Uri uri) : _uri = uri;

  Uri? _uri;

  Uri? take() {
    final uri = _uri;
    _uri = null;
    return uri;
  }
}

InitialHomeownerAppLink? resolveInitialHomeownerAppLink({
  required List<String> launchArguments,
  required String defaultRouteName,
  required Uri browserLocation,
  required bool isWeb,
  required Uri expectedBaseUri,
}) {
  final candidates = <String>[
    if (isWeb) browserLocation.toString(),
    ...launchArguments,
    if (defaultRouteName != '/') defaultRouteName,
  ];
  for (final candidate in candidates) {
    final uri = Uri.tryParse(candidate);
    if (uri != null && isHomeownerLoginLink(uri, expectedBaseUri)) {
      return InitialHomeownerAppLink(uri);
    }
  }
  return null;
}
