import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:providentia/features/identity/application/identity_session_manager.dart';
import 'package:providentia/features/identity/domain/identity_models.dart';

/// Adds the active session to every application API request.
///
/// Native requests use a short-lived bearer token. Browser requests rely on
/// the credentialed BrowserClient's HttpOnly cookies and add the CSRF token to
/// state-changing requests. A 401 performs one single-flight rotation and one
/// replay; request bodies are finalized once and copied as bytes for safety.
final class SessionHttpClient extends http.BaseClient {
  factory SessionHttpClient({
    required http.Client inner,
    required IdentitySessionManager sessions,
    bool closeInner = true,
  }) => SessionHttpClient._(inner, sessions, closeInner);

  SessionHttpClient._(this._inner, this._sessions, this.closeInner);

  final http.Client _inner;
  final IdentitySessionManager _sessions;
  final bool closeInner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await request.finalize().toBytes();
    if (_sessions.sessionTransport == ClientSessionTransport.webCookie &&
        _changesState(request.method)) {
      http.StreamedResponse? coordinatedResponse;
      final authorized = await _sessions.coordinateWebStateChangingRequest((
        recover,
      ) async {
        final response = await _inner.send(_copyRequest(request, body));
        if (response.statusCode != 401) {
          coordinatedResponse = response;
          return;
        }
        await response.stream.drain<void>();
        if (!await recover()) {
          coordinatedResponse = _authenticationRequired(request, body);
          return;
        }
        coordinatedResponse = await _inner.send(_copyRequest(request, body));
      });
      if (!authorized) {
        return _authenticationRequired(request, body);
      }
      return coordinatedResponse!;
    }
    if (!await _sessions.ensureFresh()) {
      return _authenticationRequired(request, body);
    }

    final response = await _inner.send(_copyRequest(request, body));
    if (response.statusCode != 401) {
      return response;
    }

    await response.stream.drain<void>();
    if (!await _sessions.tryRecover()) {
      return _authenticationRequired(request, body);
    }
    return _inner.send(_copyRequest(request, body));
  }

  http.BaseRequest _copyRequest(http.BaseRequest source, List<int> body) {
    final http.Request copy = source is http.Abortable
        ? http.AbortableRequest(
            source.method,
            source.url,
            abortTrigger: source.abortTrigger,
          )
        : http.Request(source.method, source.url);
    copy
      ..followRedirects = source.followRedirects
      ..maxRedirects = source.maxRedirects
      ..persistentConnection = source.persistentConnection
      ..headers.addAll(source.headers)
      ..bodyBytes = body;
    switch (_sessions.sessionTransport) {
      case ClientSessionTransport.nativeBearer:
        copy.headers['Authorization'] = 'Bearer ${_sessions.accessToken}';
      case ClientSessionTransport.webCookie:
        if (_changesState(source.method) && _sessions.csrfToken != null) {
          copy.headers['X-CSRF-Token'] = _sessions.csrfToken!;
        }
    }
    return copy;
  }

  http.StreamedResponse _authenticationRequired(
    http.BaseRequest request,
    List<int> body,
  ) {
    return http.StreamedResponse(
      Stream<List<int>>.value(<int>[]),
      401,
      request: _copyRequest(request, body),
      reasonPhrase: 'Authentication required',
      headers: const <String, String>{
        'content-type': 'application/problem+json',
      },
    );
  }

  bool _changesState(String method) => switch (method.toUpperCase()) {
    'GET' || 'HEAD' || 'OPTIONS' => false,
    _ => true,
  };

  @override
  void close() {
    if (closeInner) {
      _inner.close();
    }
  }
}
