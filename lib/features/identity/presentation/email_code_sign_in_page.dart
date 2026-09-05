import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:providentia/features/identity/domain/identity_models.dart';
import 'package:providentia/features/identity/presentation/identity_controller.dart';

final class EmailCodeSignInPage extends StatefulWidget {
  const EmailCodeSignInPage({
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
  State<EmailCodeSignInPage> createState() => _EmailCodeSignInPageState();
}

final class _EmailCodeSignInPageState extends State<EmailCodeSignInPage> {
  final GlobalKey<FormState> _emailForm = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _code = TextEditingController();
  Timer? _countdown;

  @override
  void initState() {
    super.initState();
    _countdown = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.controller.snapshot.pendingEmailCode != null) {
        setState(() {});
      }
    });
    if (widget.restoreOnStart) {
      unawaited(widget.controller.restore());
    }
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _code.dispose();
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
          key: const Key('email-code-sign-in-page'),
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
    final pending = snapshot.pendingEmailCode;
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
            IdentitySessionStatus.requestingEmailCode => const _ProgressMessage(
              message: 'Sending your email code',
            ),
            IdentitySessionStatus.verifyingEmailCode => const _ProgressMessage(
              message: 'Verifying your email code',
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
            onFieldSubmitted: (_) => _requestEmailCode(),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('identity-request-email-code'),
            onPressed: widget.controller.isBusy ? null : _requestEmailCode,
            icon: const Icon(Icons.mark_email_read_outlined),
            label: const Text('Email me a email code'),
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
    PendingEmailCodeView? pending,
    String email,
  ) {
    final remaining =
        pending?.resendAt.difference(DateTime.now().toUtc()).inSeconds ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Check your email', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text('Enter the eight-digit code sent to $email.'),
        const SizedBox(height: 16),
        TextField(
          key: const Key('identity-email-code'),
          controller: _code,
          enabled: !widget.controller.isBusy,
          keyboardType: TextInputType.number,
          autofillHints: const <String>[AutofillHints.oneTimeCode],
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(8),
          ],
          decoration: const InputDecoration(
            labelText: 'Email code',
            helperText: 'Valid for ten minutes',
          ),
          onSubmitted: (_) =>
              unawaited(widget.controller.verifyEmailCode(_code.text)),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('identity-verify-email-code'),
          onPressed: widget.controller.isBusy || pending == null
              ? null
              : () => unawaited(widget.controller.verifyEmailCode(_code.text)),
          child: const Text('Verify and sign in'),
        ),
        TextButton(
          key: const Key('identity-resend-email-code'),
          onPressed: widget.controller.isBusy || remaining > 0
              ? null
              : () {
                  _code.clear();
                  unawaited(widget.controller.resendEmailCode());
                },
          child: Text(
            remaining > 0 ? 'Resend in ${remaining}s' : 'Send a new code',
          ),
        ),
        TextButton(
          key: const Key('identity-cancel-email-code'),
          onPressed: widget.controller.isBusy
              ? null
              : () => unawaited(widget.controller.cancelEmailCode()),
          child: const Text('Use another email'),
        ),
      ],
    );
  }

  void _requestEmailCode() {
    if (_emailForm.currentState?.validate() ?? false) {
      unawaited(widget.controller.requestEmailCode(_email.text));
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
