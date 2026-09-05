import 'package:providentia_api_client/providentia_api_client.dart';

import 'profile_port.dart';

final class GeneratedProfilePort implements ProfilePort {
  const GeneratedProfilePort(this.api);
  final ProvidentiaApiClient api;
  @override
  Future<Object?> call(
    String operation, {
    Map<String, String>? path,
    Map<String, String>? query,
    Map<String, Object?>? body,
  }) async {
    try {
      return (await api.invokeOperation(
        operationId: operation,
        pathParameters: path ?? const <String, String>{},
        query: query,
        body: body,
      )).body;
    } on ProvidentiaApiException catch (error) {
      throw ProfileFailure(error.problem.detail ?? error.problem.title);
    }
  }
}
