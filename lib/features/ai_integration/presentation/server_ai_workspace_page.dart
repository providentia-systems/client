import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/domain/server_ai_models.dart';
import 'package:providentia/features/ai_integration/infrastructure/receipt_page_media_editor.dart';
import 'package:providentia/features/ai_integration/presentation/server_ai_workspace_controller.dart';

typedef AiSingleImagePicker =
    Future<AiMediaAsset?> Function(AiExtractionKind kind);
typedef AiMultipleImagePicker =
    Future<List<AiMediaAsset>> Function(AiExtractionKind kind);
typedef AiReceiptPdfPicker = Future<List<AiMediaAsset>> Function();
typedef AiLocalImageReader = Future<Uint8List> Function(AiMediaAsset asset);
typedef AiReceiptPageTransformer =
    Future<AiMediaAsset> Function({
      required AiMediaAsset asset,
      required ReceiptPageTransform transform,
      NormalizedRegion? crop,
    });
typedef AiLocalImageDiscarder =
    Future<void> Function(Iterable<AiMediaAsset> assets);
typedef AiPreparedImageReader =
    Future<Uint8List> Function(PreparedAiMedia media);

/// Permission-gated server-proxy AI surface. Candidate decisions are recorded
/// on the AI extraction only; this page never mutates inventory or purchases.
final class ServerAiWorkspacePage extends StatefulWidget {
  const ServerAiWorkspacePage({
    required this.controller,
    required this.pickSingleImage,
    this.pickMultipleImages,
    this.pickReceiptPdf,
    this.readLocalImage,
    this.transformReceiptPage,
    this.discardLocalImages,
    this.readPreparedImage,
    this.onReviewHandoff,
    super.key,
  });

  final ServerAiWorkspaceController controller;
  final AiSingleImagePicker pickSingleImage;
  final AiMultipleImagePicker? pickMultipleImages;
  final AiReceiptPdfPicker? pickReceiptPdf;
  final AiLocalImageReader? readLocalImage;
  final AiReceiptPageTransformer? transformReceiptPage;
  final AiLocalImageDiscarder? discardLocalImages;
  final AiPreparedImageReader? readPreparedImage;
  final ValueChanged<AiReviewHandoff>? onReviewHandoff;

  @override
  State<ServerAiWorkspacePage> createState() => _ServerAiWorkspacePageState();
}

