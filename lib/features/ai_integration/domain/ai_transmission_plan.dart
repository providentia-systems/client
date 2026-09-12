/// Safe recipient snapshot issued by the backend. The opaque hash is scoped to
/// the authenticated person and home and checked before provider execution.
final class AiTransmissionPlan {
  AiTransmissionPlan({
    required this.settingsRevision,
    required this.policyRevision,
    required List<AiTransmissionRecipient> extractionProfiles,
    required this.validationProfile,
    required this.sha256,
  }) : extractionProfiles = List.unmodifiable(extractionProfiles) {
    if (settingsRevision < 0 ||
        policyRevision < 0 ||
        extractionProfiles.isEmpty ||
        extractionProfiles.length > 4 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256)) {
      throw const FormatException('Invalid AI transmission plan.');
    }
  }

  factory AiTransmissionPlan.fromJson(Map<String, Object?> json) {
    final profiles = json['extractionProfiles'];
    final validator = json['validationProfile'];
    if (json.length != 5 ||
        !json.containsKey('validationProfile') ||
        json['settingsRevision'] is! int ||
        json['policyRevision'] is! int ||
        json['sha256'] is! String ||
        profiles is! List<Object?> ||
        (validator != null && validator is! Map<String, Object?>)) {
      throw const FormatException('Invalid AI transmission plan.');
    }
    return AiTransmissionPlan(
      settingsRevision: json['settingsRevision']! as int,
      policyRevision: json['policyRevision']! as int,
      extractionProfiles: profiles.map((value) {
        if (value is! Map<String, Object?>) {
          throw const FormatException('Invalid AI transmission recipient.');
        }
        return AiTransmissionRecipient.fromJson(value);
      }).toList(),
      validationProfile: validator == null
          ? null
          : AiTransmissionRecipient.fromJson(validator as Map<String, Object?>),
      sha256: json['sha256']! as String,
    );
  }

  final int settingsRevision;
  final int policyRevision;
  final List<AiTransmissionRecipient> extractionProfiles;
  final AiTransmissionRecipient? validationProfile;
  final String sha256;

  AiTransmissionRecipient get primary => extractionProfiles.first;

  List<String> get recipientDescriptions => <String>[
    for (var index = 0; index < extractionProfiles.length; index++)
      '${index == 0 ? 'Primary' : 'Fallback'}: ${extractionProfiles[index].description}',
    if (validationProfile case final validator?)
      'Validation: ${validator.description}',
  ];
}

final class AiTransmissionRecipient {
  const AiTransmissionRecipient({
    required this.profileId,
    required this.revision,
    required this.provider,
    required this.model,
    required this.endpoint,
  });

  factory AiTransmissionRecipient.fromJson(Map<String, Object?> json) {
    final id = json['profileId'];
    final revision = json['revision'];
    final provider = json['provider'];
    final model = json['model'];
    final endpoint = json['endpoint'];
    if (json.length != 5 ||
        !json.containsKey('profileId') ||
        !json.containsKey('endpoint') ||
        (id != null && (id is! String || id.isEmpty)) ||
        revision is! int ||
        revision < 0 ||
        provider is! String ||
        provider.trim().isEmpty ||
        model is! String ||
        model.trim().isEmpty ||
        (endpoint != null && endpoint is! String)) {
      throw const FormatException('Invalid AI transmission recipient.');
    }
    return AiTransmissionRecipient(
      profileId: id as String?,
      revision: revision,
      provider: provider,
      model: model,
      endpoint: endpoint as String?,
    );
  }

  final String? profileId;
  final int revision;
  final String provider;
  final String model;
  final String? endpoint;

  String get description =>
      '$provider · $model'
      '${endpoint == null ? '' : ' · $endpoint'}';
}
