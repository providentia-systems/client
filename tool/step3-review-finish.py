from pathlib import Path
p=Path('lib/features/ai_integration/presentation/server_ai_workspace_controller.dart');s=p.read_text()
old='''    if (isBusy ||
        _status != ServerAiWorkspaceStatus.reviewRequired ||
        !_requireUse()) {
      return;
    }'''
new='''    if (!_requireUse() || isBusy) return;
    if (_status != ServerAiWorkspaceStatus.reviewRequired) {
      _safeMessage = 'Reload the current extraction before reviewing candidates.';
      _notify();
      return;
    }'''
assert old in s;s=s.replace(old,new)
old='''    if (review == null ||
        candidate == null ||
        candidate.status == AiCandidateReviewStatus.rejected ||
        (decision == AiCandidateDecision.accept &&
            (candidate.status != AiCandidateReviewStatus.pending ||
                !review.canAccept(position)))) {'''
new='''    if (review == null || candidate == null ||
        candidate.status == AiCandidateReviewStatus.rejected ||
        (decision == AiCandidateDecision.accept && candidate.status != AiCandidateReviewStatus.pending)) {
      _safeMessage = 'This candidate is unavailable or has already been reviewed. Reload the current extraction.';
      _notify();
      return;
    }
    if (decision == AiCandidateDecision.accept && !review.canAccept(position)) {'''
assert old in s;s=s.replace(old,new)
old='''    if (isBusy ||
        _status != ServerAiWorkspaceStatus.reviewRequired ||
        !_requireUse()) {
      return null;
    }'''
new='''    if (!_requireUse() || isBusy) return null;
    if (_status != ServerAiWorkspaceStatus.reviewRequired) {
      _safeMessage = 'Complete the AI candidate review first.';
      _notify();
      return null;
    }'''
assert old in s;s=s.replace(old,new)
start=s.index('  AiReviewHandoff? buildReviewHandoff()');end=s.index('  Future<void> clearExtraction()',start)
part=s[start:end].replace("_setFailure('Complete the AI candidate review first.');", "_safeMessage = 'Complete the AI candidate review first.';\n      _notify();").replace('_setFailure(error.safeMessage);', '_safeMessage = error.safeMessage;\n      _notify();')
s=s[:start]+part+s[end:];p.write_text(s)
p=Path('lib/features/data_governance/infrastructure/platform_data_export_ios_channel.dart');p.write_text(p.read_text().replace("import 'dart:typed_data';\n\n",''))
p=Path('test/features/ai_integration/server_ai_workspace_controller_test.dart');s=p.read_text()
s=s.replace('''  FakeGateway? gateway,
}) => ServerAiWorkspaceController(''','''  FakeGateway? gateway,
  String? stockTarget = 'open-count-1',
}) => ServerAiWorkspaceController(
  stockCountTarget: () => stockTarget,''')
s=s.replace("expect(controller.safeMessage, contains('another device'));\n        repository.reviewError = StateError", "expect(controller.safeMessage, contains('Current evidence has been reloaded'));\n        expect(controller.status, ServerAiWorkspaceStatus.reviewRequired);\n        repository.reviewError = StateError")
s=s.replace("'The review decision was not saved safely.',", "contains('Current evidence has been reloaded'),")
s=s.replace("expect(controller.safeMessage, contains('unsafe or unexpected'));\n      },\n    );\n\n    test('all-rejected", "expect(controller.safeMessage, contains('Current evidence has been reloaded'));\n        expect(controller.review?.homeId, 'home-1');\n        expect(repository.inventoryOrPurchaseMutationCalls, 0);\n      },\n    );\n\n    test('all-rejected")
anchor="  test('role loss discards prepared bytes and blocks review', () async {"
assert anchor in s;s=s.replace(anchor,"""  test('stock extraction requires an existing open count before sending bytes', () async {
    final repository = _ServerRepository(_workspace());
    final gateway = FakeGateway(route: AiGatewayRoute.serverProxyCloud);
    final media = FakeMediaPreparation(preparedBatch(purpose: AiExtractionKind.stockPhoto));
    final controller = _controller(repository: repository, gateway: gateway, media: media, stockTarget: null);
    addTearDown(controller.dispose);
    await _loadPrepareConsentExtract(controller, asset: _asset(purpose: AiExtractionKind.stockPhoto));
    expect(gateway.requests, isEmpty);
    expect(controller.stockProposal, isNull);
    expect(repository.inventoryOrPurchaseMutationCalls, 0);
  });

"""+anchor)
p.write_text(s)