final class _ServerAiWorkspacePageState extends State<ServerAiWorkspacePage> {
  String? _selectedProfileId;
  List<AiMediaAsset> _receiptDraftPages = <AiMediaAsset>[];
  List<Uint8List?> _receiptDraftPreviews = <Uint8List?>[];
  bool _editingReceiptPage = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerAccess);
    if (widget.controller.status == ServerAiWorkspaceStatus.idle) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.controller.load();
      });
    }
  }

  @override
  void didUpdateWidget(ServerAiWorkspacePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerAccess);
      widget.controller.addListener(_handleControllerAccess);
      unawaited(_clearReceiptDraft());
    }
  }

  void _handleControllerAccess() {
    if ((!widget.controller.capabilities.mayRead ||
            !widget.controller.capabilities.mayUse) &&
        _receiptDraftPages.isNotEmpty) {
      unawaited(_clearReceiptDraft());
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
                onPressed:
                    selected == null ||
                        controller.isBusy ||
                        selected.availability !=
                            AiProviderAvailability.available
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
                onPressed:
                    selected == null ||
                        controller.isBusy ||
                        selected.availability !=
                            AiProviderAvailability.available
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
          'Extract receipt pages or a stock image',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Receipt pages stay ordered and local while you preview, rotate, or crop them. Providentia then re-encodes every selected image, removes embedded metadata, and binds your confirmation to every exact prepared digest.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            FilledButton.icon(
              key: const Key('ai-pick-receipt'),
              onPressed: _canExtract(selected)
                  ? () => _pickReceiptPages(selected!)
                  : null,
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('Choose receipt'),
            ),
            if (widget.pickReceiptPdf != null)
              OutlinedButton.icon(
                key: const Key('ai-pick-receipt-pdf'),
                onPressed: _canExtract(selected) ? _pickReceiptPdf : null,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Choose receipt PDF'),
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
        if (_receiptDraftPages.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          _receiptDraftCard(selected!),
        ],
        if (controller.status == ServerAiWorkspaceStatus.preparing ||
            controller.status ==
                ServerAiWorkspaceStatus.processing) ...<Widget>[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
        ],
        if (controller.prepared != null) ...<Widget>[
          const SizedBox(height: 16),
          _ConsentCard(
            key: ValueKey<String>(controller.prepared!.id),
            controller: controller,
            readPreparedImage: widget.readPreparedImage,
          ),
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

  Future<void> _pickReceiptPages(AiProviderProfile provider) async {
    final multiPicker = widget.pickMultipleImages;
    if (multiPicker == null) {
      await _pickAndPrepare(provider, AiExtractionKind.receipt);
      return;
    }
    final selected = await multiPicker(AiExtractionKind.receipt);
    await _stageReceiptPages(selected);
  }

  Future<void> _pickReceiptPdf() async {
    final picker = widget.pickReceiptPdf;
    if (picker == null) return;
    final selected = await picker();
    if (!mounted || selected.isEmpty) return;
    await _stageReceiptPages(selected);
  }

  Future<void> _stageReceiptPages(List<AiMediaAsset> selected) async {
    if (!mounted || selected.isEmpty) return;
    if (selected.length > 8 ||
        selected.any(
          (asset) =>
              asset.homeId != widget.controller.capabilities.homeId ||
              asset.purpose != AiExtractionKind.receipt ||
              !const <String>{
                'image/jpeg',
                'image/png',
                'image/webp',
              }.contains(asset.mimeType),
        )) {
      await _discardLocalReceiptPages(selected);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Choose between 1 and 8 receipt pages from the active home.',
          ),
        ),
      );
      return;
    }
    await _clearReceiptDraft();
    if (!mounted) {
      await _discardLocalReceiptPages(selected);
      return;
    }
    final ordered = <AiMediaAsset>[
      for (var index = 0; index < selected.length; index++)
        _withPageIndex(selected[index], index),
    ];
    setState(() {
      _receiptDraftPages = ordered;
      _receiptDraftPreviews = List<Uint8List?>.filled(ordered.length, null);
    });
    await _loadReceiptDraftPreviews(ordered);
  }

  AiMediaAsset _withPageIndex(AiMediaAsset asset, int pageIndex) =>
      AiMediaAsset(
        id: asset.id,
        homeId: asset.homeId,
        localReference: asset.localReference,
        purpose: asset.purpose,
        mimeType: asset.mimeType,
        byteLength: asset.byteLength,
        createdAt: asset.createdAt,
        pageIndex: pageIndex,
        width: asset.width,
        height: asset.height,
      );

  Future<void> _loadReceiptDraftPreviews(List<AiMediaAsset> pages) async {
    final reader = widget.readLocalImage;
    if (reader == null) return;
    for (var index = 0; index < pages.length; index++) {
      try {
        final bytes = await reader(pages[index]);
        if (!mounted ||
            index >= _receiptDraftPages.length ||
            _receiptDraftPages[index].id != pages[index].id) {
          return;
        }
        setState(() => _receiptDraftPreviews[index] = bytes);
      } catch (_) {
        // A missing local page remains visibly unavailable and cannot be sent.
      }
    }
  }

  Widget _receiptDraftCard(AiProviderProfile provider) {
    final allPreviewed =
        _receiptDraftPreviews.length == _receiptDraftPages.length &&
        _receiptDraftPreviews.every((bytes) => bytes?.isNotEmpty ?? false);
    return Card(
      key: const Key('ai-receipt-page-draft'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '${_receiptDraftPages.length} ordered receipt page${_receiptDraftPages.length == 1 ? '' : 's'}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text(
              'Check the order and make local edits before preparing the exact outbound images.',
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 250,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _receiptDraftPages.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) => SizedBox(
                  width: 190,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text('Page ${index + 1}'),
                      const SizedBox(height: 4),
                      Expanded(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: _receiptDraftPreviews[index] != null
                              ? Image.memory(
                                  _receiptDraftPreviews[index]!,
                                  key: Key('ai-receipt-local-preview-$index'),
                                  fit: BoxFit.contain,
                                )
                              : const Center(
                                  child: Text('Local preview unavailable'),
                                ),
                        ),
                      ),
                      Wrap(
                        spacing: 4,
                        children: <Widget>[
                          IconButton(
                            key: Key('ai-receipt-rotate-$index'),
                            tooltip: 'Rotate page ${index + 1} clockwise 90°',
                            onPressed:
                                !_editingReceiptPage &&
                                    widget.transformReceiptPage != null
                                ? () => _transformReceiptDraftPage(
                                    index,
                                    ReceiptPageTransform.rotateClockwise90,
                                  )
                                : null,
                            icon: const Icon(Icons.rotate_90_degrees_cw),
                          ),
                          IconButton(
                            key: Key('ai-receipt-crop-$index'),
                            tooltip: 'Crop 5% margins from page ${index + 1}',
                            onPressed:
                                !_editingReceiptPage &&
                                    widget.transformReceiptPage != null
                                ? () => _transformReceiptDraftPage(
                                    index,
                                    ReceiptPageTransform.crop,
                                  )
                                : null,
                            icon: const Icon(Icons.crop),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('ai-prepare-receipt-pages'),
              onPressed:
                  allPreviewed &&
                      !_editingReceiptPage &&
                      !widget.controller.isBusy
                  ? () => _prepareReceiptDraft(provider)
                  : null,
              icon: const Icon(Icons.verified_user_outlined),
              label: const Text('Prepare pages for consent'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _transformReceiptDraftPage(
    int index,
    ReceiptPageTransform transform,
  ) async {
    final editor = widget.transformReceiptPage;
    if (editor == null || index >= _receiptDraftPages.length) return;
    setState(() => _editingReceiptPage = true);
    try {
      final current = _receiptDraftPages[index];
      final replacement = await editor(
        asset: current,
        transform: transform,
        crop: transform == ReceiptPageTransform.crop
            ? NormalizedRegion(
                pageIndex: index,
                x: 0.05,
                y: 0.05,
                width: 0.9,
                height: 0.9,
              )
            : null,
      );
      final reader = widget.readLocalImage;
      final preview = reader == null ? null : await reader(replacement);
      if (!mounted ||
          index >= _receiptDraftPages.length ||
          _receiptDraftPages[index].id != current.id) {
        await _discardLocalReceiptPages(<AiMediaAsset>[replacement]);
        return;
      }
      setState(() {
        _receiptDraftPages[index] = _withPageIndex(replacement, index);
        _receiptDraftPreviews[index] = preview;
      });
    } catch (_) {
      await _clearReceiptDraft();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('That page could not be edited safely.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _editingReceiptPage = false);
    }
  }

  Future<void> _prepareReceiptDraft(AiProviderProfile provider) async {
    final pages = List<AiMediaAsset>.of(_receiptDraftPages);
    await widget.controller.prepareReceiptPages(
      provider: provider,
      assets: pages,
    );
    await _clearReceiptDraft(pagesToDiscard: pages);
  }

  Future<void> _clearReceiptDraft({
    Iterable<AiMediaAsset>? pagesToDiscard,
  }) async {
    final pages = List<AiMediaAsset>.of(pagesToDiscard ?? _receiptDraftPages);
    _receiptDraftPages = <AiMediaAsset>[];
    _receiptDraftPreviews = <Uint8List?>[];
    if (mounted) setState(() {});
    await _discardLocalReceiptPages(pages);
  }

  Future<void> _discardLocalReceiptPages(Iterable<AiMediaAsset> pages) async {
    final discard = widget.discardLocalImages;
    if (discard == null || pages.isEmpty) return;
    try {
      await discard(pages);
    } catch (_) {
      // The production route independently clears its entire transient source
      // registry on preparation, revocation, replacement, and disposal.
    }
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

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerAccess);
    final pages = List<AiMediaAsset>.of(_receiptDraftPages);
    _receiptDraftPages = <AiMediaAsset>[];
    _receiptDraftPreviews = <Uint8List?>[];
    final discard = widget.discardLocalImages;
    if (discard != null && pages.isNotEmpty) {
      unawaited(discard(pages));
    }
    super.dispose();
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
    final directExtraction = switch (settings
        .mediaHandling
        .directExtractionUpload) {
      AiDirectExtractionUpload.transientNotPersisted =>
        'Not stored on Providentia servers: direct extraction uploads are transient and are discarded after request processing.',
    };
    final privateMedia = switch (settings.mediaHandling.privateMediaStorage) {
      AiPrivateMediaStorage.explicitEncryptedOptIn =>
        'Optional private-media storage is separate, encrypted, and requires an explicit transient or retained choice.',
    };
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
              'Human review is mandatory. Cloud processing sends the image through the secure server proxy to the selected provider, so it leaves this device. Candidates never change inventory or purchases automatically.',
            ),
            const SizedBox(height: 8),
            Text(
              directExtraction,
              key: const Key('ai-direct-extraction-media-disclosure'),
            ),
            const SizedBox(height: 4),
            Text(privateMedia, key: const Key('ai-private-media-disclosure')),
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

final class _ConsentCard extends StatefulWidget {
  const _ConsentCard({
    required this.controller,
    required this.readPreparedImage,
    super.key,
  });

  final ServerAiWorkspaceController controller;
  final AiPreparedImageReader? readPreparedImage;

  @override
  State<_ConsentCard> createState() => _ConsentCardState();
}

final class _ConsentCardState extends State<_ConsentCard> {
  List<Uint8List>? _previewBytes;
  bool _previewUnavailable = false;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  @override
  void didUpdateWidget(_ConsentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_preparedReferences(oldWidget.controller.prepared) !=
            _preparedReferences(widget.controller.prepared) ||
        oldWidget.readPreparedImage != widget.readPreparedImage) {
      _loadPreview();
    }
  }

  String? _preparedReferences(PreparedMediaBatch? batch) =>
      batch?.media.map((media) => media.ephemeralReference).join('|');

  Future<void> _loadPreview() async {
    _previewBytes = null;
    _previewUnavailable = false;
    final reader = widget.readPreparedImage;
    final batch = widget.controller.prepared;
    if (reader == null || batch == null || batch.media.isEmpty) {
      if (mounted) setState(() => _previewUnavailable = true);
      return;
    }
    try {
      final bytes = <Uint8List>[];
      for (final media in batch.media) {
        final page = await reader(media);
        if (page.isEmpty) throw StateError('Prepared preview is empty.');
        bytes.add(page);
      }
      if (!mounted ||
          _preparedReferences(widget.controller.prepared) !=
              _preparedReferences(batch)) {
        return;
      }
      setState(() {
        _previewBytes = bytes;
        _previewUnavailable = false;
      });
    } catch (_) {
      if (mounted) setState(() => _previewUnavailable = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final prepared = controller.prepared!;
    final provider = controller.selectedProvider!;
    final previewPages = _previewBytes;
    final pageCount = prepared.media.length;
    final directExtraction = switch (controller
        .workspace!
        .settings
        .mediaHandling
        .directExtractionUpload) {
      AiDirectExtractionUpload.transientNotPersisted =>
        'This direct extraction upload is not added to Providentia media storage. It is sent through Providentia to your selected provider, so it leaves this device.',
    };
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
              'Provider: ${provider.displayName} (${provider.model})\n'
              '$pageCount prepared image${pageCount == 1 ? '' : 's'} in the displayed order',
            ),
            const SizedBox(height: 4),
            for (var index = 0; index < prepared.media.length; index++)
              Text(
                'Page ${index + 1} digest: ${prepared.media[index].sha256.substring(0, 12)}…',
                key: Key('ai-prepared-digest-$index'),
              ),
            const SizedBox(height: 8),
            Text(
              directExtraction,
              key: const Key('ai-transmission-media-disclosure'),
            ),
            const SizedBox(height: 12),
            if (previewPages != null && pageCount == 1)
              Semantics(
                label: 'Sanitized image preview selected for AI transmission',
                image: true,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: Image.memory(
                      previewPages.single,
                      key: const Key('ai-sanitized-preview'),
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Text(
                        'The sanitized preview cannot be displayed. Choose the image again before sending.',
                        key: Key('ai-sanitized-preview-unavailable'),
                      ),
                    ),
                  ),
                ),
              )
            else if (previewPages != null)
              SizedBox(
                height: 280,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: previewPages.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, index) => Semantics(
                    label:
                        'Sanitized receipt image ${index + 1} of $pageCount selected for AI transmission',
                    image: true,
                    child: Column(
                      children: <Widget>[
                        Text('Page ${index + 1}'),
                        const SizedBox(height: 4),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(
                              previewPages[index],
                              key: index == 0
                                  ? const Key('ai-sanitized-preview')
                                  : Key('ai-sanitized-preview-$index'),
                              width: 210,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => const Text(
                                'The sanitized preview cannot be displayed. Choose the image again before sending.',
                                key: Key('ai-sanitized-preview-unavailable'),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (_previewUnavailable)
              const Text(
                'The sanitized preview is unavailable. Choose the image again before sending.',
                key: Key('ai-sanitized-preview-unavailable'),
              )
            else
              const LinearProgressIndicator(
                key: Key('ai-sanitized-preview-loading'),
              ),
            if (controller.review == null) ...<Widget>[
              CheckboxListTile(
                key: const Key('ai-transmission-consent'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: controller.transmissionConfirmed,
                title: Text(
                  pageCount == 1
                      ? 'Send this exact sanitized image through the server proxy'
                      : 'Send these exact ordered sanitized images through the server proxy',
                ),
                onChanged: previewPages == null
                    ? null
                    : (value) => value ?? false
                          ? controller.confirmTransmission()
                          : controller.revokeTransmission(),
              ),
              FilledButton.icon(
                key: const Key('ai-send-extraction'),
                onPressed:
                    previewPages != null &&
                        controller.transmissionConfirmed &&
                        !controller.isBusy
                    ? controller.extract
                    : null,
                icon: const Icon(Icons.auto_awesome_outlined),
                label: const Text('Extract for review'),
              ),
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'This sanitized local preview remains visible only while you review the candidates.',
                  key: Key('ai-review-preview-retention'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _previewBytes = null;
    super.dispose();
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
