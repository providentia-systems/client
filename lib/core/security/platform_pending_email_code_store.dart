import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:providentia/features/identity/application/identity_ports.dart';
import 'package:providentia/features/identity/domain/identity_models.dart';

/// Persists the single origin-authoritative login intent in protected storage.
///
/// The v3 envelope keeps the durable head and proof in one write. All web
/// callers hold the origin session lock, while request-id comparisons make a
/// late update/cancel from an older tab harmless. Terminal state occupies the
/// same key, so superseded proofs never reappear and storage remains bounded.
final class PlatformPendingEmailCodeStore implements PendingEmailCodeStore {
  PlatformPendingEmailCodeStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _envelopeKey = 'providentia.pending-email-code.v1';
  static const String _logoutKey = 'providentia.web-logout-intent.v1';
  static const String _cookieMutationKey = 'providentia.web-cookie-mutation.v1';
  final FlutterSecureStorage _storage;

  @override
  Future<PendingEmailCode?> read() async {
    try {
      final envelope = await _storage.read(key: _envelopeKey);
      if (envelope != null) return _decode(envelope).request;

      return null;
    } on Object {
      // A corrupt/incomplete intent must suppress restoration of a previous
      // account. The manager retires that session before allowing login again.
      await _storage.write(key: _logoutKey, value: 'pending');
      await _writeTerminal(status: 'invalid');
      throw const IdentityCredentialStoreException(
        'The saved login request was invalid and has been retired.',
      );
    }
  }

  @override
  Future<void> write(PendingEmailCode request, {required bool activate}) async {
    if (activate) {
      await _writeActive(request);
      return;
    }
    final current = await _readEnvelope();
    if (current?.request?.requestId != request.requestId) return;
    await _writeActive(request);
  }

  @override
  Future<void> invalidate(PendingEmailCode request) =>
      _completeIfCurrent(request, 'invalidated');

  @override
  Future<void> clear({PendingEmailCode? request}) async {
    if (request != null) {
      await _completeIfCurrent(request, 'completed');
      return;
    }
    await _writeTerminal(status: 'none');
  }

  @override
  Future<bool> hasLogoutIntent() async =>
      await _storage.read(key: _logoutKey) == 'pending';

  @override
  Future<void> markLogoutIntent() =>
      _storage.write(key: _logoutKey, value: 'pending');

  @override
  Future<void> clearLogoutIntent() => _storage.delete(key: _logoutKey);

  @override
  Future<BrowserCookieMutationJournal?> readCookieMutation() async {
    final encoded = await _storage.read(key: _cookieMutationKey);
    if (encoded == null) return null;
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Expected a cookie mutation journal.');
    }
    final kind = BrowserCookieMutationKind.values
        .asNameMap()[_string(decoded, 'kind')];
    if (kind == null) {
      throw const FormatException('Unknown cookie mutation kind.');
    }
    return BrowserCookieMutationJournal(
      kind: kind,
      operationId: _string(decoded, 'operationId'),
    );
  }

  @override
  Future<void> beginCookieMutation(BrowserCookieMutationJournal journal) =>
      _storage.write(
        key: _cookieMutationKey,
        value: jsonEncode(<String, Object?>{
          'kind': journal.kind.name,
          'operationId': journal.operationId,
        }),
      );

  @override
  Future<void> clearCookieMutation({
    BrowserCookieMutationJournal? journal,
  }) async {
    if (journal != null) {
      final current = await readCookieMutation();
      if (current?.kind != journal.kind ||
          current?.operationId != journal.operationId) {
        return;
      }
    }
    await _storage.delete(key: _cookieMutationKey);
  }

  Future<_PendingEnvelope?> _readEnvelope() async {
    final encoded = await _storage.read(key: _envelopeKey);
    return encoded == null ? null : _decode(encoded);
  }

  Future<void> _completeIfCurrent(
    PendingEmailCode request,
    String status,
  ) async {
    final current = await _readEnvelope();
    if (current?.request?.requestId != request.requestId) return;
    await _writeTerminal(status: status, requestId: request.requestId);
  }

  Future<void> _writeActive(PendingEmailCode request) => _storage.write(
    key: _envelopeKey,
    value: jsonEncode(<String, Object?>{
      'status': 'active',
      'requestId': request.requestId,
      'email': request.email,
      'bindingToken': request.bindingToken,
      'createdAt': request.createdAt.toUtc().toIso8601String(),
      'expiresAt': request.expiresAt.toUtc().toIso8601String(),
      'resendAt': request.resendAt.toUtc().toIso8601String(),
    }),
  );

  Future<void> _writeTerminal({required String status, String? requestId}) =>
      _storage.write(
        key: _envelopeKey,
        value: jsonEncode(<String, Object?>{
          'status': status,
          'requestId': ?requestId,
        }),
      );

  _PendingEnvelope _decode(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Expected a login request object.');
    }
    final status = _string(decoded, 'status');
    if (status == 'active') {
      return _PendingEnvelope(
        request: _request(decoded, createdAt: _dateTime(decoded, 'createdAt')),
      );
    }
    if (status == 'none' ||
        status == 'completed' ||
        status == 'invalidated' ||
        status == 'invalid') {
      final requestId = decoded['requestId'];
      if (requestId != null) {
        if (requestId is! String) {
          throw const FormatException('Invalid request identifier.');
        }
        _requireUuid(requestId);
      }
      return const _PendingEnvelope();
    }
    throw const FormatException('Unknown login request state.');
  }

  PendingEmailCode _request(
    Map<String, Object?> decoded, {
    required DateTime createdAt,
  }) => PendingEmailCode(
    requestId: _string(decoded, 'requestId'),
    email: _string(decoded, 'email'),
    bindingToken: _string(decoded, 'bindingToken'),
    createdAt: createdAt,
    expiresAt: _dateTime(decoded, 'expiresAt'),
    resendAt: _dateTime(decoded, 'resendAt'),
  );
}

final class _PendingEnvelope {
  const _PendingEnvelope({this.request});

  final PendingEmailCode? request;
}

void _requireUuid(String value) {
  if (!_uuid.hasMatch(value)) throw const FormatException('Invalid UUID.');
}

final RegExp _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Missing $key.');
  }
  return value;
}

DateTime _dateTime(Map<String, Object?> json, String key) {
  final value = DateTime.tryParse(_string(json, key));
  if (value == null) throw FormatException('Invalid $key.');
  return value.toUtc();
}
