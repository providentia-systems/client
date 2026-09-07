import assert from 'node:assert/strict';
import test from 'node:test';
import {extractEmailCode, isUuid, redactSensitiveText} from './release/email_code_acceptance_protocol.mjs';

test('mail parser accepts eight digits and preserves a leading zero', () => {
  assert.equal(extractEmailCode('Your verification code is:\n\n01234567\n\nEnter it in the app.'), '01234567');
});
test('mail parser reads base64 and quoted printable MIME bodies', () => {
  const text = 'Your verification code is:\n\n01234567\n';
  assert.equal(extractEmailCode('Content-Transfer-Encoding: base64\r\n\r\n' + Buffer.from(text).toString('base64')), '01234567');
  assert.equal(extractEmailCode('Content-Transfer-Encoding: quoted-printable\r\n\r\nYour verification code is:=0A=0A01234567'), '01234567');
});
test('mail parser rejects unrelated numbers, short codes and ambiguous messages', () => {
  for (const text of ['12345678', 'Your verification code is: 1234567', 'Your verification code is: 123456789', 'Your verification code is: 12345678\nYour verification code is: 87654321']) {
    assert.throws(() => extractEmailCode(text), /one valid verification code/u);
  }
});
test('session identifiers are constrained UUID values', () => {
  assert.equal(isUuid('01912345-6789-7abc-8def-0123456789ab'), true);
  assert.equal(isUuid('not-a-session'), false);
});
test('failure evidence redacts mailbox credentials, codes and binding tokens', () => {
  const result = redactSensitiveText('test@example.test password-value code=01234567 bindingToken=secret-proof', ['test@example.test', 'password-value']);
  assert.doesNotMatch(result, /test@example|password-value|01234567|secret-proof/u);
});
