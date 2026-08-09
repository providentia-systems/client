import 'dart:async';
import 'dart:js_interop';

import 'package:providentia/core/security/origin_lock.dart';
import 'package:web/web.dart' as web;

/// Uses the same origin Web Lock as cookie/session mutations. This protects
/// flutter_secure_storage's first-use key generation as well as the device ID.
final class PlatformOriginLock implements OriginLock {
  const PlatformOriginLock();

  static const String _lockName = 'providentia.web-session-cookie-mutation.v1';

  @override
  Future<T> runExclusive<T>(
    Future<T> Function() action, {
    required Duration waitTimeout,
  }) {
    if (waitTimeout <= Duration.zero) {
      return Future<T>.error(ArgumentError.value(waitTimeout, 'waitTimeout'));
    }
    final result = Completer<T>();
    final abortController = web.AbortController();
    final timer = Timer(waitTimeout, () => abortController.abort());

    JSPromise<JSAny?> callback(web.Lock _) =>
        _runLocked(action, result, timer).toJS;

    try {
      final request = web.window.navigator.locks.request(
        _lockName,
        web.LockOptions(mode: 'exclusive', signal: abortController.signal),
        callback.toJS,
      );
      unawaited(
        request.toDart.then<void>(
          (_) {
            if (!result.isCompleted) {
              result.completeError(
                StateError('The origin lock ended without a result.'),
              );
            }
          },
          onError: (Object _, StackTrace stackTrace) {
            if (!result.isCompleted) {
              result.completeError(
                TimeoutException(
                  'Another tab is initializing secure storage.',
                  waitTimeout,
                ),
                stackTrace,
              );
            }
          },
        ),
      );
    } on Object catch (_, stackTrace) {
      timer.cancel();
      result.completeError(
        UnsupportedError(
          'This browser cannot safely initialize shared secure storage.',
        ),
        stackTrace,
      );
    }
    return result.future.whenComplete(timer.cancel);
  }

  Future<JSAny?> _runLocked<T>(
    Future<T> Function() action,
    Completer<T> result,
    Timer timer,
  ) async {
    timer.cancel();
    try {
      if (!result.isCompleted) result.complete(await action());
    } on Object catch (error, stackTrace) {
      if (!result.isCompleted) result.completeError(error, stackTrace);
    }
    return null;
  }
}
