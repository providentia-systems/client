/// Explicit composition facts for shopping interactions.
///
/// The default matches the current protocol-v2 local-first adapter: manual
/// lines can be created with a quantity, but existing quantities, online
/// suggestions, and suggestion feedback are not published by that adapter.
final class ShoppingInteractionCapabilities {
  const ShoppingInteractionCapabilities({
    required this.canEditExistingQuantities,
    required this.canRecordSuggestionFeedback,
    required this.onlineSuggestionsComposed,
  });

  static const localManualOnly = ShoppingInteractionCapabilities(
    canEditExistingQuantities: false,
    canRecordSuggestionFeedback: false,
    onlineSuggestionsComposed: false,
  );

  static const onlineEvidenceSuggestions = ShoppingInteractionCapabilities(
    // Candidate quantities are editable before Add to list. Existing persisted
    // line edits remain disabled until the protocol-v2 adapter supports them.
    canEditExistingQuantities: false,
    // The current POST feedback contract has no client idempotency key. Keep
    // production actions closed so a lost response cannot duplicate evidence.
    canRecordSuggestionFeedback: false,
    onlineSuggestionsComposed: true,
  );

  final bool canEditExistingQuantities;
  final bool canRecordSuggestionFeedback;
  final bool onlineSuggestionsComposed;
}
