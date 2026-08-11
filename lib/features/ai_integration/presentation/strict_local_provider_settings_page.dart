import 'package:flutter/material.dart';
import 'package:providentia/features/ai_integration/application/strict_local_provider_settings_controller.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';

final class StrictLocalProviderSettingsPage extends StatefulWidget {
  const StrictLocalProviderSettingsPage({required this.controller, super.key});

  final StrictLocalProviderSettingsController controller;

  @override
  State<StrictLocalProviderSettingsPage> createState() =>
      _StrictLocalProviderSettingsPageState();
}

final class _StrictLocalProviderSettingsPageState
    extends State<StrictLocalProviderSettingsPage> {
  static const _serverProxyChoice = 'server-proxy';
  final _name = TextEditingController();
  final _endpoint = TextEditingController(text: 'http://127.0.0.1:11434');
  final _model = TextEditingController();
  final _secret = TextEditingController();
  AiProviderKind _kind = AiProviderKind.ollama;
  bool _multiImage = true;
  bool _authenticated = false;
  bool _attested = false;

  @override
  void initState() {
    super.initState();
    widget.controller.load();
  }

  @override
  void dispose() {
    _name.dispose();
    _endpoint.dispose();
    _model.dispose();
    _secret.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Local AI settings')),
    body: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final state = widget.controller.state;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            const Text(
              'Direct local mode sends sanitized images straight to the shown '
              'LAN endpoint. The Providentia server does not receive them. Your '
              'local provider controls its own processing and retention.',
              key: Key('strict-local-settings-disclosure'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<AiProviderKind>(
              key: const Key('strict-local-kind'),
              initialValue: _kind,
              items: const <DropdownMenuItem<AiProviderKind>>[
                DropdownMenuItem(
                  value: AiProviderKind.ollama,
                  child: Text('Ollama'),
                ),
                DropdownMenuItem(
                  value: AiProviderKind.openAiCompatible,
                  child: Text('OpenAI-compatible LAN'),
                ),
              ],
              onChanged: (value) => setState(() {
                _kind = value ?? AiProviderKind.ollama;
                if (_kind == AiProviderKind.openAiCompatible &&
                    !_endpoint.text.startsWith('https://')) {
                  _endpoint.text = 'https://';
                }
              }),
              decoration: const InputDecoration(labelText: 'Provider'),
            ),
            TextField(
              key: const Key('strict-local-name'),
              controller: _name,
              decoration: const InputDecoration(labelText: 'Profile name'),
            ),
            TextField(
              key: const Key('strict-local-endpoint'),
              controller: _endpoint,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'LAN endpoint'),
            ),
            TextField(
              key: const Key('strict-local-model'),
              controller: _model,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Vision model'),
            ),
            SwitchListTile(
              value: _multiImage,
              onChanged: (value) => setState(() => _multiImage = value),
              title: const Text('Model supports multiple images'),
            ),
            SwitchListTile(
              value: _authenticated,
              onChanged: widget.controller.supportsAuthenticatedProfiles
                  ? (value) => setState(() => _authenticated = value)
                  : null,
              title: const Text('Endpoint requires bearer authentication'),
              subtitle: widget.controller.supportsAuthenticatedProfiles
                  ? const Text(
                      'Secret is kept only in the native secure vault.',
                    )
                  : const Text('Unavailable without a native secure vault.'),
            ),
            if (_authenticated)
              TextField(
                key: const Key('strict-local-secret'),
                controller: _secret,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Bearer secret'),
              ),
            CheckboxListTile(
              key: const Key('strict-local-attestation'),
              value: _attested,
              onChanged: (value) => setState(() => _attested = value ?? false),
              title: Text(
                'I control ${_endpoint.text.trim().isEmpty ? 'this LAN endpoint' : _endpoint.text.trim()} and understand its retention policy.',
              ),
            ),
            FilledButton(
              key: const Key('strict-local-save'),
              onPressed: state.status == StrictLocalSettingsStatus.saving
                  ? null
                  : () => widget.controller.save(
                      StrictLocalProviderDraft(
                        displayName: _name.text,
                        kind: _kind,
                        endpoint: _endpoint.text,
                        model: _model.text,
                        multiImage: _multiImage,
                        requiresAuthentication: _authenticated,
                        explicitlyAttested: _attested,
                        replacementSecret: _authenticated ? _secret.text : null,
                      ),
                    ),
              child: const Text('Save local profile'),
            ),
            if (state.safeMessage != null)
              Text(state.safeMessage!, key: const Key('strict-local-message')),
            const Divider(height: 32),
            RadioGroup<String>(
              groupValue: state.activeProfileId ?? _serverProxyChoice,
              onChanged: (profileId) {
                if (profileId == _serverProxyChoice) {
                  widget.controller.selectServerProxyRoute();
                } else if (profileId != null) {
                  widget.controller.select(profileId);
                }
              },
              child: Column(
                children: <Widget>[
                  Card(
                    child: ListTile(
                      key: const Key('strict-local-server-route'),
                      onTap: widget.controller.selectServerProxyRoute,
                      title: const Text('Server-proxy AI for stock photos'),
                      subtitle: const Text(
                        'Explicitly switch away from the local route. Cloud '
                        'processing disclosure and consent are still required.',
                      ),
                      leading: const Radio<String>(value: _serverProxyChoice),
                    ),
                  ),
                  for (final configuration in state.configurations)
                    Card(
                      child: ListTile(
                        title: Text(configuration.displayName),
                        subtitle: Text(
                          '${configuration.model}\n${configuration.endpoint}',
                        ),
                        isThreeLine: true,
                        leading: Radio<String>(value: configuration.profileId),
                        trailing: Wrap(
                          children: <Widget>[
                            IconButton(
                              tooltip: 'Test readiness',
                              onPressed: () => widget.controller.testReadiness(
                                configuration.profileId,
                              ),
                              icon: Icon(
                                state
                                            .readiness[configuration.profileId]
                                            ?.isReady ==
                                        true
                                    ? Icons.check_circle
                                    : Icons.network_check,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Delete profile',
                              onPressed: () => widget.controller.delete(
                                configuration.profileId,
                              ),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}
