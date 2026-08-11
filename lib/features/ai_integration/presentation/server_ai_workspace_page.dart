import 'package:flutter/material.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/domain/server_ai_models.dart';
import 'package:providentia/features/ai_integration/presentation/server_ai_workspace_controller.dart';

typedef AiSingleImagePicker =
    Future<AiMediaAsset?> Function(AiExtractionKind kind);

/// Permission-gated server-proxy AI surface. Candidate decisions are recorded
/// on the AI extraction only; this page never mutates inventory or purchases.
final class ServerAiWorkspacePage extends StatefulWidget {
  const ServerAiWorkspacePage({
    required this.controller,
    required this.pickSingleImage,
    this.onReviewHandoff,
    super.key,
  });

  final ServerAiWorkspaceController controller;
  final AiSingleImagePicker pickSingleImage;
  final ValueChanged<AiReviewHandoff>? onReviewHandoff;

  @override
  State<ServerAiWorkspacePage> createState() => _ServerAiWorkspacePageState();
}

final class _ServerAiWorkspacePageState extends State<ServerAiWorkspacePage> {
  String? _selectedProfileId;

  @override
  void initState() {
    super.initState();
    if (widget.controller.status == ServerAiWorkspaceStatus.idle) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.controller.load();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Household AI'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh AI settings',
            onPressed:
                widget.controller.capabilities.mayRead &&
                    !widget.controller.isBusy
                ? widget.controller.load
                : null,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, child) => _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final controller = widget.controller;
    if (controller.status == ServerAiWorkspaceStatus.accessDenied) {
      return _MessagePane(
        icon: Icons.lock_outline,
        title: 'AI access unavailable',
        message:
            controller.safeMessage ??
            'Your current household role does not include ai.read.',
      );
    }
    if (controller.status == ServerAiWorkspaceStatus.loading &&
        controller.workspace == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final workspace = controller.workspace;
    if (workspace == null) {
      return _MessagePane(
        icon: Icons.cloud_off_outlined,
        title: 'AI settings are not loaded',
        message:
            controller.safeMessage ??
            'Refresh when the household service is available.',
        action: FilledButton(
          onPressed: controller.isBusy ? null : controller.load,
          child: const Text('Try again'),
        ),
      );
    }

    final selected = _selectedProfile(workspace);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        if (controller.safeMessage != null)
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(controller.safeMessage!),
            ),
          ),
        _PrivacyBoundaryCard(settings: workspace.settings),
        const SizedBox(height: 12),
        Text(
          'Provider profiles',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        if (workspace.profiles.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No provider profile is configured. A household AI manager must add one.',
              ),
            ),
          )
        else
          RadioGroup<String>(
            groupValue: selected?.id,
            onChanged: (value) {
              if (!controller.isBusy && value != null) {
                setState(() => _selectedProfileId = value);
              }
            },
            child: Column(
              children: <Widget>[
                for (final profile in workspace.profiles)
                  RadioListTile<String>(
                    key: Key('ai-profile-${profile.id}'),
                    value: profile.id,
                    enabled: !controller.isBusy,
                    title: Text(profile.displayName),
                    subtitle: Text(
                      '${profile.providerWireId} · ${profile.model} · revision ${profile.revision}',
                    ),
                    secondary: Icon(
                      profile.credentialConfigured
                          ? Icons.key_outlined
                          : Icons.key_off_outlined,
                    ),
                  ),
              ],
            ),
          ),
        if (controller.capabilities.mayManage) ...<Widget>[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              OutlinedButton.icon(
                key: const Key('ai-add-profile'),
                onPressed: controller.isBusy
                    ? null
                    : () => _showProfileDialog(context),
                icon: const Icon(Icons.add),
                label: const Text('Add provider'),
              ),
              OutlinedButton.icon(
                key: const Key('ai-replace-credential'),
                onPressed: selected == null || controller.isBusy
                    ? null
                    : () => _showCredentialDialog(context, selected),
                icon: const Icon(Icons.password),
                label: const Text('Replace credential'),
              ),
              OutlinedButton.icon(
                key: const Key('ai-enable-profile'),
                onPressed: selected == null || controller.isBusy
                    ? null
                    : () => controller.updateSettings(
                        AiSettingsUpdate(
                          mode: AiServerMode.serverProxy,
                          provider: selected.providerWireId,
                          model: selected.model,
                          expectedRevision: workspace.settings.revision,
                        ),
                      ),
                icon: const Icon(Icons.toggle_on_outlined),
                label: const Text('Use selected provider'),
              ),
              OutlinedButton.icon(
                key: const Key('ai-single-profile-policy'),
                onPressed: selected == null || controller.isBusy
                    ? null
                    : () => controller.updatePolicy(
                        AiOrchestrationPolicyUpdate(
                          extractionProfileIds: <String>[selected.id],
                          validationProfileId: null,
                          maxAttempts: 1,
                          maxTotalTokens: workspace.policy.maxTotalTokens,
                          maxEstimatedCostMicros:
                              workspace.policy.maxEstimatedCostMicros,
                          expectedRevision: workspace.policy.revision,
                        ),
                      ),
                icon: const Icon(Icons.account_tree_outlined),
                label: const Text('Use single-profile policy'),
              ),
            ],
          ),
        ],
        const Divider(height: 32),
        Text(
          'Extract one image',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Providentia re-encodes the selected image, removes embedded metadata, and binds your confirmation to the exact prepared digest.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            FilledButton.icon(
              key: const Key('ai-pick-receipt'),
              onPressed: _canExtract(selected)
                  ? () => _pickAndPrepare(selected!, AiExtractionKind.receipt)
                  : null,
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('Choose receipt'),
            ),
            FilledButton.tonalIcon(
              key: const Key('ai-pick-stock'),
              onPressed: _canExtract(selected)
                  ? () =>
                        _pickAndPrepare(selected!, AiExtractionKind.stockPhoto)
                  : null,
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Choose stock photo'),
            ),
          ],
        ),
        if (controller.status == ServerAiWorkspaceStatus.preparing ||
            controller.status ==
                ServerAiWorkspaceStatus.processing) ...<Widget>[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
        ],
        if (controller.prepared != null) ...<Widget>[
          const SizedBox(height: 16),
          _ConsentCard(controller: controller),
        ],
        if (controller.status ==
            ServerAiWorkspaceStatus.quarantined) ...<Widget>[
          const SizedBox(height: 16),
          const _MessagePane(
            icon: Icons.gpp_bad_outlined,
            title: 'Image quarantined',
            message:
                'No inventory, purchase, price, or catalog record was changed.',
          ),
        ],
        if (controller.review != null) ...<Widget>[
          const Divider(height: 32),
          _CandidateReviewSection(controller: controller, onHandoff: _handoff),
        ],
      ],
    );
  }

  AiProviderProfile? _selectedProfile(AiServerWorkspace workspace) {
    if (_selectedProfileId != null) {
      final selected = workspace.profile(_selectedProfileId!);
      if (selected != null) return selected;
    }
    for (final profile in workspace.profiles) {
      if (profile.enabled &&
          profile.credentialConfigured &&
          profile.availability == AiProviderAvailability.available) {
        return profile;
      }
    }
    return workspace.profiles.isEmpty ? null : workspace.profiles.first;
  }

  bool _canExtract(AiProviderProfile? selected) {
    return selected != null &&
        selected.enabled &&
        selected.credentialConfigured &&
        selected.availability == AiProviderAvailability.available &&
        widget.controller.capabilities.mayUse &&
        !widget.controller.isBusy;
  }

  Future<void> _pickAndPrepare(
    AiProviderProfile provider,
    AiExtractionKind kind,
  ) async {
    final asset = await widget.pickSingleImage(kind);
    if (!mounted || asset == null) return;
    await widget.controller.prepareOne(provider: provider, asset: asset);
  }

  void _handoff() {
    final handoff = widget.controller.buildReviewHandoff();
    if (handoff == null) return;
    final consumer = widget.onReviewHandoff;
    if (consumer != null) {
      consumer(handoff);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Review is ready. An ordinary household command is still required; no data changed.',
          ),
        ),
      );
    }
  }

  Future<void> _showCredentialDialog(
    BuildContext context,
    AiProviderProfile profile,
  ) async {
    final secret = await showDialog<String>(
      context: context,
      builder: (context) => const _CredentialDialog(),
    );
    if (!mounted || secret == null || secret.isEmpty) return;
    await widget.controller.saveProviderProfile(
      draft: AiProviderProfileDraft(
        id: profile.id,
        label: profile.displayName,
        provider: profile.providerWireId,
        model: profile.model,
        estimatedCostMicros: profile.estimatedCostMicros,
        expectedRevision: profile.revision,
      ),
      credential: secret,
    );
  }

  Future<void> _showProfileDialog(BuildContext context) async {
    final draft =
        await showDialog<({AiProviderProfileDraft draft, String secret})>(
          context: context,
          builder: (context) => const _ProviderProfileDialog(),
        );
    if (!mounted || draft == null) return;
    await widget.controller.saveProviderProfile(
      draft: draft.draft,
      credential: draft.secret.isEmpty ? null : draft.secret,
    );
  }
}

