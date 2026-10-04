import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:providentia/features/homes/domain/home_models.dart';
import 'package:providentia/features/identity/application/offline_session_store.dart';
import 'package:providentia/features/identity/domain/identity_models.dart';

/// Origin-bound native local-access lease. Browser storage never authorizes
/// offline startup. This cache contains no access or refresh credentials.
final class PlatformOfflineAccessStore implements OfflineSessionStore {
  PlatformOfflineAccessStore({
    required Uri origin,
    FlutterSecureStorage? storage,
    this.enabled = !kIsWeb,
    DateTime Function()? clock,
  }) : _storage =
           storage ??
           const FlutterSecureStorage(
             aOptions: AndroidOptions(resetOnError: false),
             iOptions: IOSOptions(
               accessibility: KeychainAccessibility.unlocked_this_device,
             ),
             mOptions: MacOsOptions(
               accessibility: KeychainAccessibility.unlocked_this_device,
             ),
           ),
       _clock = clock ?? DateTime.now,
       _key =
           'providentia.offline-access.v1.${sha256.convert(utf8.encode(origin.origin))}';

  final FlutterSecureStorage _storage;
  final bool enabled;
  final DateTime Function() _clock;
  final String _key;
  Future<void> _tail = Future<void>.value();

  static const Set<String> localPermissions = <String>{
    HomePermissions.homeRead,
    HomePermissions.inventoryRead,
    HomePermissions.inventoryWrite,
    HomePermissions.inventoryManage,
    HomePermissions.purchasesRead,
    HomePermissions.purchasesWrite,
    HomePermissions.shoppingRead,
    HomePermissions.shoppingWrite,
    HomePermissions.shoppingManage,
  };

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        result.complete(await action());
      } on Object catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  Future<Map<String, Object?>?> _load() async {
    if (!enabled) return null;
    final text = await _storage.read(key: _key);
    if (text == null) return null;
    final value = _object(jsonDecode(text));
    if (value['version'] != 1) {
      throw const FormatException('Invalid cache version.');
    }
    return value;
  }

  Future<void> _save(Map<String, Object?> value) =>
      _storage.write(key: _key, value: jsonEncode(value));

  @override
  Future<OfflineSessionLease?> read() => _serial(() async {
    final value = await _load();
    return value == null ? null : _decodeLease(_object(value['identity']));
  });

  @override
  Future<void> write(OfflineSessionLease lease) => _serial(() async {
    if (!enabled) return;
    Map<String, Object?>? previous;
    try {
      previous = await _load();
    } on FormatException {
      /* replace invalid cache */
    }
    final old = previous == null
        ? null
        : _decodeLease(_object(previous['identity']));
    await _save(<String, Object?>{
      'version': 1,
      'identity': _encodeLease(lease),
      if (old != null &&
          _sameSession(old.session, lease.session) &&
          lease.user.activeHomeId == lease.session.activeHomeId &&
          lease.user.homes.any((home) => home.id == lease.session.activeHomeId))
        'home': previous!['home'],
    });
  });

  @override
  Future<void> clear() => _serial(() async {
    if (enabled) await _storage.delete(key: _key);
  });

  Future<void> rememberHome(SessionMetadata session, HomeSummary home) =>
      _serial(() async {
        final value = await _load();
        if (value == null) return;
        final lease = _decodeLease(_object(value['identity']));
        if (!_sameSession(lease.session, session) ||
            lease.session.activeHomeId != home.id ||
            !lease.user.homes.any((entry) => entry.id == home.id)) {
          return;
        }
        final now = _clock().toUtc();
        value['home'] = <String, Object?>{
          'verifiedAt': now.toIso8601String(),
          'id': home.id,
          'name': home.name,
          'locale': home.locale,
          'currency': home.currency,
          'timezone': home.timezone,
          'role': home.role.name,
          'revision': home.revision,
          'permissions': home.effectivePermissions.toList()..sort(),
        };
        await _save(value);
      });

  Future<HomeSummary?> readHome(
    SessionMetadata session,
    String homeId,
  ) => _serial(() async {
    final value = await _load();
    if (value == null || value['home'] == null) return null;
    final lease = _decodeLease(_object(value['identity']));
    final now = _clock().toUtc();
    if (!_sameSession(lease.session, session) ||
        lease.user.userId != session.userId ||
        lease.user.activeHomeId != homeId ||
        lease.user.currentSession.activeHomeId != homeId ||
        !lease.user.homes.any((home) => home.id == homeId) ||
        lease.session.activeHomeId != homeId ||
        !lease.expiresAt.isAfter(now) ||
        session.isExpiredAt(now) ||
        now.isBefore(lease.lastObservedAt) ||
        now.isBefore(lease.verifiedAt)) {
      return null;
    }
    final home = _object(value['home']);
    final verifiedAt = DateTime.parse(_string(home, 'verifiedAt')).toUtc();
    if (home['id'] != homeId ||
        now.isBefore(verifiedAt) ||
        now.difference(verifiedAt) >= const Duration(hours: 24)) {
      return null;
    }
    final permissions = (home['permissions'] as List<Object?>)
        .cast<String>()
        .toSet();
    // Authority management, export, contributions, AI, and billing need an
    // online authority check. Only already-granted local workspace operations
    // remain available, and the server rechecks them during synchronization.
    return HomeSummary(
      id: _string(home, 'id'),
      name: _string(home, 'name'),
      locale: _string(home, 'locale'),
      currency: _string(home, 'currency'),
      timezone: _string(home, 'timezone'),
      role: HomeRole.values.byName(_string(home, 'role')),
      revision: home['revision'] as int,
      effectivePermissions: permissions.intersection(localPermissions),
    );
  });

  Future<void> revokeHome(String homeId) => _serial(() async {
    final value = await _load();
    if (value == null) return;
    if (value['home'] case final Map<String, Object?> home
        when home['id'] == homeId) {
      value.remove('home');
      await _save(value);
    }
  });
}

