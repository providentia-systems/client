/// Searchable item-master text shared by shopping and manual receipt entry.
/// It contains no stock or consumption evidence: zero-stock products remain
/// discoverable and lookup works entirely from the verified offline master.
final class ProductLookupText {
  const ProductLookupText({
    required this.name,
    this.brand = '',
    this.pack = '',
    this.category = '',
    this.aliases = const <String>[],
  });

  final String name;
  final String brand;
  final String pack;
  final String category;
  final Iterable<String> aliases;
}

final class HouseholdProductLookup {
  const HouseholdProductLookup();

  List<T> rank<T>({
    required String query,
    required Iterable<T> products,
    required ProductLookupText Function(T) describe,
  }) {
    final normalized = _normalize(query);
    final matches = <(T, ProductLookupText, int, int)>[];
    var index = 0;
    for (final product in products) {
      final text = describe(product);
      final names = <String>{
        _normalize(text.name),
        for (final alias in text.aliases) _normalize(alias),
        _normalize('${text.brand} ${text.name}'),
        _normalize('${text.name} ${text.brand}'),
      }..remove('');
      final metadata = _normalize(
        '${text.name} ${text.brand} ${text.pack} ${text.category} '
        '${text.aliases.join(' ')}',
      );
      final score = normalized.isEmpty
          ? 1
          : names.contains(normalized)
          ? 1000
          : names.any((name) => name.startsWith(normalized))
          ? 800
          : names.any((name) => name.contains(normalized))
          ? 600
          : normalized.split(' ').every(metadata.contains)
          ? 400
          : 0;
      if (score > 0) matches.add((product, text, score, index));
      index++;
    }
    matches.sort((left, right) {
      final score = right.$3.compareTo(left.$3);
      if (score != 0) return score;
      for (final pair in <(String, String)>[
        (left.$2.name, right.$2.name),
        (left.$2.brand, right.$2.brand),
        (left.$2.pack, right.$2.pack),
      ]) {
        final comparison = pair.$1.toLowerCase().compareTo(
          pair.$2.toLowerCase(),
        );
        if (comparison != 0) return comparison;
      }
      return left.$4.compareTo(right.$4);
    });
    return List<T>.unmodifiable(matches.map((entry) => entry.$1));
  }
}

String _normalize(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[\s\-_,./\\():;]+'), ' ')
    .trim();
