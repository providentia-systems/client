/// Non-secret build identity, compiled into the running application.
/// Unknown development values deliberately cannot satisfy installed acceptance.
final class ClientBuildIdentity {
  const ClientBuildIdentity({
    required this.clientRevision,
    required this.contractVersion,
    required this.contractSha256,
  });

  const ClientBuildIdentity.fromEnvironment()
    : clientRevision = const String.fromEnvironment(
        'PROVIDENTIA_BUILD_REVISION',
      ),
      contractVersion = const String.fromEnvironment(
        'PROVIDENTIA_CONTRACT_VERSION',
      ),
      contractSha256 = const String.fromEnvironment(
        'PROVIDENTIA_CONTRACT_SHA256',
      );

  final String clientRevision;
  final String contractVersion;
  final String contractSha256;

  bool get isVerifiable =>
      RegExp(r'^[0-9a-f]{40}$').hasMatch(clientRevision) &&
      RegExp(r'^[0-9a-f]{64}$').hasMatch(contractSha256) &&
      contractVersion.isNotEmpty;

  Map<String, Object> toJson() => {
    'schemaVersion': 1,
    'clientRevision': clientRevision,
    'contractVersion': contractVersion,
    'contractSha256': contractSha256,
  };
}
