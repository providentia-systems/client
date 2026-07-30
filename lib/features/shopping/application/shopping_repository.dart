import 'package:providentia/features/shopping/domain/shopping_models.dart';

abstract interface class ShoppingRepository {
  Stream<ShoppingList> watchActiveList({required String homeId});

  /// Saves the list locally as one atomic domain change.
  ///
  /// Synchronizing that change requires an explicitly published backend
  /// shopping-list representation; adapters must not invent entity types.
  Future<void> saveList(ShoppingList list);

  Future<void> recordFeedback(SuggestionFeedback feedback);
}
