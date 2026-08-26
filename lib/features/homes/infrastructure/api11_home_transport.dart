import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:providentia/features/homes/application/home_ports.dart';
import 'package:providentia/features/homes/domain/home_models.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

final class Api11HomeTransport implements HomeTransportPort {
  const Api11HomeTransport(
    this._client, {
    this.requestTimeout = const Duration(seconds: 15),
  });

  final ProvidentiaApiClient _client;
  final Duration requestTimeout;

  @override
  Future<List<HomeSummary>> listHomes() => _run(
    (abortTrigger) async => _data(
      (await _invoke(
        operationId: 'listHomes',
        abortTrigger: abortTrigger,
      )).requireObject(),
    ).map(_home).toList(growable: false),
  );

  @override
  Future<HomeSummary> createHome(CreateHomeCommand command) => _run(
    (abortTrigger) async => _home(
      (await _invoke(
        operationId: 'createHome',
        abortTrigger: abortTrigger,
        body: <String, Object?>{
          'name': command.name,
          'locale': command.locale,
          'currency': command.currency,
          'timezone': command.timezone,
        },
      )).body,
    ),
  );

  @override
  Future<HomeSummary> switchActiveHome(String homeId) => _run(
    (abortTrigger) async => _home(
      (await _invoke(
        operationId: 'switchHome',
        pathParameters: <String, String>{'homeId': homeId},
        abortTrigger: abortTrigger,
      )).body,
    ),
    homeId: homeId,
    treatNotFoundAsRevoked: true,
    treatForbiddenAsRevoked: true,
  );

  @override
  Future<HomeSummary> updateHome({
    required String homeId,
    required String name,
    required String locale,
    required String currency,
    required String timezone,
    required int expectedRevision,
  }) => _run(
    (abortTrigger) async => _home(
      (await _invoke(
        operationId: 'updateHome',
        pathParameters: <String, String>{'homeId': homeId},
        abortTrigger: abortTrigger,
        body: <String, Object?>{
          'name': name,
          'locale': locale,
          'currency': currency,
          'timezone': timezone,
          'expectedRevision': expectedRevision,
        },
      )).body,
    ),
    homeId: homeId,
    treatNotFoundAsRevoked: true,
  );

  @override
  Future<List<HomeMembership>> listMemberships(String homeId) => _run(
    (abortTrigger) async => _data(
      (await _invoke(
        operationId: 'listHomeMemberships',
        pathParameters: <String, String>{'homeId': homeId},
        abortTrigger: abortTrigger,
      )).requireObject(),
    ).map(_membership).toList(growable: false),
    homeId: homeId,
    treatNotFoundAsRevoked: true,
  );

  @override
  Future<void> changeMembershipRole({
    required String homeId,
    required String userId,
    required HomeRole role,
    required int expectedRevision,
  }) => _run(
    (abortTrigger) async {
      await _invoke(
        operationId: 'changeHomeMembershipRole',
        pathParameters: <String, String>{'homeId': homeId, 'userId': userId},
        abortTrigger: abortTrigger,
        body: <String, Object?>{
          'role': _roleName(role),
          'expectedRevision': expectedRevision,
        },
      );
    },
    homeId: homeId,
    conflictMessage:
        'This member is no longer available. Refresh and try again.',
  );

