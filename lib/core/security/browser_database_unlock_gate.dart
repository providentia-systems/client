import 'dart:async';

import 'package:flutter/material.dart';
import 'package:providentia/core/database/browser_database.dart';

export 'package:providentia/core/database/browser_database_contract.dart';

/// Separate local-data unlock; this never creates an account authentication or
/// household authorization grant. Account sign-in remains the email-code flow.
final class BrowserDatabaseUnlockGate extends StatefulWidget {
  const BrowserDatabaseUnlockGate({
    required this.builder,
    this.vaultFactory = createBrowserDatabaseVault,
    super.key,
  });

  final Widget Function(
    BuildContext context,
    BrowserDatabaseSession session,
    Future<void> Function() lockLocalDatabase,
  )
  builder;
  final BrowserDatabaseVault Function() vaultFactory;

  @override
  State<BrowserDatabaseUnlockGate> createState() =>
      _BrowserDatabaseUnlockGateState();
}

final class _BrowserDatabaseUnlockGateState
    extends State<BrowserDatabaseUnlockGate> {
  final _passphrase = TextEditingController();
  final _confirmation = TextEditingController();
  BrowserDatabaseVault? _vault;
  BrowserDatabaseSession? _session;
  BrowserDatabaseState? _state;
  String? _error;
  bool _busy = true;
  bool _acknowledged = false;

  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    try {
      final vault = _vault = widget.vaultFactory();
      final state = await vault.prepare();
      if (!mounted) {
        await vault.close();
        return;
      }
      setState(() {
        _state = state;
        _busy = false;
        _error = null;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _message(error);
        });
      }
    }
  }

  Future<void> _unlock() async {
    if (_busy || _state == null) return;
    final creating = _state == BrowserDatabaseState.create;
    if (creating &&
        (_passphrase.text.runes.length < 16 ||
            _passphrase.text != _confirmation.text ||
            !_acknowledged)) {
      setState(
        () => _error =
            'Use at least 16 characters, repeat the same passphrase, and acknowledge the recovery warning.',
      );
      return;
    }
    if (_passphrase.text.isEmpty) {
      setState(() => _error = 'Enter your local-data passphrase.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    // Do not retain the entered secret in UI controllers after submission.
    final secret = _passphrase.text;
    _passphrase.clear();
    _confirmation.clear();
    try {
      final session = await _vault!.unlock(secret);
      if (!mounted) {
        await session.close();
        return;
      }
      setState(() {
        _session = session;
        _busy = false;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _message(error);
        });
      }
    }
  }

  Future<void> _lock() async {
    final vault = _vault;
    if (mounted) {
      setState(() {
        _session = null;
        _busy = true;
        _state = null;
      });
    }
    if (mounted) {
      _passphrase.clear();
      _confirmation.clear();
      _acknowledged = false;
    }
    await vault?.close();
    if (mounted) await _prepare();
  }

  Future<void> _retry() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    await _vault?.close();
    if (mounted) await _prepare();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session != null) return widget.builder(context, session, _lock);
    final creating = _state == BrowserDatabaseState.create;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    creating ? 'Protect browser data' : 'Unlock browser data',
                    style: const TextStyle(fontSize: 26),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'This separate passphrase encrypts the household database saved in this browser. '
                    'Your account still uses its usual email sign-in code.',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'If you lose this passphrase, you lose access to unsynced local data. '
                    'An email sign-in code cannot recover it. Clearing browser data can also '
                    'erase unsynced work. Keep the passphrase in a trusted password manager.',
                  ),
                  if (_state != null) ...[
                    const SizedBox(height: 20),
                    TextField(
                      key: const Key('browser-local-passphrase'),
                      controller: _passphrase,
                      enabled: !_busy,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: 'Local-data passphrase',
                      ),
                      onSubmitted: (_) {
                        if (!creating) unawaited(_unlock());
                      },
                    ),
                    if (creating) ...[
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('browser-local-passphrase-confirm'),
                        controller: _confirmation,
                        enabled: !_busy,
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                          labelText:
                              'Repeat passphrase (at least 16 characters)',
                        ),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _acknowledged,
                        onChanged: _busy
                            ? null
                            : (value) => setState(
                                () => _acknowledged = value ?? false,
                              ),
                        title: const Text(
                          'I understand that losing this passphrase can permanently lose unsynced data.',
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy ? null : _unlock,
                      child: Text(
                        creating ? 'Protect local data' : 'Unlock local data',
                      ),
                    ),
                  ],
                  if (_busy) ...[
                    const SizedBox(height: 16),
                    const Center(child: CircularProgressIndicator()),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, key: const Key('browser-unlock-error')),
                    if (_state == null)
                      TextButton(
                        onPressed: _busy ? null : _retry,
                        child: const Text('Try again'),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _passphrase.dispose();
    _confirmation.dispose();
    unawaited(_vault?.close());
    super.dispose();
  }
}

String _message(Object error) {
  final code = error is BrowserDatabaseProtectionException ? error.code : '';
  return switch (code) {
    'legacy_data_detected' =>
      'An earlier unencrypted browser database was found. '
          'It has been preserved and this version will not overwrite it. Close this tab. '
          'Use the previous trusted client version at this same browser origin to sync '
          'pending work, or contact support for a verified export and encrypted migration. '
          'Do not clear browser storage while unsynced work remains.',
    'database_busy' =>
      'Another tab has this browser database open. Close other '
          'Providentia tabs, then try again.',
    'unsupported_browser' =>
      'Secure browser storage is unavailable. Open this app '
          'over HTTPS in a current browser with WebCrypto, IndexedDB, Web Locks and '
          'origin-private storage support. Saved data has not been reset.',
    'unlock_failed' =>
      'The passphrase is incorrect, or the encrypted data cannot '
          'be verified. Try your original local-data passphrase. Saved data has not been reset.',
    'passphrase_too_short' =>
      'Use at least 16 characters for the local-data passphrase.',
    _ =>
      'Browser data could not be opened safely. Close and reopen this tab to try '
          'again. Do not clear browser storage; contact support if the problem continues.',
  };
}