bool _sameSession(SessionMetadata left, SessionMetadata right) =>
    left.sessionId == right.sessionId &&
    left.userId == right.userId &&
    left.deviceId == right.deviceId &&
    left.installationId == right.installationId &&
    left.transport == right.transport;

Map<String, Object?> _encodeLease(
  OfflineSessionLease lease,
) => <String, Object?>{
  'verifiedAt': lease.verifiedAt.toIso8601String(),
  'lastObservedAt': lease.lastObservedAt.toIso8601String(),
  'expiresAt': lease.expiresAt.toIso8601String(),
  'session': <String, Object?>{
    'sessionId': lease.session.sessionId,
    'userId': lease.session.userId,
    'deviceId': lease.session.deviceId,
    'installationId': lease.session.installationId,
    'accessExpiresAt': lease.session.accessExpiresAt.toIso8601String(),
    'refreshExpiresAt': lease.session.refreshExpiresAt?.toIso8601String(),
    'idleExpiresAt': lease.session.idleExpiresAt?.toIso8601String(),
    'refreshIdleSeconds': lease.session.refreshIdleTtl?.inSeconds,
    'activeHomeId': lease.session.activeHomeId,
  },
  'user': <String, Object?>{
    'id': lease.user.userId,
    'email': lease.user.email,
    'onboardingComplete': lease.user.onboardingComplete,
    'activeHomeId': lease.user.activeHomeId,
    'homes': lease.user.homes
        .map(
          (home) => <String, Object?>{
            'id': home.id,
            'name': home.name,
            'role': home.role,
          },
        )
        .toList(),
  },
};

OfflineSessionLease _decodeLease(Map<String, Object?> value) {
  final data = _object(value['session']);
  final user = _object(value['user']);
  DateTime? optionalDate(String key) =>
      data[key] == null ? null : DateTime.parse(_string(data, key)).toUtc();
  final session = SessionMetadata(
    sessionId: _string(data, 'sessionId'),
    deviceId: _string(data, 'deviceId'),
    installationId: _string(data, 'installationId'),
    userId: _string(data, 'userId'),
    accessExpiresAt: DateTime.parse(_string(data, 'accessExpiresAt')).toUtc(),
    refreshExpiresAt: optionalDate('refreshExpiresAt'),
    idleExpiresAt: optionalDate('idleExpiresAt'),
    refreshIdleTtl: data['refreshIdleSeconds'] == null
        ? null
        : Duration(seconds: data['refreshIdleSeconds'] as int),
    transport: ClientSessionTransport.nativeBearer,
    activeHomeId: data['activeHomeId'] as String?,
  );
  final verifiedAt = DateTime.parse(_string(value, 'verifiedAt')).toUtc();
  final currentUser = CurrentUserView(
    userId: _string(user, 'id'),
    email: _string(user, 'email'),
    emailVerified: true,
    homes: (user['homes'] as List<Object?>).map((entry) {
      final home = _object(entry);
      return CurrentUserHomeView(
        id: _string(home, 'id'),
        name: _string(home, 'name'),
        role: _string(home, 'role'),
      );
    }).toList(),
    pendingInvitations: const <CurrentUserInvitationView>[],
    platformRoles: const <PlatformRole>{},
    profile: <String, Object?>{
      'onboardingComplete': user['onboardingComplete'] == true,
    },
    activeHomeId: user['activeHomeId'] as String?,
    currentSession: DeviceSessionView(
      id: session.sessionId,
      deviceId: session.deviceId,
      deviceName: 'Providentia app',
      platform: 'native',
      transport: ClientSessionTransport.nativeBearer,
      current: true,
      createdAt: verifiedAt,
      lastSeenAt: verifiedAt,
      accessExpiresAt: session.accessExpiresAt,
      refreshExpiresAt: session.refreshExpiresAt,
      idleExpiresAt: session.idleExpiresAt,
      activeHomeId: session.activeHomeId,
    ),
  );
  return OfflineSessionLease(
    session: session,
    user: currentUser,
    verifiedAt: verifiedAt,
    lastObservedAt: DateTime.parse(_string(value, 'lastObservedAt')).toUtc(),
    expiresAt: DateTime.parse(_string(value, 'expiresAt')).toUtc(),
  );
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Invalid secure cache.');
  }
  return value;
}

String _string(Map<String, Object?> value, String key) {
  final text = value[key];
  if (text is! String || text.isEmpty) {
    throw const FormatException('Invalid secure cache field.');
  }
  return text;
}
