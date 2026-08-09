import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:providentia/features/identity/application/identity_ports.dart';
import 'package:providentia/features/identity/domain/identity_models.dart';
import 'package:web/web.dart' as web;

/// Origin-wide cookie session coordination for Flutter web tabs.
///
/// Web Locks prevent refresh-token-family replay. BroadcastChannel propagates
/// the newly rotated CSRF/session metadata so another tab never mutates with a
/// stale header while the HttpOnly cookies have already rotated.
final class PlatformSessionCoordination implements SessionCoordinationPort {
  PlatformSessionCoordination() {
    try {
      final channel = web.BroadcastChannel(_channelName);
      channel.onmessage = ((web.Event event) {
        final data = (event as web.MessageEvent).data;
        if (data == null || !data.typeofEquals('string')) return;
        _consume((data as JSString).toDart);
      }).toJS;
      _channel = channel;
    } on Object {
      // Operations fail closed below with a controlled error on browsers that
      // cannot provide safe cross-tab metadata propagation.
      _channel = null;
    }
  }

  static const String _channelName = 'providentia.web-session.v1';
  static const String _lockName = 'providentia.web-session-cookie-mutation.v1';
  static const String _latestKey = 'providentia.web-session.latest.v1';

  web.BroadcastChannel? _channel;
  final StreamController<CoordinatedSessionUpdate> _updates =
      StreamController<CoordinatedSessionUpdate>.broadcast(sync: true);

  bool _disposed = false;

  @override
  Stream<CoordinatedSessionUpdate> get updates => _updates.stream;

  @override
  Future<T> runExclusive<T>(
    Future<T> Function() action, {
    required Duration lockWaitTimeout,
  }) {
    if (_disposed) {
      return Future<T>.error(
        StateError('Session coordination has been disposed.'),
      );
    }
    if (lockWaitTimeout <= Duration.zero) {
      return Future<T>.error(
        ArgumentError.value(lockWaitTimeout, 'lockWaitTimeout'),
      );
    }
    if (_channel == null) {
      return Future<T>.error(
        UnsupportedError(
          'This browser cannot safely coordinate a session across tabs.',
        ),
      );
    }
    final result = Completer<T>();
    final abortController = web.AbortController();
    final timer = Timer(lockWaitTimeout, () => abortController.abort());

    JSPromise<JSAny?> callback(web.Lock _) =>
        _runLocked(action, result, timer).toJS;

    late final JSPromise<JSAny?> lockRequest;
    try {
      final options = web.LockOptions(
        mode: 'exclusive',
        signal: abortController.signal,
      );
      lockRequest = web.window.navigator.locks.request(
        _lockName,
        options,
        callback.toJS,
      );
    } on Object catch (_, stackTrace) {
      timer.cancel();
      result.completeError(
        UnsupportedError(
          'This browser cannot safely serialize session changes.',
        ),
        stackTrace,
      );
      return result.future;
    }
    unawaited(
      lockRequest.toDart.then<void>(
        (_) {
          if (!result.isCompleted) {
            result.completeError(
              StateError('The web session lock ended without a result.'),
            );
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!result.isCompleted) {
            result.completeError(
              TimeoutException(
                'Another tab is updating the browser session.',
                lockWaitTimeout,
              ),
              stackTrace,
            );
          }
        },
      ),
    );
    return result.future.whenComplete(timer.cancel);
  }

  @override
  Future<CoordinatedSessionUpdate?> readLatest() async {
    if (_disposed) return null;
    final encoded = web.window.localStorage.getItem(_latestKey);
    if (encoded == null) return null;
    try {
      return _decodeUpdate(encoded);
    } on Object {
      const signedOut = '{"type":"signed_out"}';
      try {
        web.window.localStorage.setItem(_latestKey, signedOut);
      } on Object {
        // The caller still receives fail-closed state for this operation.
      }
      return const CoordinatedSessionUpdate.signedOut();
    }
  }

  Future<JSAny?> _runLocked<T>(
    Future<T> Function() action,
    Completer<T> result,
    Timer timer,
  ) async {
    timer.cancel();
    try {
      final value = await action();
      if (!result.isCompleted) result.complete(value);
    } on Object catch (error, stackTrace) {
      if (!result.isCompleted) result.completeError(error, stackTrace);
    }
    return null;
  }