final class _CredentialDialog extends StatefulWidget {
  const _CredentialDialog();

  @override
  State<_CredentialDialog> createState() => _CredentialDialogState();
}

final class _CredentialDialogState extends State<_CredentialDialog> {
  final TextEditingController _secret = TextEditingController();

  @override
  void dispose() {
    _secret.clear();
    _secret.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Replace provider credential'),
      content: TextField(
        key: const Key('ai-credential-field'),
        controller: _secret,
        obscureText: true,
        enableSuggestions: false,
        autocorrect: false,
        decoration: const InputDecoration(
          labelText: 'Credential',
          helperText: 'Write-only: it will not be shown again.',
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('ai-submit-credential'),
          onPressed: () {
            final value = _secret.text;
            _secret.clear();
            Navigator.pop(context, value);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

final class _ProviderProfileDialog extends StatefulWidget {
  const _ProviderProfileDialog();

  @override
  State<_ProviderProfileDialog> createState() => _ProviderProfileDialogState();
}

final class _ProviderProfileDialogState extends State<_ProviderProfileDialog> {
  final TextEditingController _label = TextEditingController();
  final TextEditingController _model = TextEditingController();
  final TextEditingController _credential = TextEditingController();
  String _provider = 'openai';

  @override
  void dispose() {
    _credential.clear();
    _label.dispose();
    _model.dispose();
    _credential.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add provider profile'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            DropdownButtonFormField<String>(
              initialValue: _provider,
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem(value: 'openai', child: Text('OpenAI')),
                DropdownMenuItem(value: 'anthropic', child: Text('Anthropic')),
                DropdownMenuItem(value: 'gemini', child: Text('Gemini')),
                DropdownMenuItem(value: 'xai', child: Text('xAI')),
                DropdownMenuItem(
                  value: 'openai-compatible',
                  child: Text('OpenAI-compatible'),
                ),
                DropdownMenuItem(value: 'ollama', child: Text('Ollama')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _provider = value);
              },
              decoration: const InputDecoration(labelText: 'Provider'),
            ),
            TextField(
              key: const Key('ai-profile-label-field'),
              controller: _label,
              decoration: const InputDecoration(labelText: 'Profile name'),
            ),
            TextField(
              key: const Key('ai-profile-model-field'),
              controller: _model,
              decoration: const InputDecoration(labelText: 'Model'),
            ),
            TextField(
              key: const Key('ai-new-profile-credential-field'),
              controller: _credential,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Credential when required',
                helperText: 'Write-only: it will not be shown again.',
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('ai-create-profile'),
          onPressed: () {
            final secret = _credential.text;
            _credential.clear();
            Navigator.pop(context, (
              draft: AiProviderProfileDraft(
                id: null,
                label: _label.text,
                provider: _provider,
                model: _model.text,
                estimatedCostMicros: 0,
                expectedRevision: 0,
              ),
              secret: secret,
            ));
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

final class _PrivacyBoundaryCard extends StatelessWidget {
  const _PrivacyBoundaryCard({required this.settings});

  final AiServerSettings settings;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Privacy boundary',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Human review is mandatory. Prepared media is sent through the secure server proxy; candidates never change inventory or purchases automatically.',
            ),
            const SizedBox(height: 8),
            Text(
              'Settings revision ${settings.revision} · credential encryption ${settings.credentialEncryptionAvailable ? 'available' : 'unavailable'}',
            ),
          ],
        ),
      ),
    );
  }
}

final class _ConsentCard extends StatelessWidget {
  const _ConsentCard({required this.controller});

