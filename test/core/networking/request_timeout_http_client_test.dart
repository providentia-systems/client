import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:providentia/core/networking/request_timeout_http_client.dart';

void main() {
  for (final path in ['/stall-headers', '/stall-body']) {
    test(
      'timeout aborts the real $path transport before a safe retry',
      () async {
        final server = await _LoopbackServer.start();
        final client = RequestTimeoutHttpClient(
          inner: http.Client(),
          timeout: const Duration(milliseconds: 250),
        );
        addTearDown(() async {
          client.close();
          await server.close();
        });

        final attempt = client.get(server.uri('$path?token=private-fixture'));
        final error = expectLater(
          attempt,
          throwsA(
            isA<RequestTimeoutException>()
                .having((error) => error.uri, 'safe URI', isNull)
                .having(
                  (error) => error.toString(),
                  'safe message',
                  allOf(
                    contains('timed out'),
                    isNot(contains('private-fixture')),
                    isNot(contains('127.0.0.1')),
                  ),
                ),
          ),
        );
        await server.firstRequest.future.timeout(const Duration(seconds: 2));
        await error;
        await server.firstSocketClosed.future.timeout(
          const Duration(seconds: 2),
        );

        // Completing the caller's future alone is insufficient: the old socket
        // must already be gone before another saved-operation retry can start.
        expect(server.liveStalledSockets, 0);
        final retry = await client.get(server.uri('/ok'));
        expect(retry.statusCode, 200);
        expect(retry.body, 'ok');
        expect(server.requests, 2);
      },
    );
  }

  test(
    'one timed out request does not cancel another request or its timer',
    () async {
      final server = await _LoopbackServer.start();
      final client = RequestTimeoutHttpClient(
        inner: http.Client(),
        timeout: const Duration(milliseconds: 400),
      );
      addTearDown(() async {
        client.close();
        await server.close();
      });

      final stalled = expectLater(
        client.get(server.uri('/stall-headers')),
        throwsA(isA<RequestTimeoutException>()),
      );
      await server.firstRequest.future;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      // This response crosses the earlier request's deadline, while remaining
      // inside its own deadline. Closing the shared client on timeout breaks it.
      final healthy = client.get(server.uri('/delayed'));
      await stalled;
      final response = await healthy;
      expect(response.body, 'ok');
      expect(server.requests, 2);
      expect((await client.get(server.uri('/ok'))).body, 'ok');
    },
  );

  test('external cancellation retains RequestAbortedException', () async {
    final server = await _LoopbackServer.start();
    final client = RequestTimeoutHttpClient(
      inner: http.Client(),
      timeout: const Duration(seconds: 2),
    );
    addTearDown(() async {
      client.close();
      await server.close();
    });
    final externalAbort = Completer<void>();
    final attempt = client.send(
      http.AbortableRequest(
        'GET',
        server.uri('/stall-headers'),
        abortTrigger: externalAbort.future,
      ),
    );
    final expected = expectLater(
      attempt,
      throwsA(isA<http.RequestAbortedException>()),
    );
    await server.firstRequest.future;
    externalAbort.complete();
    await expected;
    await server.firstSocketClosed.future.timeout(const Duration(seconds: 2));
    expect((await client.get(server.uri('/ok'))).body, 'ok');
  });

  test('external cancellation also aborts a streamed response body', () async {
    final server = await _LoopbackServer.start();
    final client = RequestTimeoutHttpClient(
      inner: http.Client(),
      timeout: const Duration(seconds: 2),
    );
    addTearDown(() async {
      client.close();
      await server.close();
    });
    final externalAbort = Completer<void>();
    final streamed = await client.send(
      http.AbortableRequest(
        'GET',
        server.uri('/stall-body'),
        abortTrigger: externalAbort.future,
      ),
    );
    final attempt = http.Response.fromStream(streamed);
    final expected = expectLater(
      attempt,
      throwsA(isA<http.RequestAbortedException>()),
    );
    await server.firstRequest.future;
    externalAbort.complete();
    await expected;
    await server.firstSocketClosed.future.timeout(const Duration(seconds: 2));
  });

  test(
    'external transport ownership is preserved after wrapper close',
    () async {
      final inner = _TrackingClient();
      final client = RequestTimeoutHttpClient(inner: inner, closeInner: false);
      expect(
        (await client.get(Uri.parse('https://api.example.test'))).body,
        'ok',
      );
      client.close();
      expect(inner.closeCount, 0);
      expect(
        (await inner.get(Uri.parse('https://api.example.test'))).body,
        'ok',
      );
      inner.close();
      expect(inner.closeCount, 1);
    },
  );

  test('owned transport is closed exactly once', () {
    final inner = _TrackingClient();
    final client = RequestTimeoutHttpClient(inner: inner);
    client.close();
    client.close();
    expect(inner.closeCount, 1);
  });

  test('timeout must be positive', () {
    final inner = _TrackingClient();
    expect(
      () => RequestTimeoutHttpClient(inner: inner, timeout: Duration.zero),
      throwsArgumentError,
    );
    expect(
      () => RequestTimeoutHttpClient(
        inner: inner,
        timeout: const Duration(seconds: -1),
      ),
      throwsArgumentError,
    );
    inner.close();
  });
}

