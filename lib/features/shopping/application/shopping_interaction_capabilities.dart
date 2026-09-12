/// Explicit composition facts for shopping interactions.
///
/// The default matches the current protocol-v2 local-first adapter: manual
/// lines and quantity edits use durable commands. Suggestion feedback needs
/// its own retry-safe transport before production composition can enable it.
final class ShoppingInteractionCapabilities {
  const ShoppingInteractionCapabilities({
    required this.canEditExistingQuantities,
    required this.canRecordSuggestionFeedback,
    required this.onlineSuggestionsComposed,
    this.recordsSuggestionAcceptanceWithList = false,
  });

  static const localManualOnly = ShoppingInteractionCapabilities(
    canEditExistingQuantities: true,
    canRecordSuggestionFeedback: false,
    onlineSuggestionsComposed: false,
  );

  static const onlineEvidenceSuggestions = ShoppingInteractionCapabilities(
    // Persisted edits use revision-checked durable protocol-v2 commands.
    canEditExistingQuantities: true,
    // The current POST feedback contract has no client idempotency key. Keep
    // production actions closed so a lost response cannot duplicate evidence.
    canRecordSuggestionFeedback: false,
    onlineSuggestionsComposed: true,
  );

  static const durableEvidenceSuggestions = ShoppingInteractionCapabilities(
    canEditExistingQuantities: true,
    canRecordSuggestionFeedback: true,
    onlineSuggestionsComposed: true,
    recordsSuggestionAcceptanceWithList: true,
  );

  final bool recordsSuggestionAcceptanceWithList;
  final bool canEditExistingQuantities;
  final bool canRecordSuggestionFeedback;
  final bool onlineSuggestionsComposed;
}