  final ServerAiWorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final prepared = controller.prepared!;
    final provider = controller.selectedProvider!;
    final digest = prepared.media.single.sha256;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Confirm transmission',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Provider: ${provider.displayName} (${provider.model})\nPrepared digest: ${digest.substring(0, 12)}…',
            ),
            CheckboxListTile(
              key: const Key('ai-transmission-consent'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: controller.transmissionConfirmed,
              title: const Text(
                'Send this exact sanitized image through the server proxy',
              ),
              onChanged: (value) => value ?? false
                  ? controller.confirmTransmission()
                  : controller.revokeTransmission(),
            ),
            FilledButton.icon(
              key: const Key('ai-send-extraction'),
              onPressed: controller.transmissionConfirmed && !controller.isBusy
                  ? controller.extract
                  : null,
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('Extract for review'),
            ),
          ],
        ),
      ),
    );
  }
}

final class _CandidateReviewSection extends StatelessWidget {
  const _CandidateReviewSection({
    required this.controller,
    required this.onHandoff,
  });

  final ServerAiWorkspaceController controller;
  final VoidCallback onHandoff;

  @override
  Widget build(BuildContext context) {
    final review = controller.review!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Mandatory candidate review',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        const Text(
          'Accepting here records a review decision only. An ordinary authorized household command is still required to change data.',
        ),
        const SizedBox(height: 8),
        if (review.candidates.isEmpty)
          const Text('The extraction produced no candidates.')
        else
          for (final candidate in review.candidates)
            Card(
              key: Key('ai-candidate-${candidate.position}'),
              child: ListTile(
                title: Text(candidate.label),
                subtitle: Text(
                  '${candidate.type.name} · ${candidate.status.name} · revision ${candidate.revision}',
                ),
                trailing: candidate.status == AiCandidateReviewStatus.pending
                    ? Wrap(
                        spacing: 4,
                        children: <Widget>[
                          IconButton(
                            key: Key('ai-reject-${candidate.position}'),
                            tooltip: 'Reject candidate',
                            onPressed: controller.isBusy
                                ? null
                                : () => controller.reviewCandidate(
                                    position: candidate.position,
                                    decision: AiCandidateDecision.reject,
                                  ),
                            icon: const Icon(Icons.close),
                          ),
                          IconButton(
                            key: Key('ai-accept-${candidate.position}'),
                            tooltip: 'Accept candidate',
                            onPressed: controller.isBusy
                                ? null
                                : () => controller.reviewCandidate(
                                    position: candidate.position,
                                    decision: AiCandidateDecision.accept,
                                  ),
                            icon: const Icon(Icons.check),
                          ),
                        ],
                      )
                    : Icon(
                        candidate.status == AiCandidateReviewStatus.accepted
                            ? Icons.check_circle_outline
                            : Icons.cancel_outlined,
                      ),
              ),
            ),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const Key('ai-build-review-handoff'),
          onPressed:
              !review.hasPending &&
                  review.candidates.any(
                    (candidate) =>
                        candidate.status == AiCandidateReviewStatus.accepted,
                  )
              ? onHandoff
              : null,
          icon: const Icon(Icons.outbox_outlined),
          label: const Text('Prepare reviewed handoff'),
        ),
      ],
    );
  }
}

final class _MessagePane extends StatelessWidget {
  const _MessagePane({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 40),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            if (action != null) ...<Widget>[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
