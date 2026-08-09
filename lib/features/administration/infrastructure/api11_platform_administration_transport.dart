import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:providentia/features/administration/application/platform_administration_controller.dart';
import 'package:providentia/features/administration/domain/platform_administrator_models.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

final class Api11PlatformAdministrationTransport
    implements PlatformAdministrationPort {
  const Api11PlatformAdministrationTransport(
    this._client, {
    this.requestTimeout = const Duration(seconds: 15),
  });

  final ProvidentiaApiClient _client;
  final Duration requestTimeout;

  @override
  Future<List<PlatformAdministrator>> listAdministrators() =>
      _run((abortTrigger) async {
        final object = (await _invoke(
          operationId: 'listPlatformAdministrators',
          abortTrigger: abortTrigger,
        )).requireObject();
        final data = object['data'];
        if (data is! List<Object?>) {
          throw const FormatException('Expected administrator data.');
        }
        return data.map(_administrator).toList(growable: false);
      }, malformedMessage: 'Administrator details could not be read safely.');

  @override
  Future<PlatformAdministrator> grantAdministrator(String email) => _run(
    (abortTrigger) async => _administrator(
      (await _invoke(
        operationId: 'grantPlatformAdministrator',
        abortTrigger: abortTrigger,
        body: <String, Object?>{'email': email},
      )).body,
    ),
    malformedMessage: 'The administrator grant response was invalid.',
  );

  @override
  Future<void> revokeAdministrator({
    required String administratorId,
    required int expectedRevision,
  }) => _run(
    (abortTrigger) async {
      await _invoke(
        operationId: 'revokePlatformAdministrator',
        pathParameters: <String, String>{'administratorId': administratorId},
        abortTrigger: abortTrigger,
        body: <String, Object?>{'expectedRevision': expectedRevision},
      );
    },
    revoking: true,
    malformedMessage: 'The administrator revoke response was invalid.',
  );

  Future<T> _run<T>(
    Future<T> Function(Future<void> abortTrigger) action, {
    bool revoking = false,
    required String malformedMessage,
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
          throw TimeoutException(
            'Platform administration request timed out and was aborted.',
          );
        },
      );
    } on PlatformAdministrationException {
      rethrow;
    } on ProvidentiaApiException catch (error) {
      throw _failure(error, revoking: revoking);
    } on TimeoutException {
      throw const PlatformAdministrationException(
        kind: PlatformAdministrationFailureKind.unavailable,
        safeMessage: 'Platform administration did not respond. Try again.',
      );
    } on http.ClientException {
      throw const PlatformAdministrationException(
        kind: PlatformAdministrationFailureKind.unavailable,
        safeMessage: 'Platform administration could not be reached.',
      );
    } on FormatException {
      throw PlatformAdministrationException(
        kind: PlatformAdministrationFailureKind.unavailable,
        safeMessage: malformedMessage,
      );
    } on ArgumentError {
      throw PlatformAdministrationException(
        kind: PlatformAdministrationFailureKind.unavailable,
        safeMessage: malformedMessage,
      );
    }
  }

  Future<ApiResponse> _invoke({
    required String operationId,
    required Future<void> abortTrigger,
    Map<String, String> pathParameters = const <String, String>{},
    Map<String, Object?>? body,
  }) => _client.invokeOperation(
    operationId: operationId,
    pathParameters: pathParameters,
    body: body,
    abortTrigger: abortTrigger,
  );
}

PlatformAdministrator _administrator(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected an administrator object.');
  }
  return PlatformAdministrator(
    id: _uuid(value, 'id'),
    email: _email(value, 'email'),
    userId: _optionalUuid(value['userId']),
    status: switch (_string(value, 'status')) {
      'pending' => PlatformAdministratorStatus.pending,
      'active' => PlatformAdministratorStatus.active,
      _ => throw const FormatException('Unknown administrator status.'),
    },
    revision: _integer(value, 'revision'),
    grantedByUserId: _optionalUuid(value['grantedByUserId']),
    createdAt: _dateTime(value, 'createdAt'),
    activatedAt: _optionalDateTime(value['activatedAt']),
  );
}

PlatformAdministrationException _failure(
  ProvidentiaApiException error, {
  bool revoking = false,
}) {
  return switch (error.statusCode) {
    403 => const PlatformAdministrationException(
      kind: PlatformAdministrationFailureKind.forbidden,
      safeMessage: 'Platform-administrator access is required.',
    ),
    409 when revoking => const PlatformAdministrationException(
      kind: PlatformAdministrationFailureKind.conflict,
      safeMessage:
          'The final active platform administrator cannot be revoked. Refresh if the list changed.',
    ),
    409 => const PlatformAdministrationException(
      kind: PlatformAdministrationFailureKind.conflict,
      safeMessage: 'That administrator grant already exists. Refresh the list.',
    ),
    400 || 422 => const PlatformAdministrationException(
      kind: PlatformAdministrationFailureKind.validation,
      safeMessage: 'Check the administrator email and try again.',
    ),
    _ => const PlatformAdministrationException(
      kind: PlatformAdministrationFailureKind.unavailable,
      safeMessage: 'Platform administration is temporarily unavailable.',
    ),
  };
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
  if (!_uuidPattern.hasMatch(value)) {
    throw FormatException('Invalid UUID $key.');
  }
  return value;
}

String? _optionalUuid(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! String || !_uuidPattern.hasMatch(value)) {
    throw const FormatException('Expected an optional UUID.');
  }
  return value;
}

String _email(Map<String, Object?> object, String key) {
  final value = _string(object, key);
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) {
    throw FormatException('Invalid email $key.');
  }
  return value;
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

int _integer(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is! int) {
    throw FormatException('Missing $key.');
  }
  return value;
}

DateTime _dateTime(Map<String, Object?> object, String key) {
  final value = DateTime.tryParse(_string(object, key));
  if (value == null) {
    throw FormatException('Invalid $key.');
  }
  return value.toUtc();
}

DateTime? _optionalDateTime(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw const FormatException('Expected an optional date-time string.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw const FormatException('Invalid optional date-time string.');
  }
  return parsed.toUtc();
}