  @override
  Future<List<HomeInvitation>> listInvitations(String homeId) => _run(
    (abortTrigger) async => _data(
      (await _invoke(
        operationId: 'listHomeInvitations',
        pathParameters: <String, String>{'homeId': homeId},
        abortTrigger: abortTrigger,
      )).requireObject(),
    ).map(_invitation).toList(growable: false),
    homeId: homeId,
    treatNotFoundAsRevoked: true,
  );

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
    return _run(
      (abortTrigger) async {
        final object = (await _invoke(
          operationId: 'createHomeInvitation',
          pathParameters: <String, String>{'homeId': homeId},
          abortTrigger: abortTrigger,
          body: <String, Object?>{'email': email, 'role': _roleName(role)},
        )).requireObject();
        if (_string(object, 'delivery') != 'transactional-email') {
          throw const FormatException('Unknown invitation delivery.');
        }
        return HomeInvitation(
          id: _uuid(object, 'invitationId'),
          homeId: homeId,
          email: email,
          role: role,
          status: InvitationStatus.pending,
          expiresAt: _dateTime(object, 'expiresAt'),
          revision: _integer(object, 'revision'),
        );
      },
      homeId: homeId,
      treatNotFoundAsRevoked: true,
    );
  }

  @override
  Future<void> revokeInvitation({
    required String homeId,
    required String invitationId,
    required int expectedRevision,
  }) => _run(
    (abortTrigger) async {
      await _invoke(
        operationId: 'revokeHomeInvitation',
        pathParameters: <String, String>{
          'homeId': homeId,
          'invitationId': invitationId,
        },
        abortTrigger: abortTrigger,
        body: <String, Object?>{'expectedRevision': expectedRevision},
      );
    },
    homeId: homeId,
    conflictMessage:
        'This invitation is no longer available. Refresh and try again.',
  );

  @override
  Future<void> removeHomeMembership({
    required String homeId,
    required String userId,
    required int expectedRevision,
  }) => _run(
    (abortTrigger) async {
      await _invoke(
        operationId: 'removeHomeMembership',
        pathParameters: <String, String>{'homeId': homeId, 'userId': userId},
        query: <String, String>{'expectedRevision': '$expectedRevision'},
        abortTrigger: abortTrigger,
      );
    },
    homeId: homeId,
    conflictMessage:
        'This member is no longer available. Refresh and try again.',
  );

  @override
  Future<List<HomeOwnershipTransfer>> listHomeOwnershipTransfers(
    String homeId,
  ) => _run(
    (abortTrigger) async => _data(
      (await _invoke(
        operationId: 'listHomeOwnershipTransfers',
        pathParameters: <String, String>{'homeId': homeId},
        abortTrigger: abortTrigger,
      )).requireObject(),
    ).map(_ownershipTransfer).toList(growable: false),
    homeId: homeId,
    treatNotFoundAsRevoked: true,
  );

  @override
  Future<StepUpLinkReceipt> requestStepUpLink() => _run((abortTrigger) async {
    final object = (await _invoke(
      operationId: 'requestStepUpLink',
      abortTrigger: abortTrigger,
      body: <String, Object?>{
        'applicationKind': 'homeowner',
        'action': 'ownership-transfer',
      },
    )).requireObject();
    if (object['accepted'] != true) {
      throw const FormatException('Step-up link was not accepted.');
    }
    return StepUpLinkReceipt(
      developmentStepUpToken: _nullableStringField(
        object,
        'developmentStepUpToken',
      ),
    );
  });

  @override
  Future<HomeOwnershipTransfer> proposeHomeOwnershipTransfer({
    required String homeId,
    required String targetUserId,
    required int expectedTargetRevision,
    required String stepUpToken,
  }) => _run(
    (abortTrigger) async => _ownershipTransfer(
      (await _invoke(
        operationId: 'proposeHomeOwnershipTransfer',
        pathParameters: <String, String>{'homeId': homeId},
        abortTrigger: abortTrigger,
        body: <String, Object?>{
          'targetUserId': targetUserId,
          'expectedTargetRevision': expectedTargetRevision,
          'stepUpToken': stepUpToken,
        },
      )).body,
    ),
    homeId: homeId,
    treatNotFoundAsRevoked: true,
    conflictMessage:
        'This member is no longer available. Refresh and try again.',
  );

  @override
  Future<void> acceptHomeOwnershipTransfer({
    required String homeId,
    required String transferId,
    required int expectedRevision,
  }) => _decideOwnershipTransfer(
    operationId: 'acceptHomeOwnershipTransfer',
    homeId: homeId,
    transferId: transferId,
    expectedRevision: expectedRevision,
  );

  @override
  Future<void> rejectHomeOwnershipTransfer({
    required String homeId,
    required String transferId,
    required int expectedRevision,
  }) => _decideOwnershipTransfer(
    operationId: 'rejectHomeOwnershipTransfer',
    homeId: homeId,
    transferId: transferId,
    expectedRevision: expectedRevision,
  );

  @override
  Future<void> revokeHomeOwnershipTransfer({
    required String homeId,
    required String transferId,
    required int expectedRevision,
  }) => _decideOwnershipTransfer(
    operationId: 'revokeHomeOwnershipTransfer',
    homeId: homeId,
    transferId: transferId,
    expectedRevision: expectedRevision,
  );

  Future<void> _decideOwnershipTransfer({
    required String operationId,
    required String homeId,
    required String transferId,
    required int expectedRevision,
  }) => _run(
    (abortTrigger) async {
      await _invoke(
        operationId: operationId,
        pathParameters: <String, String>{
          'homeId': homeId,
          'transferId': transferId,
        },
        abortTrigger: abortTrigger,
        body: <String, Object?>{'expectedRevision': expectedRevision},
      );
    },
    homeId: homeId,
    conflictMessage:
        'This ownership transfer is no longer available. Refresh and try again.',
  );

  @override
  Future<List<RecipientHomeInvitation>> listPendingInvitations() => _run(
    (abortTrigger) async => _data(
      (await _invoke(
        operationId: 'listPendingHomeInvitations',
        abortTrigger: abortTrigger,
      )).requireObject(),
    ).map(_recipientInvitation).toList(growable: false),
  );

  @override
  Future<HomeSummary> acceptPendingInvitation({
    required String invitationId,
    required int expectedRevision,
  }) => _run((abortTrigger) async {
    final result = (await _invoke(
      operationId: 'acceptHomeInvitationById',
      pathParameters: <String, String>{'invitationId': invitationId},
      abortTrigger: abortTrigger,
      body: <String, Object?>{'expectedRevision': expectedRevision},
    )).requireObject();
    _uuid(result, 'invitationId');
    final homeId = _uuid(result, 'homeId');
    final acceptedRole = _role(_string(result, 'role'));
    final homes = await listHomes();
    return homes.firstWhere(
      (home) => home.id == homeId && home.role == acceptedRole,
      orElse: () => throw const HomeTransportException(
        kind: HomeFailureKind.authorization,
        safeMessage: 'The accepted home is not available to this session.',
      ),
    );
  });

  @override
  Future<List<HomePermissionPolicy>> listPermissionPolicies(String homeId) =>
      _run(
        (abortTrigger) async => _data(
          (await _invoke(
            operationId: 'listHomePermissionPolicies',
            pathParameters: <String, String>{'homeId': homeId},
            abortTrigger: abortTrigger,
          )).requireObject(),
        ).map(_permissionPolicy).toList(growable: false),
        homeId: homeId,
        treatNotFoundAsRevoked: true,
        treatForbiddenAsRevoked: true,
      );

  @override
  Future<HomePermissionPolicy> putPermissionPolicy({
    required String homeId,
    required HomeRole role,
    required Set<String> permissions,
    required int expectedRevision,
  }) => _run(
    (abortTrigger) async => _permissionPolicy(
      (await _invoke(
        operationId: 'putHomePermissionPolicy',
        pathParameters: <String, String>{
          'homeId': homeId,
          'role': _roleName(role),
        },
        abortTrigger: abortTrigger,
        body: <String, Object?>{
          'permissions': permissions.toList(growable: false)..sort(),
          'expectedRevision': expectedRevision,
        },
      )).body,
    ),
    homeId: homeId,
    treatNotFoundAsRevoked: true,
    treatForbiddenAsRevoked: true,
    conflictMessage:
        'This role policy is no longer available. Refresh and try again.',
  );

  @override
  Future<void> leaveHome(String homeId) => _run(
    (abortTrigger) async {
      await _invoke(
        operationId: 'leaveHome',
        pathParameters: <String, String>{'homeId': homeId},
        abortTrigger: abortTrigger,
      );
    },
    homeId: homeId,
    treatNotFoundAsRevoked: true,
  );

  Future<T> _run<T>(
    Future<T> Function(Future<void> abortTrigger) action, {
    String? homeId,
    bool treatNotFoundAsRevoked = false,
    bool treatForbiddenAsRevoked = false,
    String? conflictMessage,
  }) async {
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError.value(
        requestTimeout,
        'requestTimeout',
        'must be positive',
      );
    }
    final abort = Completer<void>();
    try {
      return await action(abort.future).timeout(
        requestTimeout,
        onTimeout: () {
          if (!abort.isCompleted) {
            abort.complete();
          }
          throw TimeoutException('Home request timed out and was aborted.');
        },
      );
    } on HomeTransportException {
      rethrow;
    } on ProvidentiaApiException catch (error) {
      throw _failure(
        error,
        homeId: homeId,
        treatNotFoundAsRevoked: treatNotFoundAsRevoked,
        treatForbiddenAsRevoked: treatForbiddenAsRevoked,
        conflictMessage: conflictMessage,
      );
    } on TimeoutException {
      throw HomeTransportException(
        kind: HomeFailureKind.network,
        safeMessage: 'The home service did not respond. Try again safely.',
        homeId: homeId,
      );
    } on http.ClientException {
      throw HomeTransportException(
        kind: HomeFailureKind.network,
        safeMessage: 'The home service could not be reached. Try again safely.',
        homeId: homeId,
      );
    } on FormatException {
      throw HomeTransportException(
        kind: HomeFailureKind.unavailable,
        safeMessage: 'Home data could not be read safely. Try again later.',
        homeId: homeId,
      );
    } on ArgumentError {
      throw HomeTransportException(
        kind: HomeFailureKind.unavailable,
        safeMessage: 'Home data could not be read safely. Try again later.',
        homeId: homeId,
      );
    }
  }

  Future<ApiResponse> _invoke({
    required String operationId,
    required Future<void> abortTrigger,
    Map<String, String> pathParameters = const <String, String>{},
    Map<String, String>? query,
    Map<String, Object?>? body,
  }) => _client.invokeOperation(
    operationId: operationId,
    pathParameters: pathParameters,
    query: query,
    body: body,
    abortTrigger: abortTrigger,
  );
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
    id: _uuid(value, 'id'),
    name: _string(value, 'name'),
    locale: _string(value, 'defaultLocale'),
    currency: _string(value, 'defaultCurrency'),
    timezone: _string(value, 'defaultTimezone'),
    role: _role(_string(value, 'role')),
    revision: _integer(value, 'revision'),
  );
}

