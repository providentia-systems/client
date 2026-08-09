#!/usr/bin/env node

import assert from 'node:assert/strict';
import test from 'node:test';

import {
  createLoginLinkProof,
  extractApprovalLink,
  isLoginLinkProofShape,
  redactSensitiveText,
} from './release/login_link_acceptance_protocol.mjs';

test('acceptance proof is fresh, origin-owned PKCE material', () => {
  const first = createLoginLinkProof();
  const second = createLoginLinkProof();

  assert.equal(isLoginLinkProofShape(first), true);
  assert.equal(isLoginLinkProofShape(second), true);
  assert.notEqual(first.requestId, second.requestId);
  assert.notEqual(first.installationId, second.installationId);
  assert.notEqual(first.pollToken, second.pollToken);
  assert.notEqual(first.codeVerifier, second.codeVerifier);
  assert.notEqual(first.state, second.state);
  assert.notEqual(first.pollToken, first.pollChallenge);
  assert.notEqual(first.codeVerifier, first.codeChallenge);
});

test('mail parser accepts only the exact scanner-safe HTTPS fragment link', () => {
  const requestId = '01912345-6789-7abc-8def-0123456789ab';
  const capability = 'A'.repeat(43);
  const source = Buffer.from([
    'Subject: Approve your Providentia login',
    '',
    'Review this login request:',
    `https://auth.example.test/login-links/${requestId}#approval=${capability}`,
  ].join('\r\n'));

  assert.equal(
    extractApprovalLink(source, requestId, 'https://auth.example.test'),
    `https://auth.example.test/login-links/${requestId}#approval=${capability}`,
  );
});

test('mail parser rejects query credentials, HTTP and another request', () => {
  const requestId = '01912345-6789-7abc-8def-0123456789ab';
  const another = '02912345-6789-7abc-8def-0123456789ab';
  const capability = 'B'.repeat(43);
  const invalidSources = [
    `https://auth.example.test/login-links/${requestId}?approval=${capability}`,
    `http://auth.example.test/login-links/${requestId}#approval=${capability}`,
    `https://attacker.example.test/login-links/${requestId}#approval=${capability}`,
    `https://auth.example.test/login-links/${another}#approval=${capability}`,
    `https://auth.example.test/login-links/${requestId}#approval=short`,
  ];

  for (const source of invalidSources) {
    assert.throws(
      () => extractApprovalLink(source, requestId, 'https://auth.example.test'),
      /did not contain a valid login approval link/u,
    );
  }
});

test('mail parser rejects an invalid configured approval origin', () => {
  const requestId = '01912345-6789-7abc-8def-0123456789ab';
  assert.throws(
    () => extractApprovalLink('', requestId, 'http://auth.example.test'),
    /configured login approval origin is invalid/u,
  );
});

test('failure redaction removes mailbox and protocol capabilities', () => {
  const email = 'acceptance@example.test';
  const password = 'mailbox-password-value';
  const approval = 'C'.repeat(43);
  const pollToken = 'D'.repeat(43);
  const source = `${email} ${password} https://auth.example.test/login-links/request#approval=${approval} pollToken=${pollToken}`;
  const redacted = redactSensitiveText(source, [email, password, pollToken]);

  assert.doesNotMatch(redacted, /acceptance@example\.test/u);
  assert.doesNotMatch(redacted, /mailbox-password-value/u);
  assert.doesNotMatch(redacted, new RegExp(approval, 'u'));
  assert.doesNotMatch(redacted, new RegExp(pollToken, 'u'));
  assert.match(redacted, /#approval=\[redacted\]/u);
});
