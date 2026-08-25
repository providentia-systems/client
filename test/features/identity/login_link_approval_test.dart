import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:providentia/features/identity/application/login_link_approval_port.dart';
import 'package:providentia/features/identity/domain/login_link_approval_models.dart';
import 'package:providentia/features/identity/infrastructure/generated_login_link_approval_transport.dart';
import 'package:providentia/features/identity/presentation/login_link_approval_controller.dart';
import 'package:providentia/features/identity/presentation/login_link_approval_page.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

void main() {
  test('approval capability accepts only the homeowner fragment contract', () {
    final capability = LoginLinkApprovalCapability.parse(_link);

    expect(capability.requestId, _requestId);
    expect(capability.approvalToken, _token);
    expect(capability.toString(), 'LoginLinkApprovalCapability(<redacted>)');
    for (final invalid in <Uri>[
      Uri.parse(
        'providentia://login-link/admin#requestId=$_requestId&approval=$_token',
      ),
      Uri.parse(
        'providentia://login-link/homeowner?approval=$_token#requestId=$_requestId',
      ),
      Uri.parse(
        'providentia://login-link/homeowner#requestId=$_requestId&approval=$_token&approval=$_token',
      ),
      Uri.parse(
        'providentia://login-link/homeowner#requestId=$_requestId&approval=$_token&extra=value',
      ),
    ]) {
      expect(
        () => LoginLinkApprovalCapability.parse(invalid),
        throwsFormatException,
      );
    }
  });

  test('transport proves, reviews, and decides as homeowner only', () async {
    final requests = <http.Request>[];
    final transport = GeneratedLoginLinkApprovalTransport(
      _client((request) async {
        requests.add(request);
        final body = jsonDecode(request.body) as Map<String, Object?>;
        expect(body['applicationKind'], 'homeowner');
        expect(body['approvalToken'], _token);
        if (request.url.path.endsWith('/proof')) {
          return _json(<String, Object?>{
            'valid': true,
            'requestId': _requestId,
            'applicationKind': 'homeowner',
            'expiresAt': '2026-08-25T15:00:00Z',
          });
        }
        if (request.url.path.endsWith('/review')) {
          return _json(<String, Object?>{
            'requestId': _requestId,
            'applicationKind': 'homeowner',
            'deviceName': 'Kitchen laptop',
            'platform': 'linux',
            'createdAt': '2026-08-25T14:00:00Z',
            'expiresAt': '2026-08-25T15:00:00Z',
          });
        }
        expect(body['decision'], 'approve');
        return _json(<String, Object?>{
          'requestId': _requestId,
          'applicationKind': 'homeowner',
          'status': 'received',
        }, statusCode: 202);
      }),
    );
    final capability = LoginLinkApprovalCapability.parse(_link);

    await transport.prove(capability);
    final review = await transport.review(capability);
    await transport.decide(
      capability: capability,
      decision: LoginLinkApprovalDecision.approve,
    );

    expect(review.deviceName, 'Kitchen laptop');
    expect(requests, hasLength(3));
    expect(requests.map((request) => request.url.path), <String>[
      '/api/v1/auth/login-links/$_requestId/proof',
      '/api/v1/auth/login-links/$_requestId/review',
      '/api/v1/auth/login-links/$_requestId/decision',
    ]);
  });

  test(
    'transport rejects an admin-kind response in the homeowner client',
    () async {
      final transport = GeneratedLoginLinkApprovalTransport(
        _client(
          (_) async => _json(<String, Object?>{
            'valid': true,
            'requestId': _requestId,
            'applicationKind': 'admin',
            'expiresAt': '2026-08-25T15:00:00Z',
          }),
        ),
      );

      await expectLater(
        transport.prove(LoginLinkApprovalCapability.parse(_link)),
        throwsA(
          isA<LoginLinkApprovalException>().having(
            (error) => error.kind,
            'kind',
            LoginLinkApprovalFailureKind.invalidResponse,
          ),
        ),
      );
    },
  );

  testWidgets('review page makes one explicit decision and cannot replay it', (
    tester,
  ) async {
    final transport = _ApprovalTransport();
    final controller = LoginLinkApprovalController(
      transport: transport,
      clock: () => DateTime.utc(2026, 8, 25, 14, 30),
    );
    addTearDown(controller.dispose);
    await controller.receive(_link);
    await tester.pumpWidget(
      MaterialApp(home: LoginLinkApprovalPage(controller: controller)),
    );

    expect(find.text('Device: Kitchen laptop'), findsOneWidget);
    await tester.tap(find.byKey(const Key('login-link-approve')));
    await tester.pumpAndSettle();

    expect(transport.decisions, <LoginLinkApprovalDecision>[
      LoginLinkApprovalDecision.approve,
    ]);
    expect(
      find.text('Login approved. Return to the requesting device.'),
      findsOneWidget,
    );
    await controller.decide(LoginLinkApprovalDecision.approve);
    expect(transport.decisions, hasLength(1));
  });

  test('cancel defeats a late review and forgets its capability', () async {
    final transport = _ApprovalTransport()..reviewGate = Completer<void>();
    final controller = LoginLinkApprovalController(
      transport: transport,
      clock: () => DateTime.utc(2026, 8, 25, 14, 30),
    );
    final receiving = controller.receive(_link);
    await Future<void>.delayed(Duration.zero);

    controller.cancel();
    transport.reviewGate!.complete();
    await receiving;

    expect(controller.snapshot.status, LoginLinkApprovalStatus.idle);
    await controller.decide(LoginLinkApprovalDecision.approve);
    expect(transport.decisions, isEmpty);
    controller.dispose();
  });
}

final class _ApprovalTransport implements LoginLinkApprovalPort {
  final List<LoginLinkApprovalDecision> decisions =
      <LoginLinkApprovalDecision>[];
  Completer<void>? reviewGate;

  @override
  Future<void> prove(LoginLinkApprovalCapability capability) async {}

  @override
  Future<LoginLinkApprovalReview> review(
    LoginLinkApprovalCapability capability,
  ) async {
    await reviewGate?.future;
    return LoginLinkApprovalReview(
      requestId: capability.requestId,
      deviceName: 'Kitchen laptop',
      platform: 'linux',
      createdAt: DateTime.utc(2026, 8, 25, 14),
      expiresAt: DateTime.utc(2026, 8, 25, 15),
    );
  }

  @override
  Future<void> decide({
    required LoginLinkApprovalCapability capability,
    required LoginLinkApprovalDecision decision,
  }) async {
    decisions.add(decision);
  }
}

ProvidentiaApiClient _client(
  Future<http.Response> Function(http.Request request) handler,
) => ProvidentiaApiClient(
  baseUri: Uri.parse('https://api.example.test'),
  httpClient: MockClient(handler),
);

http.Response _json(Object body, {int statusCode = 200}) => http.Response(
  jsonEncode(body),
  statusCode,
  headers: const <String, String>{'content-type': 'application/json'},
);

const String _requestId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const String _token = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN_1234567890';
final Uri _link = Uri.parse(
  'providentia://login-link/homeowner#requestId=$_requestId&approval=$_token',
);
