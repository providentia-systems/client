import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/ai_integration/application/ai_ports.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/infrastructure/api17_ai_gateway.dart';
import 'package:providentia/features/ai_integration/infrastructure/strict_local_ai_composition.dart';
import 'package:providentia/features/ai_integration/infrastructure/strict_local_native_transport.dart';
import 'package:providentia/features/ai_integration/infrastructure/strict_local_provider_gateway.dart';

void main() {
  const transport = NativeStrictLocalHttpTransport();

  test('connects only to pinned peer and reports the actual peer', () async {
    final server = await _server((request) async {
      expect(request.uri.path, '/api/tags');
      request.response
        ..statusCode = 200
        ..write('{"models":[]}');
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    final response = await transport.send(_request(server));

    expect(response.statusCode, 200);
    expect(response.connectedPeerAddress, '127.0.0.1');
    expect(utf8.decode(response.body), '{"models":[]}');
  });

  test('does not follow redirects', () async {
    var requests = 0;
    final server = await _server((request) async {
      requests++;
      if (request.uri.path == '/target') {
        request.response.write('must not be reached');
      } else {
        request.response
          ..statusCode = 302
          ..headers.set(HttpHeaders.locationHeader, '/target');
      }
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    final response = await transport.send(_request(server));

    expect(response.statusCode, 302);
    expect(response.headers, contains(HttpHeaders.locationHeader));
    expect(requests, 1);
  });

  test('bounds chunked response bodies', () async {
    final server = await _server((request) async {
      request.response.add(List<int>.filled(128, 1));
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    await expectLater(
      transport.send(_request(server, maximumResponseBytes: 16)),
      throwsA(
        isA<StrictLocalBoundaryException>().having(
          (error) => error.code,
          'code',
          'local_response_size_limit',
        ),
      ),
    );
  });

  test('closes timed-out requests', () async {
    final server = await _server((request) async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      try {
        request.response.write('late');
        await request.response.close();
      } on Object {
        // The client intentionally tears down the timed-out socket.
      }
    });
    addTearDown(() => server.close(force: true));

    await expectLater(
      transport.send(
        _request(server, timeout: const Duration(milliseconds: 20)),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('cannot fall back to the URI host outside the pinned set', () async {
    final server = await _server((request) async {
      request.response.write('must not be reached');
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    await expectLater(
      transport.send(
        _request(server, pinnedPeerAddresses: const <String>{'127.0.0.2'}),
      ),
      throwsA(anything),
    );
  });

  test('native resolver returns IP literals', () async {
    final addresses = await const NativeStrictLocalNameResolver().resolve(
      'localhost',
      timeout: const Duration(seconds: 2),
    );

    expect(addresses, isNotEmpty);
    expect(
      addresses.every((address) => InternetAddress.tryParse(address) != null),
      isTrue,
    );
  });

  test('IPv6 ULA guard pins remain parseable by dart:io', () async {
    final resolved = await const StrictLocalEndpointGuard().resolve(
      endpoint: Uri.parse('https://[fd12:3456::9]'),
      resolver: const NativeStrictLocalNameResolver(),
    );

    expect(resolved.addresses, hasLength(1));
    expect(InternetAddress.tryParse(resolved.addresses.single), isNotNull);
    expect(resolved.addresses.single, contains(':'));
  });

  test('current-platform composition exposes the strict-local route', () {
    final gateway = StrictLocalAiComposition.createForCurrentPlatform(
      mediaReader: const _NoMediaReader(),
    );

    expect(gateway.route, AiGatewayRoute.directStrictLocal);
  });
}

Future<HttpServer> _server(
  Future<void> Function(HttpRequest request) handler,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen(handler);
  return server;
}

StrictLocalTransportRequest _request(
  HttpServer server, {
  Duration timeout = const Duration(seconds: 2),
  int maximumResponseBytes = 1024,
  Set<String> pinnedPeerAddresses = const <String>{'127.0.0.1'},
}) => StrictLocalTransportRequest(
  method: 'GET',
  uri: Uri.parse('http://127.0.0.1:${server.port}/api/tags'),
  headers: const <String, String>{'accept': 'application/json'},
  body: null,
  timeout: timeout,
  maximumResponseBytes: maximumResponseBytes,
  pinnedPeerAddresses: pinnedPeerAddresses,
);

final class _NoMediaReader implements PreparedMediaByteReader {
  const _NoMediaReader();

  @override
  Future<Uint8List> read(PreparedAiMedia media) =>
      throw UnsupportedError('not used');
}
