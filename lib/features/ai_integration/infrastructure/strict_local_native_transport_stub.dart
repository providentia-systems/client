import 'package:providentia/features/ai_integration/infrastructure/strict_local_provider_gateway.dart';

final class NativeStrictLocalNameResolver implements StrictLocalNameResolver {
  const NativeStrictLocalNameResolver();

  @override
  Future<List<String>> resolve(String host, {required Duration timeout}) =>
      throw const StrictLocalBoundaryException(
        code: 'native_dns_unavailable',
        safeMessage:
            'Strict local DNS verification is unavailable on this platform.',
      );
}

final class NativeStrictLocalHttpTransport implements StrictLocalHttpTransport {
  const NativeStrictLocalHttpTransport();

  @override
  bool get blocksRedirects => false;

  @override
  bool get exposesConnectedPeerAddress => false;

  @override
  Future<StrictLocalTransportResponse> send(
    StrictLocalTransportRequest request,
  ) => throw const StrictLocalBoundaryException(
    code: 'native_transport_unavailable',
    safeMessage: 'Strict local AI is unavailable on this platform.',
  );
}
