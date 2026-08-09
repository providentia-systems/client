/// Serializes initialization and storage changes shared by every browser tab.
abstract interface class OriginLock {
  Future<T> runExclusive<T>(
    Future<T> Function() action, {
    required Duration waitTimeout,
  });
}
