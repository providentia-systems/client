import assert from 'node:assert/strict';
import test from 'node:test';
import {browserRequestHeaders, HOMEOWNER_SESSION_COOKIES} from './release/browser_session_contract.mjs';

test('browser lifecycle always selects homeowner independently of body or caller header casing', () => {
  for (const body of [undefined, {}, {transport: 'web'}]) {
    const headers = browserRequestHeaders({body, headers: {'x-providentia-application': 'legacy', 'X-CSRF-Token': 'synthetic-proof'}});
    assert.equal(headers['X-Providentia-Application'], 'homeowner');
    assert.equal(headers['x-providentia-application'], undefined);
    assert.equal(headers['X-CSRF-Token'], 'synthetic-proof');
    assert.equal(headers['Content-Type'], body === undefined ? undefined : 'application/json');
  }
  assert.deepEqual(HOMEOWNER_SESSION_COOKIES, ['providentia_homeowner_access', 'providentia_homeowner_refresh', 'providentia_homeowner_csrf']);
});

test('separate application probe is explicit and unknown legacy context is rejected', () => {
  assert.equal(browserRequestHeaders({application: 'admin'})['X-Providentia-Application'], 'admin');
  for (const application of ['', null, 'legacy']) assert.throws(() => browserRequestHeaders({application}));
});
