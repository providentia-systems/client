import 'package:flutter/foundation.dart';
import 'package:providentia/features/identity/application/login_link_approval_port.dart';
import 'package:providentia/features/identity/domain/login_link_approval_models.dart';

enum LoginLinkApprovalStatus {
  idle,
  loading,
  ready,
  submitting,
  completed,
  failed,
}

final class LoginLinkApprovalSnapshot {
  const LoginLinkApprovalSnapshot({
    required this.status,
    this.review,
    this.decision,
    this.safeMessage,
  });

  const LoginLinkApprovalSnapshot.idle()
    : status = LoginLinkApprovalStatus.idle,
      review = null,
      decision = null,
      safeMessage = null;

  final LoginLinkApprovalStatus status;
  final LoginLinkApprovalReview? review;
  final LoginLinkApprovalDecision? decision;
  final String? safeMessage;
}

final class LoginLinkApprovalController extends ChangeNotifier {
  LoginLinkApprovalController({
    required this.transport,
    Uri? expectedBaseUri,
    DateTime Function()? clock,
  }) : _expectedBaseUri =
           expectedBaseUri ?? Uri.parse('providentia://login-link/homeowner'),
       _clock = clock ?? DateTime.now;

  final LoginLinkApprovalPort transport;
  final Uri _expectedBaseUri;
  final DateTime Function() _clock;
  LoginLinkApprovalCapability? _capability;
  LoginLinkApprovalSnapshot _snapshot = const LoginLinkApprovalSnapshot.idle();
  int _generation = 0;
  bool _disposed = false;

  LoginLinkApprovalSnapshot get snapshot => _snapshot;

  Future<void> receive(Uri uri) async {
    final generation = ++_generation;
    _capability = null;
    _set(
      const LoginLinkApprovalSnapshot(status: LoginLinkApprovalStatus.loading),
    );
    try {
      final capability = LoginLinkApprovalCapability.parse(
        uri,
        expectedBaseUri: _expectedBaseUri,
      );
      _capability = capability;
      await transport.prove(capability);
      final review = await transport.review(capability);
      if (!_isCurrent(generation, capability)) return;
      if (review.isExpiredAt(_clock().toUtc())) {
        throw const LoginLinkApprovalException(
          LoginLinkApprovalFailureKind.invalidOrExpired,
          'This login approval link has expired.',
        );
      }
      _set(
        LoginLinkApprovalSnapshot(
          status: LoginLinkApprovalStatus.ready,
          review: review,
        ),
      );
    } on LoginLinkApprovalException catch (error) {
      if (generation != _generation) return;
      _capability = null;
      _set(
        LoginLinkApprovalSnapshot(
          status: LoginLinkApprovalStatus.failed,
          safeMessage: error.safeMessage,
        ),
      );
    } on FormatException catch (error) {
      if (generation != _generation) return;
      _capability = null;
      _set(
        LoginLinkApprovalSnapshot(
          status: LoginLinkApprovalStatus.failed,
          safeMessage: error.message.toString(),
        ),
      );
    } on Object {
      if (generation != _generation) return;
      _capability = null;
      _set(
        const LoginLinkApprovalSnapshot(
          status: LoginLinkApprovalStatus.failed,
          safeMessage: 'The login approval link could not be reviewed safely.',
        ),
      );
    }
  }

  Future<void> decide(LoginLinkApprovalDecision decision) async {
    final capability = _capability;
    final review = _snapshot.review;
    if (capability == null ||
        review == null ||
        _snapshot.status != LoginLinkApprovalStatus.ready) {
      return;
    }
    final generation = ++_generation;
    _set(
      LoginLinkApprovalSnapshot(
        status: LoginLinkApprovalStatus.submitting,
        review: review,
      ),
    );
    try {
      await transport.decide(capability: capability, decision: decision);
      if (!_isCurrent(generation, capability)) return;
      _capability = null;
      _set(
        LoginLinkApprovalSnapshot(
          status: LoginLinkApprovalStatus.completed,
          decision: decision,
          safeMessage: decision == LoginLinkApprovalDecision.approve
              ? 'Login approved. Return to the requesting device.'
              : 'Login denied.',
        ),
      );
    } on LoginLinkApprovalException catch (error) {
      if (generation != _generation) return;
      _capability = null;
      _set(
        LoginLinkApprovalSnapshot(
          status: LoginLinkApprovalStatus.failed,
          safeMessage: error.safeMessage,
        ),
      );
    } on Object {
      if (generation != _generation) return;
      _capability = null;
      _set(
        const LoginLinkApprovalSnapshot(
          status: LoginLinkApprovalStatus.failed,
          safeMessage: 'The login decision could not be sent safely.',
        ),
      );
    }
  }

  void cancel() {
    _generation++;
    _capability = null;
    _set(const LoginLinkApprovalSnapshot.idle());
  }

  bool _isCurrent(int generation, LoginLinkApprovalCapability capability) =>
      !_disposed &&
      generation == _generation &&
      identical(_capability, capability);

  void _set(LoginLinkApprovalSnapshot snapshot) {
    if (_disposed) return;
    _snapshot = snapshot;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _capability = null;
    super.dispose();
  }
}
