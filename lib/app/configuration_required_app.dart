import 'package:flutter/material.dart';
import 'package:providentia/core/design_system/providentia_theme.dart';

/// Launchable fallback for invalid public API connection configuration.
/// It deliberately contains no credentials or persistence access.
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
                            'API connection setup required',
                            style: Theme.of(context).textTheme.headlineMedium,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'The API connection settings for this build are '
                          'invalid. Set PROVIDENTIA_API_BASE_URL to an absolute '
                          'HTTPS server origin, or use HTTP only for loopback '
                          'development, then restart the app.',
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
