final class HomeLocation {
  const HomeLocation({
    required this.id,
    required this.name,
    required this.kind,
    required this.revision,
    required this.archived,
  });

  final String id;
  final String name;
  final String kind;
  final int revision;
  final bool archived;

  static const kinds = [
    'pantry',
    'shelf',
    'fridge',
    'freezer',
    'household',
    'other',
  ];
}

/// Location metadata uses the same durable sync boundary as count sessions.
abstract interface class HomeLocationRepository {
  bool get supportsHomeLocations;
  Stream<List<HomeLocation>> watchHomeLocations(String homeId);
  Future<void> saveHomeLocation({
    required String homeId,
    String? locationId,
    required String name,
    required String kind,
    required bool archived,
    int? expectedRevision,
  });
}