final class _TrackingClient extends http.BaseClient {
  int closeCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await request.finalize().drain<void>();
    return http.StreamedResponse(Stream.value(utf8.encode('ok')), 200);
  }

  @override
  void close() => closeCount++;
}

/// A genuine HTTP connection with deliberately unfinished headers/body. Raw
/// sockets let the test observe transport cancellation without completing the
/// server response and accidentally making a dangling request look successful.
final class _LoopbackServer {
  _LoopbackServer(this.server);

  final ServerSocket server;
  final sockets = <Socket>{};
  final stalledSockets = <Socket>{};
  final firstRequest = Completer<void>();
  final firstSocketClosed = Completer<void>();
  int requests = 0;

  int get liveStalledSockets => stalledSockets.length;

  static Future<_LoopbackServer> start() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final harness = _LoopbackServer(server);
    server.listen(
      harness._accept,
      onError: (Object error) {
        // A transport abort can reset a connection before accept completes.
        // That reset is expected cancellation evidence, not a server failure.
        if (error is! SocketException) throw error;
      },
    );
    return harness;
  }

  Uri uri(String path) => Uri.parse('http://127.0.0.1:${server.port}$path');

  void _accept(Socket socket) {
    sockets.add(socket);
    var headers = '';
    var handled = false;
    socket.listen(
      (bytes) {
        if (handled) return;
        headers += ascii.decode(bytes);
        if (!headers.contains('\r\n\r\n')) return;
        handled = true;
        requests++;
        final path = headers.split(' ')[1];
        final stalled = path.startsWith('/stall-');
        if (stalled) {
          stalledSockets.add(socket);
          if (path.startsWith('/stall-body')) {
            socket.write(
              'HTTP/1.1 200 OK\r\nContent-Length: 50\r\n\r\npartial',
            );
          }
          if (!firstRequest.isCompleted) firstRequest.complete();
        } else if (path == '/delayed') {
          Timer(const Duration(milliseconds: 250), () => _respond(socket));
        } else {
          _respond(socket);
        }
      },
      onDone: () {
        sockets.remove(socket);
        if (stalledSockets.remove(socket) && !firstSocketClosed.isCompleted) {
          firstSocketClosed.complete();
        }
        socket.destroy();
      },
      onError: (Object _) {
        sockets.remove(socket);
        if (stalledSockets.remove(socket) && !firstSocketClosed.isCompleted) {
          firstSocketClosed.complete();
        }
        socket.destroy();
      },
    );
  }

  void _respond(Socket socket) {
    if (!sockets.contains(socket)) return;
    socket.write(
      'HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok',
    );
    unawaited(
      socket
          .flush()
          .then((_) => socket.close())
          .catchError((Object _) => socket),
    );
  }

  Future<void> close() async {
    for (final socket in sockets.toList()) {
      socket.destroy();
    }
    sockets.clear();
    stalledSockets.clear();
    await server.close();
  }
}
