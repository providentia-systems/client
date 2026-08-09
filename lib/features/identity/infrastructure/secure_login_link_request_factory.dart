import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:providentia/features/identity/domain/identity_models.dart';

final class SecureLoginLinkRequestFactory implements LoginLinkRequestFactory {
  SecureLoginLinkRequestFactory({Random? random})
    : _random = random ?? Random.secure();

  final Random _random;

  @override
  PendingLoginLinkRequest create({
    required String email,
    required DateTime createdAt,
    required DateTime expiresAt,
    required Duration pollInterval,
  }) {
    return PendingLoginLinkRequest(
      requestId: _uuid(),
      email: normalizedEmail(email),
      pollToken: _secret(32),
      codeVerifier: _secret(64),
      state: _secret(32),
      createdAt: createdAt.toUtc(),
      expiresAt: expiresAt.toUtc(),
      pollInterval: pollInterval,
    );
  }

  @override
  String challenge(String secret) {
    return base64Url
        .encode(sha256.convert(utf8.encode(secret)).bytes)
        .replaceAll('=', '');
  }

  String _secret(int length) {
    final bytes = List<int>.generate(length, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  String _uuid() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
