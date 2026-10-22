import 'dart:async';

import 'package:http/http.dart' as http;

/// A request expired without establishing whether the server accepted it.
/// Callers must retain immutable operation identities for response-loss recovery.
final class RequestTimeoutException extends http.ClientException {
  RequestTimeoutException()
    : super(
        'The request timed out. Retry safely with the saved operation identity.',
      );
}

/// Applies a deadline to each request, including its streamed response body.
///
/// The native and browser transports support package:http's Abortable contract;
/// SessionHttpClient preserves that contract when it copies authenticated
/// requests. Expiry aborts only this request, never the shared authenticated
/// client. This is deliberately below application synchronization, so a timed
/// out transport cannot later apply a response to the local projection.
final class RequestTimeoutHttpClient extends http.BaseClient {
  factory RequestTimeoutHttpClient({
    required http.Client inner,
    Duration timeout = const Duration(seconds: 30),
    bool closeInner = true,
  }) {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'must be positive');
    }
    return RequestTimeoutHttpClient._(inner, timeout, closeInner);
  }

  RequestTimeoutHttpClient._(this._inner, this.timeout, this.closeInner);

  final http.Client _inner;
  final Duration timeout;
  final bool closeInner;
  final Set<Completer<void>> _activeAborts = {};
  bool _closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) throw http.ClientException('The request client is closed.');
    final abort = Completer<void>();
    _activeAborts.add(abort);
    var expired = false;
    final timer = Timer(timeout, () {
      if (!abort.isCompleted) {
        expired = true;
        abort.complete();
      }
    });
    if (request case http.Abortable(:final abortTrigger?)) {
      unawaited(
        abortTrigger.then((_) {
          timer.cancel();
          if (!abort.isCompleted) abort.complete();
        }),
      );
    }
    void finished() {
      timer.cancel();
      _activeAborts.remove(abort);
    }

    try {
      final response = await _inner.send(
        _DeadlineRequest(request, abort.future),
      );
      Stream<List<int>> guardedBody() async* {
        try {
          await for (final chunk in response.stream) {
            yield chunk;
          }
        } on http.RequestAbortedException {
          if (expired) throw RequestTimeoutException();
          rethrow;
        } finally {
          finished();
        }
      }

      return http.StreamedResponse(
        guardedBody(),
        response.statusCode,
        contentLength: response.contentLength,
        request: response.request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    } on http.RequestAbortedException {
      finished();
      if (expired) throw RequestTimeoutException();
      rethrow;
    } catch (_) {
      finished();
      rethrow;
    }
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    for (final abort in _activeAborts.toList(growable: false)) {
      if (!abort.isCompleted) abort.complete();
    }
    if (closeInner) _inner.close();
  }
}

/// Retains the original body stream without finalizing or buffering it twice.
final class _DeadlineRequest extends http.BaseRequest with http.Abortable {
  _DeadlineRequest(http.BaseRequest source, this.abortTrigger)
    : _body = source.finalize(),
      super(source.method, source.url) {
    contentLength = source.contentLength;
    followRedirects = source.followRedirects;
    maxRedirects = source.maxRedirects;
    persistentConnection = source.persistentConnection;
    headers.addAll(source.headers);
  }

  final http.ByteStream _body;
  @override
  final Future<void> abortTrigger;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return _body;
  }
}
