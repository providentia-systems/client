import 'package:providentia/features/ai_integration/application/ai_ports.dart';
import 'package:providentia/features/ai_integration/infrastructure/api17_ai_gateway.dart'
    show PreparedMediaByteReader;
import 'package:providentia/features/ai_integration/infrastructure/strict_local_native_transport.dart';
import 'package:providentia/features/ai_integration/infrastructure/strict_local_provider_gateway.dart';

/// Narrow hook for the app shell. Web and unverified transports intentionally
/// receive a deny-by-default gateway rather than silently weakening isolation.
abstract final class StrictLocalAiComposition {
  static AiProviderGateway create({
    required StrictLocalNameResolver resolver,
    required PreparedMediaByteReader mediaReader,
    StrictLocalHttpTransport transport = const DeniedStrictLocalHttpTransport(),
    StrictLocalCredentialReader credentialReader =
        const DisabledStrictLocalCredentialReader(),
  }) => StrictLocalProviderGateway(
    resolver: resolver,
    transport: transport,
    mediaReader: mediaReader,
    credentialReader: credentialReader,
  );

  /// Enables the verified dart:io transport on native builds. Conditional
  /// stubs keep web deny-by-default.
  static AiProviderGateway createForCurrentPlatform({
    required PreparedMediaByteReader mediaReader,
    StrictLocalCredentialReader credentialReader =
        const DisabledStrictLocalCredentialReader(),
  }) => create(
    resolver: const NativeStrictLocalNameResolver(),
    transport: const NativeStrictLocalHttpTransport(),
    mediaReader: mediaReader,
    credentialReader: credentialReader,
  );
}