  @override
  void publishGrant(SessionGrant grant, {String? intentId}) {
    if (_disposed) return;
    if (grant.metadata.transport != ClientSessionTransport.webCookie) {
      throw ArgumentError('Only browser cookie grants can be coordinated.');
    }
    final encoded = jsonEncode(<String, Object?>{
      'type': 'grant',
      'grant': _grantToJson(grant),
      'intentId': ?intentId,
    });
    web.window.localStorage.setItem(_latestKey, encoded);
    _broadcast(encoded);
  }

  @override
  void publishAuthenticationIntent(String intentId) {
    if (_disposed) return;
    final encoded = jsonEncode(<String, Object?>{
      'type': 'authentication_intent',
      'intentId': intentId,
    });
    web.window.localStorage.setItem(_latestKey, encoded);
    _broadcast(encoded);
  }

  @override
  void publishSignedOut() {
    if (_disposed) return;
    final encoded = jsonEncode(<String, Object?>{'type': 'signed_out'});
    web.window.localStorage.setItem(_latestKey, encoded);
    _broadcast(encoded);
  }

  void _broadcast(String encoded) {
    try {
      _channel?.postMessage(encoded.toJS);
    } on Object {
      // Durable localStorage state is authoritative at the next lock handoff.
    }
  }

  void _consume(String encoded) {
    if (_disposed) return;
    try {
      final update = _decodeUpdate(encoded);
      if (update != null) _updates.add(update);
    } on Object {
      // Malformed same-origin messages never cross into session state.
    }
  }

  CoordinatedSessionUpdate? _decodeUpdate(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, Object?>) return null;
    return switch (decoded['type']) {
      'grant' => CoordinatedSessionUpdate.grant(
        _grantFromJson(decoded['grant']),
        intentId: _optionalString(decoded['intentId']),
      ),
      'signed_out' => const CoordinatedSessionUpdate.signedOut(),
      'authentication_intent' => CoordinatedSessionUpdate.authenticationIntent(
        _string(decoded, 'intentId'),
      ),
      _ => null,
    };
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _channel?.close();
    _channel = null;
    await _updates.close();
  }
}

Map<String, Object?> _grantToJson(SessionGrant grant) => <String, Object?>{
  'sessionId': grant.metadata.sessionId,
  'deviceId': grant.metadata.deviceId,
  'userId': grant.metadata.userId,
  'accessExpiresAt': grant.metadata.accessExpiresAt.toIso8601String(),
  'refreshExpiresAt': grant.metadata.refreshExpiresAt.toIso8601String(),
  'idleExpiresAt': grant.metadata.idleExpiresAt.toIso8601String(),
  'refreshIdleTtlSeconds': grant.metadata.refreshIdleTtl.inSeconds,
  'activeHomeId': grant.metadata.activeHomeId,
  'csrfToken': grant.secrets.csrfToken,
};

SessionGrant _grantFromJson(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a coordinated session grant.');
  }
  return SessionGrant(
    metadata: SessionMetadata(
      sessionId: _string(value, 'sessionId'),
      deviceId: _string(value, 'deviceId'),
      userId: _string(value, 'userId'),
      accessExpiresAt: _dateTime(value, 'accessExpiresAt'),
      refreshExpiresAt: _dateTime(value, 'refreshExpiresAt'),
      idleExpiresAt: _dateTime(value, 'idleExpiresAt'),
      refreshIdleTtl: Duration(
        seconds: _integer(value, 'refreshIdleTtlSeconds'),
      ),
      transport: ClientSessionTransport.webCookie,
      activeHomeId: _optionalString(value['activeHomeId']),
    ),
    secrets: SessionSecrets(csrfToken: _string(value, 'csrfToken')),
  );
}

String _string(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! String || field.isEmpty) {
    throw FormatException('Missing $key.');
  }
  return field;
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  if (value case final String text when text.isNotEmpty) return text;
  throw const FormatException('Expected a string or null.');
}

int _integer(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! int) throw FormatException('Missing $key.');
  return field;
}

DateTime _dateTime(Map<String, Object?> value, String key) {
  final parsed = DateTime.tryParse(_string(value, key));
  if (parsed == null) throw FormatException('Invalid $key.');
  return parsed.toUtc();
}
