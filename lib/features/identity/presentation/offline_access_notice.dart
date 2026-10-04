import 'package:flutter/material.dart';

/// Keeps bounded local access visible and provides an explicit revalidation
/// action before any server work can resume.
final class OfflineAccessNotice extends StatelessWidget {
  const OfflineAccessNotice({
    required this.offline,
    required this.onReconnect,
    required this.onSignOut,
    required this.child,
    super.key,
  });
  final bool offline;
  final Future<void> Function() onReconnect;
  final Future<void> Function() onSignOut;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!offline) return child;
    return Column(
      children: <Widget>[
        Material(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                children: <Widget>[
                  const Text(
                    'Offline: saved work stays on this device until access is reverified.',
                  ),
                  TextButton(
                    onPressed: onReconnect,
                    child: const Text('Reconnect'),
                  ),
                  TextButton(
                    onPressed: onSignOut,
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
