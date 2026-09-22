import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia/features/inventory/infrastructure/generated_home_item_master_source.dart';
import 'package:providentia_api_client/providentia_api_client.dart' as generated;

abstract interface class PublishedCategorySource {
  Future<List<PublishedInventoryCategory>> loadAll();
}

/// A failed or malformed page never becomes a partially successful snapshot.
final class GeneratedPublishedCategorySource implements PublishedCategorySource {
  const GeneratedPublishedCategorySource(this._client);
  final generated.ProvidentiaApiClient _client;

  @override
  Future<List<PublishedInventoryCategory>> loadAll() async {
    const limit = 100;
    final categories = <PublishedInventoryCategory>[];
    final identifiers = <String>{};
    final uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    );
    for (var offset = 0; offset < 100000; offset += limit) {
      late final generated.ApiResponse response;
      try {
        response = await _client.listPublishedCatalogCategories(
          query: {'limit': '$limit', 'offset': '$offset'},
        );
      } on generated.ProvidentiaApiException {
        // This public endpoint cannot establish that home access was revoked.
        throw const HomeItemMasterSourceException(
          HomeItemMasterSourceFailure.unavailable,
        );
      }
      final body = response.requireObject();
      final data = body['data'];
      final pagination = body['pagination'];
      if (data is! List<Object?> ||
          data.length > limit ||
          pagination is! Map<String, Object?> ||
          pagination['limit'] != limit ||
          pagination['offset'] != offset) {
        throw const FormatException('The published category page is invalid.');
      }
      for (final row in data) {
        if (row is! Map<String, Object?>) {
          throw const FormatException('The published category is invalid.');
        }
        final id = row['id'];
        final name = row['canonicalName'];
        final revision = row['revision'];
        if (id is! String || !uuid.hasMatch(id) ||
            name is! String || name.trim().isEmpty || name.length > 191 ||
            revision is! int || revision < 1 || !identifiers.add(id)) {
          throw const FormatException('The published category is invalid or duplicated.');
        }
        categories.add(PublishedInventoryCategory(
          id: id, name: name.trim(), revision: revision,
        ));
      }
      if (data.length < limit) {
        return List<PublishedInventoryCategory>.unmodifiable(categories);
      }
    }
    throw const FormatException('The published category list did not terminate.');
  }
}