HomeMembership _membership(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a membership object.');
  }
  return HomeMembership(
    userId: _uuid(value, 'userId'),
    displayName:
        _optionalStringField(value, 'displayName') ?? 'Household member',
    role: _role(_string(value, 'role')),
    revision: _integer(value, 'revision'),
  );
}

HomeInvitation _invitation(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected an invitation object.');
  }
  _uuid(value, 'inviterUserId');
  return HomeInvitation(
    id: _uuid(value, 'id'),
    homeId: _uuid(value, 'homeId'),
    email: _string(value, 'email'),
    role: _role(_string(value, 'role')),
    status: _invitationStatus(_string(value, 'status')),
    expiresAt: _dateTime(value, 'expiresAt'),
    revision: _integer(value, 'revision'),
  );
}

RecipientHomeInvitation _recipientInvitation(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a recipient invitation object.');
  }
  if (_string(value, 'status') != 'pending') {
    throw const FormatException('Unknown recipient invitation status.');
  }
  return RecipientHomeInvitation(
    id: _uuid(value, 'id'),
    homeId: _uuid(value, 'homeId'),
    homeName: _string(value, 'homeName'),
    inviterUserId: _uuid(value, 'inviterUserId'),
    inviterDisplayName: _nullableStringField(value, 'inviterDisplayName'),
    role: _role(_string(value, 'role')),
    expiresAt: _dateTime(value, 'expiresAt'),
    revision: _integer(value, 'revision'),
  );
}

