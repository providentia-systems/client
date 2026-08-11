import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:providentia/features/ai_integration/infrastructure/strict_local_provider_gateway.dart';

final class NativeStrictLocalNameResolver implements StrictLocalNameResolver {
  const NativeStrictLocalNameResolver();

  @override
  Future<List<String>> resolve(String host, {required Duration timeout}) async {
    final addresses = await InternetAddress.lookup(host).timeout(timeout);
    return addresses.map((address) => address.address).toSet().toList()..sort();
  }
}

/// dart:io implementation that connects only to guard-approved IP literals.
/// HTTPS is upgraded with the original URI host, preserving SNI and normal
/// certificate/hostname verification; bad certificates are never accepted.
final class NativeStrictLocalHttpTransport implements StrictLocalHttpTransport {
  const NativeStrictLocalHttpTransport();

  @override
  bool get blocksRedirects => true;

  @override
  bool get exposesConnectedPeerAddress => true;

  @override
  Future<StrictLocalTransportResponse> send(
    StrictLocalTransportRequest request,
  ) async {
    if ((request.uri.scheme != 'http' && request.uri.scheme != 'https') ||
        request.pinnedPeerAddresses.isEmpty) {
      throw const StrictLocalBoundaryException(
        code: 'missing_pinned_peer',
        safeMessage: 'The strict local network peer was not pinned.',
      );
    }
    final client = HttpClient()
      ..autoUncompress = false
      ..connectionTimeout = request.timeout
      ..idleTimeout = request.timeout
      ..maxConnectionsPerHost = 1
      ..findProxy = (_) => 'DIRECT';
    String? connectedPeer;
    ConnectionTask<Socket>? activeTask;
    Socket? activeSocket;
    var cancelled = false;
    client.connectionFactory = (uri, proxyHost, proxyPort) async {
      if (proxyHost != null ||
          proxyPort != null ||
          uri.origin != request.uri.origin) {
        throw const StrictLocalBoundaryException(
          code: 'unexpected_connection_target',
          safeMessage: 'The strict local connection target changed.',
        );
      }
      final candidates = request.pinnedPeerAddresses.toList()..sort();
      final socketFuture = () async {
        Object? lastError;
        for (final candidate in candidates) {
          if (cancelled) throw const SocketException('Connection cancelled.');
          try {
            final address = InternetAddress(candidate);
            activeTask = await Socket.startConnect(address, uri.port);
            var socket = await activeTask!.socket;
            activeSocket = socket;
            if (uri.scheme == 'https') {
              socket = await SecureSocket.secure(
                socket,
                host: uri.host,
                supportedProtocols: const <String>['http/1.1'],
              );
              activeSocket = socket;
            }
            final expectedBytes = address.rawAddress;
            final peerBytes = socket.remoteAddress.rawAddress;
            if (expectedBytes.length != peerBytes.length ||
                Iterable<int>.generate(
                  expectedBytes.length,
                ).any((index) => expectedBytes[index] != peerBytes[index])) {
              socket.destroy();
              throw const StrictLocalBoundaryException(
                code: 'connected_peer_mismatch',
                safeMessage:
                    'The connected peer did not match the pinned address.',
              );
            }
            connectedPeer = socket.remoteAddress.address;
            return socket;
          } on Object catch (error) {
            lastError = error;
            activeSocket?.destroy();
            activeSocket = null;
          }
        }
        throw lastError ?? const SocketException('No pinned peer available.');
      }();
      return ConnectionTask.fromSocket(socketFuture, () {
        cancelled = true;
        activeTask?.cancel();
        activeSocket?.destroy();
      });
    };

    Future<StrictLocalTransportResponse> execute() async {
      final outbound = await client.openUrl(request.method, request.uri);
      outbound
        ..followRedirects = false
        ..maxRedirects = 0
        ..persistentConnection = false;
      const forbiddenHeaders = <String>{
        HttpHeaders.hostHeader,
        HttpHeaders.contentLengthHeader,
        HttpHeaders.transferEncodingHeader,
        HttpHeaders.connectionHeader,
      };
      for (final entry in request.headers.entries) {
        if (forbiddenHeaders.contains(entry.key.toLowerCase())) {
          throw const StrictLocalBoundaryException(
            code: 'unsafe_transport_header',
            safeMessage: 'The strict local request contained an unsafe header.',
          );
        }
        outbound.headers.set(entry.key, entry.value);
      }
      final body = request.body;
      if (body != null) {
        outbound.contentLength = body.length;
        outbound.add(body);
      } else {
        outbound.contentLength = 0;
      }
      final inbound = await outbound.close();
      if (inbound.contentLength > request.maximumResponseBytes) {
        throw const StrictLocalBoundaryException(
          code: 'local_response_size_limit',
          safeMessage: 'The local AI response exceeded the safety limit.',
        );
      }
      final bytes = BytesBuilder(copy: false);
      var byteCount = 0;
      await for (final chunk in inbound) {
        byteCount += chunk.length;
        if (byteCount > request.maximumResponseBytes) {
          throw const StrictLocalBoundaryException(
            code: 'local_response_size_limit',
            safeMessage: 'The local AI response exceeded the safety limit.',
          );
        }
        bytes.add(chunk);
      }
      final headers = <String, String>{};
      inbound.headers.forEach((name, values) {
        headers[name.toLowerCase()] = values.join(',');
      });
      final peer = connectedPeer;
      if (peer == null) {
        throw const StrictLocalBoundaryException(
          code: 'peer_address_unavailable',
          safeMessage:
              'The connected local network peer could not be verified.',
        );
      }
      return StrictLocalTransportResponse(
        statusCode: inbound.statusCode,
        body: bytes.takeBytes(),
        finalUri: request.uri,
        connectedPeerAddress: peer,
        redirected: inbound.redirects.isNotEmpty,
        headers: headers,
      );
    }

    try {
      return await execute().timeout(
        request.timeout,
        onTimeout: () {
          client.close(force: true);
          throw TimeoutException('Strict local request timed out.');
        },
      );
    } finally {
      client.close(force: true);
    }
  }
}
