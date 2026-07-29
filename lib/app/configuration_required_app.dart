import 'package:flutter/material.dart';
import 'package:providentia/core/design_system/providentia_theme.dart';

/// Launchable fallback while production sign-in and active-home selection are
/// completed. It deliberately contains no credentials or persistence access.
final class ConfigurationRequiredApp extends StatelessWidget {
  const ConfigurationRequiredApp({required this.safeMessage, super.key});

  final String safeMessage;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Providentia',
      theme: ProvidentiaTheme.light(),
      highContrastTheme: ProvidentiaTheme.light(highContrast: true),
      home: Scaffold(
        key: const Key('configuration-required-shell'),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(Icons.eco_rounded, size: 52),
                        const SizedBox(height: 16),
                        Semantics(
                          header: true,
                          child: Text(
                            'Sign-in setup required',
                            style: Theme.of(context).textTheme.headlineMedium,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'This build is ready to launch, but no authenticated '
                          'home has been selected. For the development '
                          'prototype, start it with the loopback home and '
                          'short-lived token printed by the backend setup '
                          'script. Production sign-in remains a follow-on UI.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          safeMessage,
                          key: const Key('configuration-safe-message'),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
