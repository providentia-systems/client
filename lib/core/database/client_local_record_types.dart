/// Reserved Drift record types that are local-only and must never be accepted
/// from, or removed by, a synchronization bootstrap.
abstract final class ClientLocalRecordTypes {
  static const String itemMasterCache = 'inventory-item-master-product';
  static const String shoppingSuggestionCache = 'shopping-suggestion-cache-v1';
  static const String shoppingSuggestionLineLink =
      'shopping-suggestion-line-link-v1';
  static const String strictLocalAiConfiguration =
      'client.local-ai-provider.configuration-v1';
  static const String strictLocalAiSelection =
      'client.local-ai-provider.selection-v1';

  static const Set<String> synchronizationProtected = <String>{
    itemMasterCache,
    shoppingSuggestionCache,
    shoppingSuggestionLineLink,
    strictLocalAiConfiguration,
    strictLocalAiSelection,
  };
}
