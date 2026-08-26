import 'dart:async';

import 'package:flutter/material.dart';
import 'package:providentia/features/identity/domain/identity_models.dart';
import 'package:providentia/features/identity/presentation/identity_controller.dart';

final class LoginLinkSignInPage extends StatefulWidget {
  const LoginLinkSignInPage({
    required this.controller,
    this.restoreOnStart = true,
    this.authenticatedBuilder,
    super.key,
  });

  final IdentityController controller;
  final bool restoreOnStart;
  final Widget Function(BuildContext context, IdentitySessionSnapshot snapshot)?
  authenticatedBuilder;

  @override
  State<LoginLinkSignInPage> createState() => _LoginLinkSignInPageState();
}

final class _LoginLinkSignInPageState extends State<LoginLinkSignInPage>
    with WidgetsBindingObserver {
  final GlobalKey<FormState> _emailForm = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.restoreOnStart) {
      unawaited(widget.controller.restore());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        widget.controller.resumeLoginLinkPolling();
        return;
      case AppLifecycleState.inactive ||
          AppLifecycleState.hidden ||
          AppLifecycleState.paused ||
          AppLifecycleState.detached:
        widget.controller.pauseLoginLinkPolling();
        return;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final snapshot = widget.controller.snapshot;
        if (snapshot.isAuthenticated && widget.authenticatedBuilder != null) {
          final authenticated = widget.authenticatedBuilder!(context, snapshot);
          if (snapshot.currentUser != null) {
            return authenticated;
          }
          return Stack(
            children: <Widget>[
              authenticated,
              SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Material(
                    elevation: 4,
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              snapshot.safeMessage ??
                                  'Account details are temporarily unavailable.',
                            ),
                          ),
                          TextButton(
                            key: const Key('identity-retry-account-details'),
                            onPressed: widget.controller.isBusy
                                ? null
                                : () => unawaited(
                                    widget.controller.refreshCurrentUser(),
                                  ),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }
        return Scaffold(
          key: const Key('login-link-sign-in-page'),
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: _content(snapshot),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _content(IdentitySessionSnapshot snapshot) {
    final theme = Theme.of(context);
    final pending = snapshot.pendingLoginLink;
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Semantics(
            header: true,
            child: Text(
              'Sign in to Providentia',
              style: theme.textTheme.headlineMedium,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Enter your email. No password is needed.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          switch (snapshot.status) {
            IdentitySessionStatus.restoring => const _ProgressMessage(
              message: 'Restoring your secure session',
            ),
            IdentitySessionStatus.requestingLoginLink => const _ProgressMessage(
              message: 'Sending your login link',
            ),
            IdentitySessionStatus.exchangingLoginLink => const _ProgressMessage(
              message: 'Email approved. Finishing sign in securely',
            ),
            IdentitySessionStatus.authenticated => const _ProgressMessage(
              message: 'Signed in. Loading your homes',
            ),
            _ when pending != null || snapshot.loginEmail != null =>
              _pendingRequest(
                snapshot,
                pending,
                pending?.email ?? snapshot.loginEmail!,
              ),
            _ => _emailEntry(),
          },
          if (snapshot.safeMessage != null) ...<Widget>[
            const SizedBox(height: 16),
            Semantics(
              liveRegion: true,
              container: true,
              child: Text(
                snapshot.safeMessage!,
                key: const Key('identity-safe-message'),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _emailEntry() {
    return Form(
      key: _emailForm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextFormField(
            key: const Key('identity-email'),
            controller: _email,
            enabled: !widget.controller.isBusy,
            autofillHints: const <String>[AutofillHints.email],
            autocorrect: false,
            keyboardType: TextInputType.emailAddress,
            textCapitalization: TextCapitalization.none,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Email address',
              hintText: 'name@example.com',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            validator: _validateEmail,
            onFieldSubmitted: (_) => _requestLoginLink(),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('identity-request-login-link'),
            onPressed: widget.controller.isBusy ? null : _requestLoginLink,
            icon: const Icon(Icons.mark_email_read_outlined),
            label: const Text('Email me a login link'),
          ),
          const SizedBox(height: 12),
          const Text(
            'For privacy, the response is the same whether this address is new or already registered.',
          ),
        ],
      ),
    );
  }

  Widget _pendingRequest(
    IdentitySessionSnapshot snapshot,
    PendingLoginLinkView? pending,
    String email,
  ) {
    final waiting =
        snapshot.status == IdentitySessionStatus.waitingForLoginLink;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          header: true,
          child: Text(
            waiting ? 'Check your email' : 'Request a new login link',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          waiting
              ? 'Open the login link sent to $email on any device. This app will continue automatically after the browser approves the request.'
              : 'Send a new login link to $email to continue.',
        ),
        if (waiting) ...<Widget>[
          const SizedBox(height: 12),
          const Text(
            'The browser will tell you when approval is complete and can then be closed.',
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const Key('identity-check-login-link'),
            onPressed: widget.controller.isBusy
                ? null
                : () => unawaited(widget.controller.checkLoginLinkNow()),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Check now'),
          ),
        ],
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          key: const Key('identity-resend-login-link'),
          onPressed: widget.controller.isBusy
              ? null
              : () => unawaited(widget.controller.resendLoginLink()),
          icon: const Icon(Icons.forward_to_inbox_outlined),
          label: const Text('Send a new login link'),
        ),
        TextButton(
          key: const Key('identity-cancel-login-link'),
          onPressed: widget.controller.isBusy
              ? null
              : () => unawaited(widget.controller.cancelLoginLink()),
          child: const Text('Use another email'),
        ),
      ],
    );
  }

  void _requestLoginLink() {
    if (_emailForm.currentState?.validate() ?? false) {
      unawaited(widget.controller.requestLoginLink(_email.text));
    }
  }

  String? _validateEmail(String? value) {
    final normalized = value?.trim() ?? '';
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalized)
        ? null
        : 'Enter a valid email address.';
  }
}

final class _ProgressMessage extends StatelessWidget {
  const _ProgressMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: message,
      child: Row(
        children: <Widget>[
          const SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 16),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}
