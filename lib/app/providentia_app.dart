import 'package:flutter/material.dart';
import 'package:providentia/features/feature_registry.dart';

/// Phase 1 application shell.
///
/// The approved Fresh Market design system and feature UI are intentionally
/// deferred to Phase 3. This shell proves that the application and feature
/// boundaries compose on every supported Flutter target.
class ProvidentiaApp extends StatelessWidget {
  const ProvidentiaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const _FoundationScreen(),
      title: 'Providentia',
    );
  }
}

class _FoundationScreen extends StatelessWidget {
  const _FoundationScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Providentia',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Production foundation ready. Product workflows and the '
                    'approved responsive design system begin in later phases.',
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '${featureRegistry.length} bounded feature areas registered',
                    key: const Key('feature-count'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
