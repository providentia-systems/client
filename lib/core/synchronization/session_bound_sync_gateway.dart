import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/core/synchronization/sync_ports.dart';

/// A workspace may never borrow the credentials of a later signed-in account.
/// Existing operations keep their immutable device binding; mismatches require
/// recovery rather than being rewritten and replayed.
final class SessionBoundSyncGateway implements SyncRemoteGateway {
  factory SessionBoundSyncGateway({
    required SyncRemoteGateway delegate,
    required String homeId,
    required String deviceId,
    required bool Function() isCurrent,
  }) => SessionBoundSyncGateway._(delegate, homeId, deviceId, isCurrent);

  SessionBoundSyncGateway._(
    this._delegate,
    this.homeId,
    this.deviceId,
    this._isCurrent,
  );

  final SyncRemoteGateway _delegate;
  final String homeId;
  final String deviceId;
  final bool Function() _isCurrent;
  bool _invalidated = false;

  void invalidate() => _invalidated = true;

  void _requireCurrent(String requestedHome) {
    if (_invalidated || !_isCurrent() || requestedHome != homeId) {
      throw const AuthenticationSyncException(
        'The synchronization workspace changed. Reopen the current home.',
      );
    }
  }

  void _requireDevice(String requestedDevice) {
    if (requestedDevice != deviceId) {
      throw const BindingSyncException(
        'Saved work has a different device binding and needs recovery. '
        'It has not been reassigned or sent.',
        code: 'device_binding_mismatch',
      );
    }
  }

  Future<T> _bound<T>(String home, Future<T> Function() action) async {
    _requireCurrent(home);
    final result = await action();
    _requireCurrent(home);
    return result;
  }

  @override
  Future<PullPage> bootstrap({required String homeId}) =>
      _bound(homeId, () => _delegate.bootstrap(homeId: homeId));

  @override
  Future<PullPage> pull({required String homeId, String? afterCursor}) =>
      _bound(
        homeId,
        () => _delegate.pull(homeId: homeId, afterCursor: afterCursor),
      );

  @override
  Future<PushResponse> push({
    required String homeId,
    required String? lastPulledCursor,
    required List<PendingClientOperation> operations,
  }) async {
    _requireCurrent(homeId);
    for (final operation in operations) {
      _requireCurrent(operation.homeId);
      _requireDevice(operation.deviceId);
    }
    return _bound(
      homeId,
      () => _delegate.push(
        homeId: homeId,
        lastPulledCursor: lastPulledCursor,
        operations: operations,
      ),
    );
  }

  @override
  Future<OperationStatusResponse> operationStatuses({
    required String homeId,
    required String deviceId,
    required List<String> operationIds,
  }) async {
    _requireCurrent(homeId);
    _requireDevice(deviceId);
    return _bound(
      homeId,
      () => _delegate.operationStatuses(
        homeId: homeId,
        deviceId: deviceId,
        operationIds: operationIds,
      ),
    );
  }
}
