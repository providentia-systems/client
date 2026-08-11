import 'package:providentia/features/shopping/domain/shopping_models.dart';

abstract interface class ShoppingRepository {
  Stream<ShoppingList> watchActiveList({required String homeId});

  /// Saves a published list mutation as one atomic local projection/outbox
  /// transaction.
  ///
  /// Adapters must reject edits and deletes that do not have a corresponding
  /// command in the pinned protocol rather than inventing transport semantics.
  Future<void> saveList(ShoppingList list);

  Future<void> recordFeedback(SuggestionFeedback feedback);
}