HomeOwnershipTransfer _ownershipTransfer(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected an ownership transfer object.');
  }
  return HomeOwnershipTransfer(
    id: _uuid(value, 'id'),
    homeId: _uuid(value, 'homeId'),
    proposedByUserId: _uuid(value, 'proposedByUserId'),
    targetUserId: _uuid(value, 'targetUserId'),
    expectedTargetRevision: _optionalIntegerField(
      value,
      'expectedTargetRevision',
    ),
    status: _ownershipTransferStatus(_string(value, 'status')),
    expiresAt: _dateTime(value, 'expiresAt'),
    revision: _integer(value, 'revision'),
  );
}

OwnershipTransferStatus _ownershipTransferStatus(String source) =>
    switch (source) {
      'pending' => OwnershipTransferStatus.pending,
      'accepted' => OwnershipTransferStatus.accepted,
      'rejected' => OwnershipTransferStatus.rejected,
      'revoked' => OwnershipTransferStatus.revoked,
      'expired' => OwnershipTransferStatus.expired,
      _ => throw FormatException('Unknown ownership transfer status $source.'),
    };

HomePermissionPolicy _permissionPolicy(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a permission policy object.');
  }
  return HomePermissionPolicy(
    role: _role(_string(value, 'role')),
    revision: _integer(value, 'revision'),
    permissions: _requiredStringSet(value['permissions']),
    configurable: _optionalBooleanField(value, 'configurable') ?? false,
  );
}

