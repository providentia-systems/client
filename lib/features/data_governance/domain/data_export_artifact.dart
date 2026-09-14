import 'dart:typed_data';

import 'package:providentia/core/security/uuid_v4.dart';

import 'data_governance_models.dart';

/// A retrieved private artifact, retained in memory only until save/discard.
/// Its token is deliberately not represented. Saved user copies are not caches.
final class DataExportArtifact {
  DataExportArtifact({
    required this.requestId,
    required this.scope,
    required this.expiresAt,
    required Uint8List bytes,
  }) : _bytes = bytes {
    if (!isUuid(requestId) || bytes.isEmpty) {
      throw ArgumentError('Invalid export artifact.');
    }
  }

  final String requestId;
  final DataGovernanceScope scope;
  final DateTime expiresAt;
  final Uint8List _bytes;
  bool _disposed = false;

  String get filename => 'providentia-${scope.name}-export-$requestId.json';
  Uint8List get bytes {
    if (_disposed) throw StateError('Export artifact was discarded.');
    return _bytes;
  }

  bool get disposed => _disposed;
  void dispose() {
    _bytes.fillRange(0, _bytes.length, 0);
    _disposed = true;
  }

  @override
  String toString() => 'DataExportArtifact(private)';
}
