import 'package:providentia/core/security/origin_lock.dart';

final class PlatformOriginLock implements OriginLock {
  const PlatformOriginLock();

  @override
  Future<T> runExclusive<T>(
    Future<T> Function() action, {
    required Duration waitTimeout,
  }) => action();
}
