import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:providentia/core/security/origin_lock.dart';
import 'package:providentia/core/security/platform_origin_lock.dart';

/// Stable, non-secret device identifier used to bind revocable sessions.
final class DeviceIdentityStore {
  DeviceIdentityStore({
    FlutterSecureStorage? storage,
    this.originLock = const PlatformOriginLock(),
  }) : _storage = storage ?? const FlutterSecureStorage();

  static const String _key = 'providentia.device-id.v1';
  final FlutterSecureStorage _storage;
  final OriginLock originLock;

  Future<String> getOrCreate() => originLock.runExclusive<String>(
    _getOrCreateInsideLock,
    waitTimeout: const Duration(seconds: 15),
  );

  Future<String> _getOrCreateInsideLock() async {
    final existing = await _storage.read(key: _key);
    if (existing != null && _uuid.hasMatch(existing)) {
      return existing;
    }
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    final created =
        '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
    await _storage.write(key: _key, value: created);
    final canonical = await _storage.read(key: _key);
    if (canonical == null || !_uuid.hasMatch(canonical)) {
      throw StateError('The device identity could not be persisted safely.');
    }
    return canonical;
  }
}

final RegExp _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
