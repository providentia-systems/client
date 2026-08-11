import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/shopping/application/online_shopping_suggestion_repository.dart';
import 'package:providentia/features/shopping/application/shopping_interaction_capabilities.dart';
import 'package:providentia/features/shopping/application/shopping_repository.dart';
import 'package:providentia/features/shopping/domain/online_shopping_suggestion_models.dart';
import 'package:providentia/features/shopping/domain/shopping_models.dart';
import 'package:providentia/features/shopping/presentation/shopping_controller.dart';
import 'package:providentia/features/shopping/presentation/shopping_workspace.dart';

void main() {
  testWidgets('manual item is trimmed, saved, and check-off updates progress', (
    tester,
  ) async {
    final repository = _ShoppingRepository(_list());
    final controller = ShoppingController(
      repository: repository,
      homeId: 'home-a',
      idGenerator: () => 'manual-1',
      clock: () => DateTime.utc(2026, 7, 30),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ShoppingWorkspace(controller: controller)),
      ),
    );
    repository.emit();
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('manual-list-input')),
      '  Tea  ',
    );
    await tester.enterText(
      find.byKey(const Key('manual-list-quantity')),
      '2.5',
    );
    await tester.tap(find.byKey(const Key('manual-list-add')));
    await tester.pump();
    expect(repository.current.lines.single.name, 'Tea');
    expect(repository.current.lines.single.quantity, 2.5);
    repository.emit();
    await tester.pump();
    expect(find.text('Tea'), findsOneWidget);
    expect(find.text('Manual'), findsOneWidget);
    expect(find.text('Quantity: 2.50'), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    repository.emit();
    await tester.pump();
    expect(find.text('1/1 complete'), findsOneWidget);

    controller.dispose();
    await repository.close();
  });

  test('controller rejects a repository stream from another home', () async {
    final repository = _ShoppingRepository(
      ShoppingList(
        id: 'foreign',
        homeId: 'home-b',
        name: 'Foreign',
        createdAt: DateTime.utc(2026),
      ),
    );
    final controller = ShoppingController(
      repository: repository,
      homeId: 'home-a',
    );
    controller.start();
    repository.emit();
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.safeError, contains('rejected'));
    controller.dispose();
    await repository.close();
  });

  testWidgets(
    'suggestion is labelled and explanation works while feedback stays honest',
    (tester) async {
      final repository = _ShoppingRepository(
        _list().add(_suggestion(explanation: 'Low stock after two counts.')),
      );
      final controller = ShoppingController(
        repository: repository,
        homeId: 'home-a',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ShoppingWorkspace(controller: controller)),
        ),
      );
      repository.emit();
      await tester.pump();

      expect(find.text('Suggested'), findsOneWidget);
      expect(
        find.text('Suggestion feedback is not available in this workspace.'),
        findsOneWidget,
      );
      expect(find.text('Useful'), findsNothing);
      await tester.tap(
        find.byKey(const Key('shopping-explanation-suggestion-1')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Why this was suggested'), findsWidgets);
      expect(find.text('Low stock after two counts.'), findsOneWidget);

      controller.dispose();
      await repository.close();
    },
  );

  testWidgets('capability enables quantity editing and real feedback calls', (
    tester,
  ) async {
    final repository = _ShoppingRepository(
      _list().add(_suggestion(explanation: 'Reliable usage interval.')),
    );
    var id = 0;
    final controller = ShoppingController(
      repository: repository,
      homeId: 'home-a',
      idGenerator: () => 'feedback-${++id}',
      clock: () => DateTime.utc(2026, 8, 11),
      capabilities: const ShoppingInteractionCapabilities(
        canEditExistingQuantities: true,
        canRecordSuggestionFeedback: true,
        onlineSuggestionsComposed: false,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ShoppingWorkspace(controller: controller)),
      ),
    );
    repository.emit();
    await tester.pump();

    await tester.tap(
      find.byKey(const Key('edit-shopping-quantity-suggestion-1')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('shopping-quantity-editor-suggestion-1')),
      '4',
    );
    await tester.tap(
      find.byKey(const Key('save-shopping-quantity-suggestion-1')),
    );
    await tester.pumpAndSettle();

    expect(repository.current.lines.single.quantity, 4);
    expect(repository.feedback, hasLength(1));
    expect(
      repository.feedback.single.kind,
      SuggestionFeedbackKind.quantityEdited,
    );
    expect(repository.feedback.single.originalQuantity, 2);
    expect(repository.feedback.single.updatedQuantity, 4);

    await tester.tap(find.byKey(const Key('accept-suggestion-suggestion-1')));
    await tester.pumpAndSettle();
    expect(repository.feedback, hasLength(2));
    expect(repository.feedback.last.kind, SuggestionFeedbackKind.accepted);
    expect(find.text('Suggestion feedback recorded.'), findsOneWidget);

    controller.dispose();
    await repository.close();
  });

  testWidgets(
    'empty workspace does not claim online suggestions are composed',
    (tester) async {
      final repository = _ShoppingRepository(_list());
      final controller = ShoppingController(
        repository: repository,
        homeId: 'home-a',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ShoppingWorkspace(controller: controller)),
        ),
      );
      repository.emit();
      await tester.pump();

      expect(find.text('Online suggestions are not connected'), findsOneWidget);
      expect(find.textContaining('appear after'), findsNothing);

      controller.dispose();
      await repository.close();
    },
  );

  testWidgets(
    'online suggestion stays separate, explains limits, and adds exactly once',
    (tester) async {
      final repository = _ShoppingRepository(_list());
      final suggestion = _onlineSuggestion();
      final online = _OnlineSuggestionRepository(
        ShoppingSuggestionFeed(
          suggestions: <OnlineShoppingSuggestion>[suggestion],
          fromVerifiedCache: false,
          verifiedAt: DateTime.utc(2026, 8, 11, 12),
        ),
      );
      final controller = ShoppingController(
        repository: repository,
        suggestionRepository: online,
        capabilities: ShoppingInteractionCapabilities.onlineEvidenceSuggestions,
        homeId: 'home-a',
        clock: () => DateTime.utc(2026, 8, 11, 13),
        idGenerator: () => 'line-from-suggestion',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ShoppingWorkspace(controller: controller)),
        ),
      );
      repository.emit();
      await tester.pumpAndSettle();

      expect(repository.current.lines, isEmpty);
      expect(find.text('Evidence-based · legacy'), findsOneWidget);
      expect(find.textContaining('Limited evidence'), findsOneWidget);
      expect(find.textContaining('stay separate'), findsOneWidget);
      expect(find.textContaining('retry-safe support'), findsOneWidget);
      expect(find.text('Dismiss'), findsNothing);
      expect(find.text('Snooze'), findsNothing);

      await tester.tap(
        find.byKey(Key('online-suggestion-explanation-${suggestion.id}')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Limitations'), findsOneWidget);
      expect(find.text('• Only one reliable count interval.'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(Key('add-online-suggestion-${suggestion.id}')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(Key('online-suggestion-quantity-${suggestion.id}')),
        '4',
      );
      await tester.tap(
        find.byKey(Key('confirm-add-online-suggestion-${suggestion.id}')),
      );
      await tester.pumpAndSettle();

      final line = repository.current.lines.single;
      expect(line.id, 'line-from-suggestion');
      expect(line.origin, ShoppingLineOrigin.suggestion);
      expect(line.suggestionId, suggestion.id);
      expect(line.homeProductId, suggestion.homeProductId);
      expect(line.selectedPackId, suggestion.selectedPackId);
      // ignore: deprecated_member_use_from_same_package
      expect(line.productPackId, isNull);
      expect(line.quantity, 4);
      expect(online.feedback, isEmpty);
      expect(
        find.byKey(Key('online-shopping-suggestion-${suggestion.id}')),
        findsNothing,
      );

      expect(await controller.addOnlineSuggestion(suggestion), isFalse);
      expect(repository.current.lines, hasLength(1));

      controller.dispose();
      await repository.close();
    },
  );

  test(
    'production online capability never posts non-idempotent feedback',
    () async {
      final repository = _ShoppingRepository(_list());
      final suggestion = _onlineSuggestion();
      final online = _OnlineSuggestionRepository(
        ShoppingSuggestionFeed(
          suggestions: <OnlineShoppingSuggestion>[suggestion],
          fromVerifiedCache: false,
          verifiedAt: DateTime.utc(2026, 8, 11),
        ),
      );
      final controller = ShoppingController(
        repository: repository,
        suggestionRepository: online,
        capabilities: ShoppingInteractionCapabilities.onlineEvidenceSuggestions,
        homeId: 'home-a',
        clock: () => DateTime.utc(2026, 8, 11, 13),
        idGenerator: () => 'line-from-suggestion',
      );
      controller.start();
      repository.emit();
      await controller.refreshSuggestions();

      expect(
        await controller.decideOnlineSuggestion(
          suggestion,
          OnlineSuggestionDecision.dismissed,
        ),
        isFalse,
      );
      expect(online.feedback, isEmpty);
      expect(controller.state.suggestions, contains(suggestion));
      expect(await controller.addOnlineSuggestion(suggestion), isTrue);
      expect(online.feedback, isEmpty);

      controller.dispose();
      await repository.close();
    },
  );

  test('online composition and home boundary fail closed', () async {
    expect(
      () => ShoppingController(
        repository: _ShoppingRepository(_list()),
        homeId: 'home-a',
        capabilities: ShoppingInteractionCapabilities.onlineEvidenceSuggestions,
      ),
      throwsArgumentError,
    );

    final repository = _ShoppingRepository(_list());
    final online = _OnlineSuggestionRepository(
      ShoppingSuggestionFeed(
        suggestions: <OnlineShoppingSuggestion>[
          _onlineSuggestion(homeId: 'home-b'),
        ],
        fromVerifiedCache: false,
        verifiedAt: DateTime.utc(2026, 8, 11),
      ),
    );
    final controller = ShoppingController(
      repository: repository,
      suggestionRepository: online,
      capabilities: ShoppingInteractionCapabilities.onlineEvidenceSuggestions,
      homeId: 'home-a',
      clock: () => DateTime.utc(2026, 8, 11, 13),
    );
    controller.start();
    repository.emit();
    await controller.refreshSuggestions();

    expect(controller.state.suggestions, isEmpty);
    expect(controller.state.safeError, contains('rejected'));

    controller.dispose();
    await repository.close();
  });

  test('feedback authorization change hides active home suggestions', () async {
    final repository = _ShoppingRepository(_list());
    final suggestion = _onlineSuggestion();
    final online = _OnlineSuggestionRepository(
      ShoppingSuggestionFeed(
        suggestions: <OnlineShoppingSuggestion>[suggestion],
        fromVerifiedCache: false,
        verifiedAt: DateTime.utc(2026, 8, 11),
      ),
    );
    final controller = ShoppingController(
      repository: repository,
      suggestionRepository: online,
      capabilities: const ShoppingInteractionCapabilities(
        canEditExistingQuantities: false,
        canRecordSuggestionFeedback: true,
        onlineSuggestionsComposed: true,
      ),
      homeId: 'home-a',
      clock: () => DateTime.utc(2026, 8, 11, 13),
    );
    controller.start();
    repository.emit();
    await controller.refreshSuggestions();
    expect(controller.state.suggestions, hasLength(1));

    online.failure = const OnlineSuggestionException(
      OnlineSuggestionFailureKind.authenticationRequired,
    );
    expect(
      await controller.decideOnlineSuggestion(
        suggestion,
        OnlineSuggestionDecision.dismissed,
      ),
      isFalse,
    );
    expect(controller.state.suggestions, isEmpty);
    expect(controller.state.safeError, contains('Sign in again'));

    controller.dispose();
    await repository.close();
  });

  test(
    'online authorization denial is terminal and reports the boundary once',
    () async {
      final repository = _ShoppingRepository(_list());
      final online =
          _OnlineSuggestionRepository(
              ShoppingSuggestionFeed(
                suggestions: const <OnlineShoppingSuggestion>[],
                fromVerifiedCache: false,
                verifiedAt: DateTime.utc(2026, 8, 11),
              ),
            )
            ..failure = const OnlineSuggestionException(
              OnlineSuggestionFailureKind.authorizationDenied,
            );
      var authorizationDenials = 0;
      final controller = ShoppingController(
        repository: repository,
        suggestionRepository: online,
        capabilities: ShoppingInteractionCapabilities.onlineEvidenceSuggestions,
        homeId: 'home-a',
        onAuthorizationDenied: () async {
          authorizationDenials++;
        },
      );

      await controller.refreshSuggestions();
      await Future<void>.delayed(Duration.zero);
      await controller.refreshSuggestions();

      expect(controller.state.suggestionsAccessDenied, isTrue);
      expect(controller.state.suggestions, isEmpty);
      expect(controller.state.safeError, contains('no longer available'));
      expect(authorizationDenials, 1);
      expect(online.listCalls, 1);

      controller.dispose();
      await repository.close();
    },
  );
}

ShoppingList _list() => ShoppingList(
  id: 'list',
  homeId: 'home-a',
  name: 'Weekly',
  createdAt: DateTime.utc(2026),
);

ShoppingListLine _suggestion({String? explanation}) => ShoppingListLine(
  id: 'suggestion-1',
  homeId: 'home-a',
  name: 'Milk',
  quantity: 2,
  origin: ShoppingLineOrigin.suggestion,
  createdAt: DateTime.utc(2026, 8, 10),
  productPackId: 'home-product-1',
  explanation: explanation,
);

OnlineShoppingSuggestion _onlineSuggestion({String homeId = 'home-a'}) =>
    OnlineShoppingSuggestion(
      id: '0198a0b1-c2d3-7e4f-a345-6789abcdef01',
      homeId: homeId,
      homeProductId: '0198a0b1-c2d3-7e4f-b456-789abcdef012',
      productName: 'Rolled oats',
      packText: '1 kg',
      expectedDemand: ExactDecimal('4'),
      safetyStock: ExactDecimal('1'),
      factualStock: ExactDecimal('2'),
      usableStock: ExactDecimal('2'),
      requiredQuantity: ExactDecimal('3'),
      selectedPackId: '0198a0b1-c2d3-7e4f-9567-89abcdef0123',
      packCount: 3,
      confidenceScore: ExactDecimal('0.25'),
      confidenceBand: ShoppingSuggestionConfidenceBand.low,
      status: OnlineShoppingSuggestionStatus.active,
      expiresAt: DateTime.utc(2026, 8, 12),
      modelVersion: 'suggestion-v1',
      asOf: DateTime.utc(2026, 8, 11, 12),
      inputWatermark:
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    );

class _ShoppingRepository implements ShoppingRepository {
  _ShoppingRepository(this.current);

  final controller = StreamController<ShoppingList>.broadcast();
  ShoppingList current;
  final List<SuggestionFeedback> feedback = <SuggestionFeedback>[];

  void emit() => controller.add(current);

  @override
  Stream<ShoppingList> watchActiveList({required String homeId}) =>
      controller.stream;

  @override
  Future<void> saveList(ShoppingList list) async {
    current = list;
  }

  @override
  Future<void> recordFeedback(SuggestionFeedback value) async {
    feedback.add(value);
  }

  Future<void> close() => controller.close();
}

final class _OnlineSuggestionRepository
    implements OnlineShoppingSuggestionRepository {
  _OnlineSuggestionRepository(this.feed);

  ShoppingSuggestionFeed feed;
  OnlineSuggestionException? failure;
  var listCalls = 0;
  final List<OnlineSuggestionFeedback> feedback = <OnlineSuggestionFeedback>[];

  @override
  Future<ShoppingSuggestionFeed> list({required String homeId}) async {
    listCalls++;
    final currentFailure = failure;
    if (currentFailure != null) throw currentFailure;
    return feed;
  }

  @override
  Future<OnlineShoppingSuggestionExplanation> explanation({
    required String homeId,
    required String suggestionId,
  }) async {
    final suggestion = feed.suggestions.singleWhere(
      (candidate) => candidate.id == suggestionId,
    );
    return OnlineShoppingSuggestionExplanation(
      id: suggestion.id,
      homeId: suggestion.homeId,
      homeProductId: suggestion.homeProductId,
      requiredQuantity: suggestion.requiredQuantity,
      confidenceScore: suggestion.confidenceScore,
      confidenceBand: suggestion.confidenceBand,
      factors: <ShoppingSuggestionFactor>[
        ShoppingSuggestionFactor(
          key: 'expected-demand',
          value: suggestion.expectedDemand,
          days: 7,
        ),
      ],
      limitations: <String>['Only one reliable count interval.'],
      packOptions: const <SuggestionPackOption>[],
      modelVersion: suggestion.modelVersion,
      asOf: suggestion.asOf,
      inputWatermark: suggestion.inputWatermark,
    );
  }

  @override
  Future<OnlineSuggestionFeedbackReceipt> recordFeedback(
    OnlineSuggestionFeedback value,
  ) async {
    final currentFailure = failure;
    if (currentFailure != null) throw currentFailure;
    feedback.add(value);
    return const OnlineSuggestionFeedbackReceipt(id: 'feedback-receipt');
  }
}
