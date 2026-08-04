import 'package:providentia/features/homes/application/home_ports.dart';
import 'package:providentia/features/homes/domain/home_models.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

/// Home and membership adapter for the published Laminas API 1.7 contract.
final class Api17HomeTransport implements HomeTransportPort {
  const Api17HomeTransport(this._client);

  final ProvidentiaApiClient _client;

  @override
  Future<List<HomeSummary>> listHomes() async {
    try {
      final object = (await _client.listHomes()).requireObject();
      return _data(object).map(_home).toList(growable: false);
    } on ProvidentiaApiException catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<HomeSummary> createHome(CreateHomeCommand command) async {
    try {
      final response = await _client.createHome(
        body: <String, Object?>{
          'name': command.name,
          'locale': command.locale,
          'currency': command.currency,
          'timezone': command.timezone,
        },
      );
      return _home(response.body);
    } on ProvidentiaApiException catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<HomeSummary> switchActiveHome(String homeId) async {
    try {
      return _home((await _client.switchHome(homeId: homeId)).body);
    } on ProvidentiaApiException catch (error) {
      throw _failure(error, homeId: homeId);
    }
  }

  @override
  Future<List<HomeMembership>> listMemberships(String homeId) async {
    try {
      final object = (await _client.listHomeMemberships(
        homeId: homeId,
      )).requireObject();
      return _data(object).map(_membership).toList(growable: false);
    } on ProvidentiaApiException catch (error) {
      throw _failure(error, homeId: homeId);
    }
  }

  @override
  Future<void> changeMembershipRole({
    required String homeId,
    required String userId,
    required HomeRole role,
    required int expectedRevision,
  }) async {
    try {
      await _client.changeHomeMembershipRole(
        homeId: homeId,
        userId: userId,
        body: <String, Object?>{
          'role': _roleName(role),
          'expectedRevision': expectedRevision,
        },
      );
    } on ProvidentiaApiException catch (error) {
      throw _failure(error, homeId: homeId);
    }
  }

  /// API 1.7 can create and accept invitations but cannot list them.
  Future<List<HomeInvitation>> listInvitations(String homeId) async =>
      const <HomeInvitation>[];

  @override
  Future<HomeInvitation> createInvitation({
    required String homeId,
    required String email,
    required HomeRole role,
  }) async {
    if (role == HomeRole.owner) {
      throw const HomeTransportException(
        kind: HomeFailureKind.validation,
        safeMessage: 'Ownership must be transferred, not invited.',
      );
    }
    try {
      final object = (await _client.createHomeInvitation(
        homeId: homeId,
        body: <String, Object?>{'email': email, 'role': _roleName(role)},
      )).requireObject();
      return HomeInvitation(
        id: _string(object, 'invitationId'),
        homeId: homeId,
        email: email,
        role: role,
        status: InvitationStatus.pending,
        expiresAt: _dateTime(object, 'expiresAt'),
        revision: 1,
      );
    } on ProvidentiaApiException catch (error) {
      throw _failure(error, homeId: homeId);
    }
  }

  Future<void> revokeInvitation({
    required String homeId,
    required String invitationId,
    required int expectedRevision,
  }) {
    throw HomeTransportException(
      kind: HomeFailureKind.unavailable,
      homeId: homeId,
      safeMessage:
          'Invitation revocation is awaiting a published backend operation.',
    );
  }

  @override
  Future<HomeSummary> acceptInvitation(String token) async {
    final before = await listHomes();
    try {
      final response = await _client.acceptHomeInvitation(
        body: <String, Object?>{'token': token},
      );
      if (response.body case final Map<String, Object?> object) {
        final candidate = object['home'] ?? object;
        try {
          return _home(candidate);
        } on FormatException {
          // The API 1.7 response is intentionally free-form. Resolve the new
          // authorization from the authoritative list below.
        }
      }
      final priorIds = before.map((home) => home.id).toSet();
      final after = await listHomes();
      final added = after.where((home) => !priorIds.contains(home.id)).toList();
      if (added.length == 1) {
        return added.single;
      }
      throw const HomeTransportException(
        kind: HomeFailureKind.unavailable,
        safeMessage: 'The accepted home could not be identified safely.',
      );
    } on ProvidentiaApiException catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> leaveHome(String homeId) async {
    try {
      await _client.leaveHome(homeId: homeId);
    } on ProvidentiaApiException catch (error) {
      throw _failure(error, homeId: homeId);
    }
  }
}

List<Object?> _data(Map<String, Object?> object) {
  final data = object['data'];
  if (data is! List<Object?>) {
    throw const FormatException('Expected a data array.');
  }
  return data;
}

HomeSummary _home(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a home object.');
  }
  return HomeSummary(
    id: _string(value, 'id'),
    name: _string(value, 'name'),
    locale: _optionalString(value['defaultLocale']) ?? 'en-NA',
    currency: _optionalString(value['defaultCurrency']) ?? 'NAD',
    timezone: _optionalString(value['defaultTimezone']) ?? 'Africa/Windhoek',
    role: _role(_optionalString(value['role']) ?? 'member'),
    revision: _integer(value, 'revision'),
  );
}

HomeMembership _membership(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a membership object.');
  }
  return HomeMembership(
    userId: _string(value, 'userId'),
    displayName: _optionalString(value['displayName']) ?? 'Household member',
    role: _role(_string(value, 'role')),
    revision: _integer(value, 'revision'),
  );
}

HomeRole _role(String source) => switch (source) {
  'owner' => HomeRole.owner,
  'manager' => HomeRole.manager,
  'member' => HomeRole.member,
  'viewer' => HomeRole.viewer,
  _ => throw FormatException('Unknown home role $source.'),
};

String _roleName(HomeRole role) => switch (role) {
  HomeRole.owner => 'owner',
  HomeRole.manager => 'manager',
  HomeRole.member => 'member',
  HomeRole.viewer => 'viewer',
};

HomeTransportException _failure(
  ProvidentiaApiException error, {
  String? homeId,
}) {
  final kind = switch (error.statusCode) {
    401 => HomeFailureKind.authentication,
    403 => HomeFailureKind.authorization,
    404 => HomeFailureKind.membershipRevoked,
    409 => HomeFailureKind.conflict,
    400 || 422 => HomeFailureKind.validation,
    >= 500 => HomeFailureKind.unavailable,
    _ => HomeFailureKind.network,
  };
  final message = switch (kind) {
    HomeFailureKind.authentication => 'Sign in again to access your homes.',
    HomeFailureKind.authorization || HomeFailureKind.membershipRevoked =>
      'You no longer have access to this home.',
    HomeFailureKind.conflict =>
      'This home changed on another device. Refresh and try again.',
    HomeFailureKind.validation => 'Check the home details and try again.',
    _ => 'The home service is temporarily unavailable.',
  };
  return HomeTransportException(
    kind: kind,
    safeMessage: message,
    homeId: homeId,
  );
}

String _string(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Missing $key.');
  }
  return value;
}

String? _optionalString(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

int _integer(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  throw FormatException('Missing $key.');
}

DateTime _dateTime(Map<String, Object?> object, String key) {
  final value = DateTime.tryParse(_string(object, key));
  if (value == null) throw FormatException('Invalid $key.');
  return value.toUtc();
}
