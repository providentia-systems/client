import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:providentia/features/administration/domain/platform_administrator_models.dart';

enum PlatformAdministrationFailureKind {
  forbidden,
  conflict,
  validation,
  unavailable,
}

final class PlatformAdministrationException implements Exception {
  const PlatformAdministrationException({
    required this.kind,
    required this.safeMessage,
  });

  final PlatformAdministrationFailureKind kind;
  final String safeMessage;
}

abstract interface class PlatformAdministrationPort {
  Future<List<PlatformAdministrator>> listAdministrators();

  Future<PlatformAdministrator> grantAdministrator(String email);

  Future<void> revokeAdministrator({
    required String administratorId,
    required int expectedRevision,
  });
}

final class PlatformAdministrationController extends ChangeNotifier {
  factory PlatformAdministrationController(
    PlatformAdministrationPort transport, {
    Future<void> Function()? onAuthorizationLost,
  }) => PlatformAdministrationController._(transport, onAuthorizationLost);

  PlatformAdministrationController._(this._transport, this._onAuthorizationLost)
    : _snapshot = PlatformAdministrationSnapshot();

  final PlatformAdministrationPort _transport;
  final Future<void> Function()? _onAuthorizationLost;
  PlatformAdministrationSnapshot _snapshot;
  int _generation = 0;
  bool _disposed = false;

  PlatformAdministrationSnapshot get snapshot => _snapshot;

  Future<void> load() async {
    final generation = ++_generation;
    _set(
      PlatformAdministrationSnapshot(
        loading: true,
        administrators: _snapshot.administrators,
      ),
    );
    try {
      final administrators = await _transport.listAdministrators();
      if (generation != _generation) {
        return;
      }
      _set(PlatformAdministrationSnapshot(administrators: administrators));
    } on PlatformAdministrationException catch (error) {
      if (generation == _generation) {
        _transportFailure(error);
      }
    } on Exception {
      if (generation == _generation) {
        _failure('Administrator details could not be loaded safely.');
      }
    }
  }

  Future<void> grant(String email) async {
    final normalized = email.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(normalized)) {
      _failure('Enter a valid email address.');
      return;
    }
    final generation = ++_generation;
    _set(
      PlatformAdministrationSnapshot(
        loading: true,
        administrators: _snapshot.administrators,
      ),
    );
    try {
      await _transport.grantAdministrator(normalized);
      if (generation != _generation) {
        return;
      }
      final administrators = await _transport.listAdministrators();
      if (generation == _generation) {
        _set(PlatformAdministrationSnapshot(administrators: administrators));
      }
    } on PlatformAdministrationException catch (error) {
      if (generation == _generation) {
        _transportFailure(error);
      }
    } on Exception {
      if (generation == _generation) {
        _failure('The administrator grant could not be completed safely.');
      }
    }
  }

  Future<void> revoke(PlatformAdministrator administrator) async {
    final generation = ++_generation;
    _set(
      PlatformAdministrationSnapshot(
        loading: true,
        administrators: _snapshot.administrators,
      ),
    );
    try {
      await _transport.revokeAdministrator(
        administratorId: administrator.id,
        expectedRevision: administrator.revision,
      );
      if (generation != _generation) {
        return;
      }
      final administrators = await _transport.listAdministrators();
      if (generation == _generation) {
        _set(PlatformAdministrationSnapshot(administrators: administrators));
      }
    } on PlatformAdministrationException catch (error) {
      if (generation == _generation) {
        _transportFailure(error);
      }
    } on Exception {
      if (generation == _generation) {
        _failure('The administrator revoke could not be completed safely.');
      }
    }
  }

  /// Invalidates in-flight work and removes privileged data immediately when
  /// the authenticated session is lost.
  void clearSensitiveState() {
    if (_disposed) {
      return;
    }
    _generation++;
    _set(PlatformAdministrationSnapshot());
  }

  void _transportFailure(PlatformAdministrationException error) {
    if (error.kind != PlatformAdministrationFailureKind.forbidden) {
      _failure(error.safeMessage);
      return;
    }
    _generation++;
    _set(PlatformAdministrationSnapshot());
    final onAuthorizationLost = _onAuthorizationLost;
    if (onAuthorizationLost != null) {
      unawaited(onAuthorizationLost().catchError((_) {}));
    }
  }

  void _failure(String safeMessage) => _set(
    PlatformAdministrationSnapshot(
      administrators: _snapshot.administrators,
      safeMessage: safeMessage,
    ),
  );

  void _set(PlatformAdministrationSnapshot snapshot) {
    if (_disposed) {
      return;
    }
    _snapshot = snapshot;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
