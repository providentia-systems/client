import 'package:flutter/material.dart';

final class HomeAiHubPage extends StatelessWidget {
  const HomeAiHubPage({
    required this.serverProxyPageBuilder,
    required this.strictLocalSettingsPageBuilder,
    required this.mayManageLocalProfiles,
    super.key,
  });

  final WidgetBuilder serverProxyPageBuilder;
  final WidgetBuilder strictLocalSettingsPageBuilder;
  final bool mayManageLocalProfiles;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Household AI')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Card(
          child: ListTile(
            key: const Key('home-ai-server-proxy'),
            leading: const Icon(Icons.cloud_outlined),
            title: const Text('Secure server AI'),
            subtitle: const Text(
              'Use household-managed cloud providers through the Providentia server.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(builder: serverProxyPageBuilder),
            ),
          ),
        ),
        Card(
          child: ListTile(
            key: const Key('home-ai-strict-local'),
            leading: const Icon(Icons.lan_outlined),
            title: const Text('Direct local AI'),
            subtitle: Text(
              mayManageLocalProfiles
                  ? 'Configure Ollama or an HTTPS OpenAI-compatible LAN provider.'
                  : 'Your household role cannot manage local AI profiles.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: mayManageLocalProfiles
                ? () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: strictLocalSettingsPageBuilder,
                    ),
                  )
                : null,
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'Direct local mode is available only when the device can verify '
            'the connected LAN peer. Browser builds fail closed.',
          ),
        ),
      ],
    ),
  );
}
