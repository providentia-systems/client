import 'dart:async';

import 'package:flutter/material.dart';
import 'package:providentia/features/identity/domain/login_link_approval_models.dart';
import 'package:providentia/features/identity/presentation/login_link_approval_controller.dart';

final class LoginLinkApprovalPage extends StatelessWidget {
  const LoginLinkApprovalPage({required this.controller, super.key});

  final LoginLinkApprovalController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const Key('login-link-approval-page'),
    appBar: AppBar(title: const Text('Review login request')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => Padding(
              padding: const EdgeInsets.all(24),
              child: _content(context, controller.snapshot),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _content(BuildContext context, LoginLinkApprovalSnapshot snapshot) {
    final review = snapshot.review;
    if (snapshot.status == LoginLinkApprovalStatus.loading) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Checking this login request securely'),
        ],
      );
    }
    if (review != null &&
        (snapshot.status == LoginLinkApprovalStatus.ready ||
            snapshot.status == LoginLinkApprovalStatus.submitting)) {
      final busy = snapshot.status == LoginLinkApprovalStatus.submitting;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'A device wants to sign in',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          Text('Device: ${review.deviceName}'),
          Text('Platform: ${review.platform}'),
          Text('Requested: ${review.createdAt.toLocal()}'),
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('login-link-approve'),
            onPressed: busy
                ? null
                : () => unawaited(
                    controller.decide(LoginLinkApprovalDecision.approve),
                  ),
            child: const Text('Approve login'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('login-link-deny'),
            onPressed: busy
                ? null
                : () => unawaited(
                    controller.decide(LoginLinkApprovalDecision.deny),
                  ),
            child: const Text('Deny login'),
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(Icons.verified_user_outlined, size: 56),
        const SizedBox(height: 16),
        Text(
          snapshot.safeMessage ?? 'Open a current Providentia login link.',
          key: const Key('login-link-approval-message'),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
