import 'dart:async';

import 'package:flutter/material.dart';
import 'package:providentia/features/identity/domain/identity_models.dart';
import 'package:providentia/features/identity/presentation/identity_controller.dart';

final class PasswordlessSignInPage extends StatefulWidget {
  const PasswordlessSignInPage({
    required this.controller,
    this.restoreOnStart = true,
    this.authenticatedChild,
    super.key,
  });

  final IdentityController controller;
  final bool restoreOnStart;
  final Widget? authenticatedChild;

  @override
  State<PasswordlessSignInPage> createState() => _PasswordlessSignInPageState();
}

final class _PasswordlessSignInPageState extends State<PasswordlessSignInPage> {
  final GlobalKey<FormState> _emailForm = GlobalKey<FormState>();
  final GlobalKey<FormState> _codeForm = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _code = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _usePassword = false;

  @override
  void initState() {
    super.initState();
    _usePassword = widget.controller.supportsLegacyPassword;
    if (widget.restoreOnStart) {
      unawaited(widget.controller.restore());
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final snapshot = widget.controller.snapshot;
        if (snapshot.status == IdentitySessionStatus.authenticated &&
            widget.authenticatedChild != null) {
          return widget.authenticatedChild!;
        }
        return Scaffold(
          key: const Key('passwordless-sign-in-page'),
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: AutofillGroup(
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
          ),
        );
      },
    );
  }

  Widget _content(IdentitySessionSnapshot snapshot) {
    final theme = Theme.of(context);
    return Column(
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
          'Use the same email on every device to reach your homes and pantry data.',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 24),
        if (snapshot.status == IdentitySessionStatus.restoring)
          const _ProgressMessage(message: 'Restoring your secure session')
        else if (snapshot.status == IdentitySessionStatus.authenticated)
          const _ProgressMessage(message: 'Signed in. Loading your homes')
        else if (snapshot.challenge != null)
          _challengeForm(snapshot.challenge!)
        else
          _emailEntry(),
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
            textInputAction: _usePassword
                ? TextInputAction.next
                : TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Email address',
              hintText: 'name@example.com',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            validator: _validateEmail,
            onFieldSubmitted: (_) {
              if (!_usePassword) _requestLink();
            },
          ),
          if (_usePassword) ...<Widget>[
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('identity-password'),
              controller: _password,
              enabled: !widget.controller.isBusy,
              autofillHints: const <String>[AutofillHints.password],
              obscureText: true,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Password',
                prefixIcon: Icon(Icons.lock_outline),
              ),
              validator: (value) => value == null || value.isEmpty
                  ? 'Enter your password.'
                  : null,
              onFieldSubmitted: (_) => _submitPassword(),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('identity-request-link'),
            onPressed: widget.controller.isBusy
                ? null
                : (_usePassword ? _submitPassword : _requestLink),
            icon: widget.controller.isBusy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.mark_email_read_outlined),
            label: Text(
              _usePassword ? 'Sign in securely' : 'Email me a sign-in link',
            ),
          ),
          if (widget.controller.supportsLegacyPassword)
            TextButton(
              key: const Key('identity-toggle-password'),
              onPressed: widget.controller.isBusy
                  ? null
                  : () => setState(() => _usePassword = !_usePassword),
              child: Text(
                _usePassword
                    ? 'Use an email sign-in link'
                    : 'Use password for this server',
              ),
            ),
          const SizedBox(height: 12),
          if (!_usePassword)
            const Text(
              'For privacy, the response is the same whether or not the address has been used before.',
            ),
        ],
      ),
    );
  }

  Widget _challengeForm(PasswordlessChallengeReceipt challenge) {
    return Form(
      key: _codeForm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            header: true,
            child: Text(
              'Check your email',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 8),
          Text('Open the private link sent to ${challenge.email}.'),
          if (challenge.codeEntryAvailable) ...<Widget>[
            const SizedBox(height: 20),
            TextFormField(
              key: const Key('identity-one-time-code'),
              controller: _code,
              enabled: !widget.controller.isBusy,
              autofillHints: const <String>[AutofillHints.oneTimeCode],
              autocorrect: false,
              keyboardType: TextInputType.number,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'One-time code',
                prefixIcon: Icon(Icons.password_outlined),
              ),
              validator: (value) => value == null || value.trim().length < 4
                  ? 'Enter the complete code.'
                  : null,
              onFieldSubmitted: (_) => _submitCode(),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('identity-submit-code'),
              onPressed: widget.controller.isBusy ? null : _submitCode,
              child: const Text('Continue securely'),
            ),
          ],
          const SizedBox(height: 12),
          TextButton(
            key: const Key('identity-use-another-email'),
            onPressed: widget.controller.isBusy
                ? null
                : widget.controller.useAnotherEmail,
            child: const Text('Use another email'),
          ),
        ],
      ),
    );
  }

  void _requestLink() {
    if (_emailForm.currentState?.validate() ?? false) {
      unawaited(widget.controller.requestSignInLink(_email.text));
    }
  }

  void _submitCode() {
    if (_codeForm.currentState?.validate() ?? false) {
      unawaited(widget.controller.submitCode(_code.text));
    }
  }

  void _submitPassword() {
    if (_emailForm.currentState?.validate() ?? false) {
      unawaited(
        widget.controller.signInWithPassword(
          email: _email.text,
          password: _password.text,
        ),
      );
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
