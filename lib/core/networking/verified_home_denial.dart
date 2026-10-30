import 'package:providentia_api_client/providentia_api_client.dart';

/// Only an explicit membership denial authorizes the home revocation boundary.
/// Resource, provider, role and deployment failures do not establish revocation.
bool isVerifiedHomeAccessDenial(ProvidentiaApiException error) =>
    (error.statusCode == 403 || error.statusCode == 404) &&
    error.problem.type ==
        'https://providentia.invalid/problems/sync_home_access_denied';