Set<String> _requiredStringSet(Object? value) {
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    throw const FormatException('Expected a string array.');
  }
  final result = value.cast<String>().toSet();
  if (result.length != value.length || result.any((item) => item.isEmpty)) {
    throw const FormatException('Expected unique non-empty strings.');
  }
  return result;
}

bool? _optionalBooleanField(Map<String, Object?> object, String key) {
  if (!object.containsKey(key)) {
    return null;
  }
  return switch (object[key]) {
    final bool parsed => parsed,
    _ => throw FormatException('Expected boolean $key.'),
  };
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

InvitationStatus _invitationStatus(String source) => switch (source) {
  'pending' => InvitationStatus.pending,
  'accepted' => InvitationStatus.accepted,
  'revoked' => InvitationStatus.revoked,
  'expired' => InvitationStatus.expired,
  _ => throw FormatException('Unknown invitation status $source.'),
};

HomeTransportException _failure(
  ProvidentiaApiException error, {
  String? homeId,
  bool treatNotFoundAsRevoked = false,
  bool treatForbiddenAsRevoked = false,
  String? conflictMessage,
}) {
  final kind = switch (error.statusCode) {
    401 => HomeFailureKind.authentication,
    403 when homeId != null && treatForbiddenAsRevoked =>
      HomeFailureKind.membershipRevoked,
    403 => HomeFailureKind.authorization,
    404 when homeId != null && treatNotFoundAsRevoked =>
      HomeFailureKind.membershipRevoked,
    404 || 410 || 409 => HomeFailureKind.conflict,
    400 || 422 => HomeFailureKind.validation,
    >= 500 => HomeFailureKind.unavailable,
    _ => HomeFailureKind.network,
  };
  final message = switch (kind) {
    HomeFailureKind.authentication => 'Sign in again to access your homes.',
    HomeFailureKind.authorization || HomeFailureKind.membershipRevoked =>
      'You no longer have access to this home.',
    HomeFailureKind.conflict =>
      conflictMessage ??
          (homeId == null
              ? 'This invitation is no longer available. Refresh and try again.'
              : 'This home changed on another device. Refresh and try again.'),
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

String _uuid(Map<String, Object?> object, String key) {
  final value = _string(object, key);
  if (!RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(value)) {
    throw FormatException('Invalid UUID $key.');
  }
  return value;
}

String? _optionalStringField(Map<String, Object?> object, String key) {
  if (!object.containsKey(key)) {
    return null;
  }
  final value = object[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Expected non-empty string $key.');
  }
  return value;
}

String? _nullableStringField(Map<String, Object?> object, String key) {
  if (!object.containsKey(key) || object[key] == null) {
    return null;
  }
  final value = object[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Expected nullable string $key.');
  }
  return value;
}

int _integer(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is int) {
    return value;
  }
  throw FormatException('Missing $key.');
}

int? _optionalIntegerField(Map<String, Object?> object, String key) {
  if (!object.containsKey(key)) {
    return null;
  }
  return switch (object[key]) {
    final int parsed => parsed,
    _ => throw FormatException('Expected integer $key.'),
  };
}

DateTime _dateTime(Map<String, Object?> object, String key) {
  final value = DateTime.tryParse(_string(object, key));
  if (value == null) {
    throw FormatException('Invalid $key.');
  }
  return value.toUtc();
}
