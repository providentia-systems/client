#!/usr/bin/env node

import {randomUUID} from 'node:crypto';
import {writeFile} from 'node:fs/promises';
import process from 'node:process';
import {chromium, firefox, webkit} from 'playwright';

import {
  createLoginLinkProof,
  extractApprovalLink,
  isLoginLinkProofShape,
  isUuid,
  redactSensitiveText,
} from './login_link_acceptance_protocol.mjs';

const API_TIMEOUT_MS = 15_000;
const APPROVAL_PAGE_TIMEOUT_MS = 30_000;
const APPROVAL_STATUS_TIMEOUT_MS = 90_000;
const WEB_IDLE_SECONDS = 30 * 24 * 60 * 60;
const LOGIN_LINK_TTL_MS = 15 * 60 * 1000;
const LOGIN_LINK_TTL_TOLERANCE_MS = 30_000;
const SESSION_COOKIE_NAMES = [
  'providentia_access',
  'providentia_refresh',
  'providentia_csrf',
];

const [targetUrl, browserName, evidenceFile] = process.argv.slice(2);
if (!targetUrl || !browserName || !evidenceFile) {
  throw new Error('Usage: verify_web_runtime.mjs URL BROWSER EVIDENCE_FILE');
}
const target = secureUrl(targetUrl, 'PWA target');
const browserType = browserName === 'firefox'
  ? firefox
  : browserName === 'webkit'
    ? webkit
    : chromium;
const launchOptions = browserName === 'chrome'
  ? {channel: 'chrome'}
  : browserName === 'edge'
    ? {channel: 'msedge'}
    : {};
const sensitiveValues = new Set(
  [
    process.env.E2E_USER_EMAIL,
    process.env.E2E_MAILBOX_IMAP_USER,
    process.env.E2E_MAILBOX_IMAP_PASSWORD,
  ].filter((value) => typeof value === 'string' && value !== ''),
);
const browser = await browserType.launch(launchOptions);
const context = await browser.newContext({serviceWorkers: 'allow'});
const page = await context.newPage();
const evidence = {
  schemaVersion: 2,
  target: target.origin,
  browser: browserName,
  startedAt: new Date().toISOString(),
  checks: {},
};
let failure;

try {
  const response = await page.goto(target.href, {waitUntil: 'networkidle'});
  assert(response?.ok(), `Initial page returned HTTP ${response?.status() ?? 'unknown'}.`);
  evidence.checks.initialLoad = true;

  const manifestHref = await page.locator('link[rel="manifest"]').getAttribute('href');
  assert(manifestHref, 'PWA manifest link is missing.');
  const manifestResponse = await context.request.get(new URL(manifestHref, target).href);
  assert(manifestResponse.ok(), 'PWA manifest is unavailable.');
  const manifest = await manifestResponse.json();
  assert(manifest.display === 'standalone', 'PWA manifest must use standalone display mode.');
  evidence.checks.manifest = true;

  await page.waitForFunction(() => 'serviceWorker' in navigator, undefined, {
    timeout: API_TIMEOUT_MS,
  });
  await within(
    page.evaluate(() => navigator.serviceWorker.ready),
    API_TIMEOUT_MS,
    'The service worker did not become ready before the bounded deadline.',
  );
  evidence.checks.serviceWorker = true;

  const persistenceKey = cryptoRandomId();
  await within(page.evaluate(async (value) => {
    const request = indexedDB.open('providentia-release-acceptance', 1);
    const database = await new Promise((resolve, reject) => {
      request.onupgradeneeded = () => request.result.createObjectStore('evidence');
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
    await new Promise((resolve, reject) => {
      const transaction = database.transaction('evidence', 'readwrite');
      transaction.objectStore('evidence').put(value, 'persistence-key');
      transaction.oncomplete = resolve;
      transaction.onerror = () => reject(transaction.error);
    });
    database.close();
  }, persistenceKey), API_TIMEOUT_MS, 'The IndexedDB write exceeded its bounded deadline.');
  await page.reload({waitUntil: 'networkidle'});
  const persisted = await within(page.evaluate(async () => {
    const request = indexedDB.open('providentia-release-acceptance', 1);
    const database = await new Promise((resolve, reject) => {
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
    const value = await new Promise((resolve, reject) => {
      const transaction = database.transaction('evidence', 'readonly');
      const get = transaction.objectStore('evidence').get('persistence-key');
      get.onsuccess = () => resolve(get.result);
      get.onerror = () => reject(get.error);
    });
    database.close();
    return value;
  }), API_TIMEOUT_MS, 'The IndexedDB read exceeded its bounded deadline.');
  assert(persisted === persistenceKey, 'IndexedDB value did not survive reload.');
  evidence.checks.indexedDbPersistence = true;

  await context.setOffline(true);
  const offlineResponse = await page.reload({waitUntil: 'domcontentloaded'});
  assert(
    offlineResponse === null || offlineResponse.ok(),
    `Service-worker offline reload returned HTTP ${offlineResponse?.status() ?? 'unknown'}.`,
  );
  assert(await page.locator('body').isVisible(), 'Offline PWA reload did not render a document body.');
  await context.setOffline(false);
  evidence.checks.offlineReload = true;

  if (process.env.E2E_REQUIRE_AUTH === '1') {
    await verifyLoginLinkAuthentication({
      browser,
      context,
      page,
      record: evidence,
      target,
      browserName,
      sensitiveValues,
    });
  } else {
    evidence.checks.authentication = 'not-requested';
  }
  evidence.finishedAt = new Date().toISOString();
  evidence.outcome = 'passed';
} catch (error) {
  const message = safeErrorMessage(error, sensitiveValues);
  evidence.finishedAt = new Date().toISOString();
  evidence.outcome = 'failed';
  evidence.error = message;
  failure = new Error(message);
} finally {
  await writeFile(evidenceFile, `${JSON.stringify(evidence, null, 2)}\n`, 'utf8');
  await context.close();
  await browser.close();
}

if (failure) throw failure;

async function verifyLoginLinkAuthentication({
  browser,
  context,
  page,
  record,
  target: pwaTarget,
  browserName: selectedBrowser,
  sensitiveValues: secrets,
}) {
  for (const name of [
    'E2E_API_BASE_URL',
    'E2E_HOMEOWNER_APP_LINK_BASE',
    'E2E_USER_EMAIL',
    'E2E_MAILBOX_IMAP_HOST',
    'E2E_MAILBOX_IMAP_USER',
    'E2E_MAILBOX_IMAP_PASSWORD',
  ]) {
    assert(process.env[name], `${name} is required when authenticated browser acceptance is enabled.`);
  }
  assert(
    process.env.E2E_MAILBOX_IMAP_SECURE === 'true',
    'The controlled acceptance mailbox must use TLS-secured IMAP.',
  );

  const apiBase = secureUrl(process.env.E2E_API_BASE_URL, 'API base URL');
  const appLinkBase = secureUrl(
    process.env.E2E_HOMEOWNER_APP_LINK_BASE,
    'homeowner app-link base URL',
  );
  assert(
    appLinkBase.origin === pwaTarget.origin,
    'The homeowner app-link must open the deployed PWA origin.',
  );
  const email = process.env.E2E_USER_EMAIL.trim().toLowerCase();
  assert(/^[^\s@]+@[^\s@]+\.[^\s@]+$/u.test(email), 'The synthetic acceptance email is invalid.');
  const mailboxTimeoutMs = boundedInteger(
    process.env.E2E_MAILBOX_TIMEOUT_SECONDS ?? '120',
    30,
    300,
    'E2E_MAILBOX_TIMEOUT_SECONDS',
  ) * 1000;
  const proof = createLoginLinkProof();
  assert(isLoginLinkProofShape(proof), 'The origin login proof could not be generated safely.');
  for (const value of [proof.pollToken, proof.codeVerifier, proof.state]) secrets.add(value);

  const requestStartedAt = new Date();
  const start = await browserJson(page, new URL('/api/v1/auth/login-links', apiBase), {
    method: 'POST',
    body: {
      requestId: proof.requestId,
      email,
      applicationKind: 'homeowner',
      pollChallenge: proof.pollChallenge,
      codeChallenge: proof.codeChallenge,
      codeChallengeMethod: 'S256',
      state: proof.state,
      installationId: proof.installationId,
      deviceName: `release-${selectedBrowser}`,
      platform: `web-${selectedBrowser}`,
      transport: 'web',
      requestedSessionIdleSeconds: WEB_IDLE_SECONDS,
    },
  });
  assert(start.status === 202, `Login-link start returned HTTP ${start.status}.`);
  assert(start.json, 'Login-link start did not return JSON.');
  assert(start.body?.accepted === true, 'Login-link start was not accepted generically.');
  assert(start.body?.requestId === proof.requestId, 'Login-link start returned another request identifier.');
  assert(
    Number.isInteger(start.body?.pollIntervalSeconds)
      && start.body.pollIntervalSeconds >= 1
      && start.body.pollIntervalSeconds <= 30,
    'Login-link start returned an invalid polling interval.',
  );
  const expiresAt = Date.parse(start.body?.expiresAt ?? '');
  assert(Number.isFinite(expiresAt) && expiresAt > Date.now(), 'Login-link expiry is invalid.');
  assert(
    expiresAt <= requestStartedAt.getTime() + LOGIN_LINK_TTL_MS + LOGIN_LINK_TTL_TOLERANCE_MS,
    'Login-link expiry exceeds the 15-minute acceptance policy.',
  );
  record.checks.loginLinkStarted = true;

  const approvalLink = await waitForApprovalLink({
    requestId: proof.requestId,
    email,
    startedAt: requestStartedAt,
    timeoutMs: mailboxTimeoutMs,
    expectedApprovalBase: appLinkBase.href,
  });
  secrets.add(approvalLink);
  const approvalCapability = new URLSearchParams(
    new URL(approvalLink).hash.slice(1),
  ).get('approval') ?? '';
  if (approvalCapability !== '') secrets.add(decodeURIComponent(approvalCapability));
  record.checks.mailboxDelivery = true;

  const approvalContext = await browser.newContext({serviceWorkers: 'block'});
  try {
    const approvalPage = await approvalContext.newPage();
    const proofResponse = approvalPage.waitForResponse((response) =>
      response.request().method() === 'POST'
      && response.url().endsWith(`/api/v1/auth/login-links/${proof.requestId}/proof`),
    );
    const reviewResponse = approvalPage.waitForResponse((response) =>
      response.request().method() === 'POST'
      && response.url().endsWith(`/api/v1/auth/login-links/${proof.requestId}/review`),
    );
    await approvalPage.goto(approvalLink, {
      waitUntil: 'domcontentloaded',
      timeout: APPROVAL_PAGE_TIMEOUT_MS,
    });
    const [proofResult, reviewResult] = await Promise.all([
      proofResponse,
      reviewResponse,
    ]);
    assert(proofResult.status() === 200, `App-owned login proof returned HTTP ${proofResult.status()}.`);
    assert(reviewResult.status() === 200, `App-owned login review returned HTTP ${reviewResult.status()}.`);
    await approvalPage.getByText('A device wants to sign in', {exact: true}).waitFor({
      timeout: APPROVAL_PAGE_TIMEOUT_MS,
    });
    assert(
      new URL(approvalPage.url()).hash === '',
      'The homeowner app did not remove the approval capability from browser history.',
    );

    const beforeDecision = await getLoginLinkStatus(page, apiBase, proof);
    assert(beforeDecision === 'pending', 'Opening the email link unexpectedly approved the request.');
    record.checks.scannerSafeReview = true;

    const decisionResponse = approvalPage.waitForResponse((response) =>
      response.request().method() === 'POST'
      && response.url().endsWith(`/api/v1/auth/login-links/${proof.requestId}/decision`),
    );
    await approvalPage.getByRole('button', {name: 'Approve login', exact: true}).click({
      timeout: APPROVAL_PAGE_TIMEOUT_MS,
    });
    const decisionResult = await decisionResponse;
    assert(
      decisionResult.status() === 202,
      `App-owned login decision returned HTTP ${decisionResult.status()}.`,
    );
    await approvalPage.getByText(
      'Login approved. Return to the requesting device.',
      {exact: true},
    ).waitFor({
      timeout: APPROVAL_PAGE_TIMEOUT_MS,
    });
    const browserBootstrap = await approvalContext.request.get(
      new URL('/api/v1/me', apiBase).href,
      {timeout: API_TIMEOUT_MS},
    );
    assert(
      browserBootstrap.status() === 401 || browserBootstrap.status() === 403,
      'The approval browser received an authenticated session.',
    );
    record.checks.explicitAppOwnedApproval = true;
    record.checks.approvalBrowserUnauthenticated = true;
  } finally {
    await approvalContext.close();
  }

  const approved = await waitForLoginLinkApproval({
    page,
    apiBase,
    proof,
    pollIntervalSeconds: start.body.pollIntervalSeconds,
  });
  assert(approved === 'approved', `The login request reached terminal state ${approved}.`);
  record.checks.originObservedApproval = true;

  const exchange = await browserJson(
    page,
    new URL(`/api/v1/auth/login-links/${proof.requestId}/exchange`, apiBase),
    {
      method: 'POST',
      body: {
        pollToken: proof.pollToken,
        codeVerifier: proof.codeVerifier,
        state: proof.state,
      },
    },
  );
  assert(exchange.status === 200, `Login-link exchange returned HTTP ${exchange.status}.`);
  assert(exchange.json, 'Login-link exchange did not return JSON.');
  validateWebSession(exchange.body, proof.installationId);
  for (const value of [
    exchange.body?.csrfToken,
    exchange.body?.accessToken,
    exchange.body?.refreshToken,
  ]) {
    if (typeof value === 'string' && value !== '') secrets.add(value);
  }
  assert(
    !Object.hasOwn(exchange.body, 'accessToken') && !Object.hasOwn(exchange.body, 'refreshToken'),
    'Web exchange exposed bearer credentials.',
  );
  record.checks.originExchange = true;

  const exchangeCookies = await sessionCookies(context, apiBase);
  validateSessionCookies(exchangeCookies, apiBase.protocol === 'https:');
  record.checks.secureCookieSession = true;

  const bootstrap = await authenticatedBootstrap(page, apiBase);
  validateBootstrap(bootstrap, {
    email,
    sessionId: exchange.body.sessionId,
    deviceId: proof.installationId,
    activeHomeId: exchange.body.activeHomeId,
  });
  const homes = await browserJson(page, new URL('/api/v1/homes', apiBase), {method: 'GET'});
  assert(homes.status === 200 && homes.json && Array.isArray(homes.body?.data), 'Authorized homes are unavailable.');
  assert(homes.body.data.length > 0, 'The synthetic account has no home membership.');
  const bootstrapHomeIds = new Set(bootstrap.homes.map((home) => home.id));
  assert(
    homes.body.data.every((home) => bootstrapHomeIds.has(home.id)),
    'The home list disagrees with the authenticated bootstrap.',
  );
  record.checks.authenticatedBootstrap = true;
  record.checks.homeMembership = true;

  const secondTab = await context.newPage();
  try {
    await secondTab.goto(pwaTarget.href, {waitUntil: 'domcontentloaded'});
    const secondBootstrap = await authenticatedBootstrap(secondTab, apiBase);
    validateBootstrap(secondBootstrap, {
      email,
      sessionId: exchange.body.sessionId,
      deviceId: proof.installationId,
      activeHomeId: exchange.body.activeHomeId,
    });
  } finally {
    await secondTab.close();
  }
  record.checks.cookieSessionSharedAcrossTabs = true;

  const refresh = await browserJson(page, new URL('/api/v1/auth/refresh', apiBase), {
    method: 'POST',
    headers: {'X-CSRF-Token': exchange.body.csrfToken},
    body: {},
  });
  assert(refresh.status === 200, `Session refresh returned HTTP ${refresh.status}.`);
  assert(refresh.json, 'Session refresh did not return JSON.');
  validateWebSession(refresh.body, proof.installationId);
  assert(refresh.body.sessionId === exchange.body.sessionId, 'Refresh changed the current session identifier.');
  assert(refresh.body.userId === exchange.body.userId, 'Refresh changed the authenticated account.');
  for (const value of [refresh.body?.csrfToken, refresh.body?.accessToken, refresh.body?.refreshToken]) {
    if (typeof value === 'string' && value !== '') secrets.add(value);
  }
  assert(
    !Object.hasOwn(refresh.body, 'accessToken') && !Object.hasOwn(refresh.body, 'refreshToken'),
    'Web refresh exposed bearer credentials.',
  );
  const refreshedCookies = await sessionCookies(context, apiBase);
  validateSessionCookies(refreshedCookies, apiBase.protocol === 'https:');
  assert(
    exchangeCookies.get('providentia_refresh')?.value
      !== refreshedCookies.get('providentia_refresh')?.value,
    'Refresh did not rotate the persistent session cookie.',
  );
  await authenticatedBootstrap(page, apiBase);
  record.checks.sessionRefresh = true;

  const logout = await browserJson(page, new URL('/api/v1/auth/logout', apiBase), {
    method: 'POST',
    headers: {'X-CSRF-Token': refresh.body.csrfToken},
    body: {},
  });
  assert(logout.status === 204, `Logout returned HTTP ${logout.status}.`);
  const remainingCookies = await sessionCookies(context, apiBase);
  assert(remainingCookies.size === 0, 'Logout did not clear every session cookie.');
  const afterLogout = await browserJson(page, new URL('/api/v1/me', apiBase), {method: 'GET'});
  assert(
    afterLogout.status === 401 || afterLogout.status === 403,
    `Post-logout bootstrap returned HTTP ${afterLogout.status}.`,
  );
  const homesAfterLogout = await browserJson(page, new URL('/api/v1/homes', apiBase), {method: 'GET'});
  assert(
    homesAfterLogout.status === 401 || homesAfterLogout.status === 403,
    `Post-logout home read returned HTTP ${homesAfterLogout.status}.`,
  );
  record.checks.logoutRevocation = true;
  record.checks.authentication = true;
}

async function waitForApprovalLink({
  requestId,
  email,
  startedAt,
  timeoutMs,
  expectedApprovalBase,
}) {
  const port = boundedInteger(
    process.env.E2E_MAILBOX_IMAP_PORT ?? '993',
    1,
    65_535,
    'E2E_MAILBOX_IMAP_PORT',
  );
  const folder = (process.env.E2E_MAILBOX_IMAP_FOLDER ?? 'INBOX').trim();
  assert(folder !== '', 'E2E_MAILBOX_IMAP_FOLDER cannot be empty.');
  const {ImapFlow} = await import('imapflow');
  const client = new ImapFlow({
    host: process.env.E2E_MAILBOX_IMAP_HOST,
    port,
    secure: true,
    auth: {
      user: process.env.E2E_MAILBOX_IMAP_USER,
      pass: process.env.E2E_MAILBOX_IMAP_PASSWORD,
    },
    logger: false,
    connectionTimeout: 10_000,
    greetingTimeout: 10_000,
    socketTimeout: 30_000,
  });
  client.on('error', () => {});
  const deadline = Date.now() + timeoutMs;
  const searchedSince = new Date(startedAt.getTime() - 60_000);
  const inspected = new Set();
  let lock;

  try {
    await client.connect();
    lock = await client.getMailboxLock(folder, {
      readOnly: true,
      acquireTimeout: 10_000,
    });
    while (Date.now() < deadline) {
      const uids = (await client.search(
        {since: searchedSince, subject: 'Approve your Providentia login'},
        {uid: true},
      )) || [];
      const candidates = uids.slice(-200).reverse();
      for (const uid of candidates) {
        if (inspected.has(uid)) continue;
        inspected.add(uid);
        const message = await client.fetchOne(uid, {envelope: true, source: true}, {uid: true});
        if (!message?.source || !recipientMatches(message.envelope?.to, email)) continue;
        if (!message.source.includes(requestId)) continue;
        return extractApprovalLink(message.source, requestId, expectedApprovalBase);
      }
      await delay(Math.min(3000, Math.max(0, deadline - Date.now())));
    }
  } catch {
    throw new Error('The controlled mailbox could not be read safely for login-link acceptance.');
  } finally {
    lock?.release();
    if (client.usable) {
      try {
        await client.logout();
      } catch {
        client.close();
      }
    }
  }
  throw new Error('No matching login-link message arrived before the bounded mailbox deadline.');
}

async function getLoginLinkStatus(page, apiBase, proof) {
  const result = await browserJson(
    page,
    new URL(`/api/v1/auth/login-links/${proof.requestId}/status`, apiBase),
    {method: 'POST', body: {pollToken: proof.pollToken}},
  );
  assert(result.status === 200, `Login-link status returned HTTP ${result.status}.`);
  assert(result.json, 'Login-link status did not return JSON.');
  assert(result.body?.requestId === proof.requestId, 'Login-link status returned another request identifier.');
  assert(result.body?.applicationKind === 'homeowner', 'Login-link status crossed the application boundary.');
  assert(
    ['pending', 'approved', 'denied', 'exchanged', 'expired', 'cancelled'].includes(result.body?.status),
    'Login-link status returned an invalid state.',
  );
  return result.body.status;
}

async function waitForLoginLinkApproval({page, apiBase, proof, pollIntervalSeconds}) {
  const deadline = Date.now() + APPROVAL_STATUS_TIMEOUT_MS;
  while (Date.now() < deadline) {
    const result = await browserJson(
      page,
      new URL(`/api/v1/auth/login-links/${proof.requestId}/status`, apiBase),
      {method: 'POST', body: {pollToken: proof.pollToken}},
    );
    if (result.status === 200 && result.json) {
      assert(result.body?.requestId === proof.requestId, 'Login-link status returned another request identifier.');
      assert(result.body?.applicationKind === 'homeowner', 'Login-link status crossed the application boundary.');
      const status = result.body?.status;
      assert(
        ['pending', 'approved', 'denied', 'exchanged', 'expired', 'cancelled'].includes(status),
        'Login-link status returned an invalid state.',
      );
      if (status !== 'pending') return status;
    } else if (result.status !== 429 && !result.networkError) {
      throw new Error(`Login-link status returned HTTP ${result.status}.`);
    }
    await delay(Math.max(1000, Math.min(30_000, pollIntervalSeconds * 1000)));
  }
  throw new Error('The originating client did not observe approval before the bounded deadline.');
}

async function authenticatedBootstrap(page, apiBase) {
  const response = await browserJson(page, new URL('/api/v1/me', apiBase), {method: 'GET'});
  assert(response.status === 200, `Authenticated bootstrap returned HTTP ${response.status}.`);
  assert(response.json && response.body, 'Authenticated bootstrap did not return JSON.');
  return response.body;
}

function validateWebSession(session, installationId) {
  assert(session && typeof session === 'object', 'The web session response is invalid.');
  assert(isUuid(session.sessionId), 'The web session identifier is invalid.');
  assert(session.deviceId === installationId, 'The web session is not bound to the originating installation.');
  assert(isUuid(session.userId), 'The authenticated account identifier is invalid.');
  assert(session.transport === 'web', 'The exchange did not issue a web session.');
  assert(typeof session.csrfToken === 'string' && session.csrfToken.length >= 40, 'The CSRF proof is invalid.');
  assert(session.refreshIdleTtlSeconds === WEB_IDLE_SECONDS, 'The web session is not using the 30-day idle policy.');
  for (const field of ['accessExpiresAt', 'refreshExpiresAt', 'idleExpiresAt']) {
    assert(Number.isFinite(Date.parse(session[field] ?? '')), `The web session ${field} is invalid.`);
  }
}

function validateBootstrap(bootstrap, {email, sessionId, deviceId, activeHomeId}) {
  assert(bootstrap?.email?.toLowerCase() === email, 'Bootstrap returned another account.');
  assert(bootstrap.emailVerified === true, 'The synthetic account email is not verified.');
  assert(Array.isArray(bootstrap.homes) && bootstrap.homes.length > 0, 'Bootstrap returned no home membership.');
  assert(bootstrap.currentSession?.id === sessionId, 'Bootstrap returned another current session.');
  assert(bootstrap.currentSession?.deviceId === deviceId, 'Bootstrap returned another installation.');
  assert(bootstrap.currentSession?.current === true, 'Bootstrap did not mark the current session.');
  assert(bootstrap.currentSession?.transport === 'web', 'Bootstrap returned a non-web current session.');
  assert(bootstrap.activeHomeId === activeHomeId, 'Bootstrap active home disagrees with the session grant.');
  assert(
    typeof bootstrap.activeHomeId === 'string'
      && bootstrap.homes.some((home) => home?.id === bootstrap.activeHomeId),
    'Bootstrap did not select an authorized active home.',
  );
}

async function sessionCookies(context, apiBase) {
  const cookies = await context.cookies(apiBase.href);
  return new Map(
    cookies
      .filter((cookie) => SESSION_COOKIE_NAMES.includes(cookie.name))
      .map((cookie) => [cookie.name, cookie]),
  );
}

function validateSessionCookies(cookies, requireSecure) {
  assert(cookies.size === SESSION_COOKIE_NAMES.length, 'The web session cookie set is incomplete.');
  for (const name of SESSION_COOKIE_NAMES) {
    const cookie = cookies.get(name);
    assert(cookie, `The ${name} session cookie is missing.`);
    assert(cookie.sameSite === 'Strict', `The ${name} session cookie is not SameSite=Strict.`);
    if (requireSecure) assert(cookie.secure, `The ${name} session cookie is not Secure.`);
  }
  assert(cookies.get('providentia_access').httpOnly, 'The access cookie is not HttpOnly.');
  assert(cookies.get('providentia_refresh').httpOnly, 'The refresh cookie is not HttpOnly.');
  assert(!cookies.get('providentia_csrf').httpOnly, 'The CSRF cookie must remain readable by the client.');
}

async function browserJson(page, url, {method, headers = {}, body}) {
  return page.evaluate(async ({requestUrl, requestMethod, requestHeaders, requestBody, timeoutMs}) => {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const response = await fetch(requestUrl, {
        method: requestMethod,
        credentials: 'include',
        headers: {
          Accept: 'application/json',
          ...(requestBody === undefined ? {} : {'Content-Type': 'application/json'}),
          ...requestHeaders,
        },
        body: requestBody === undefined ? undefined : JSON.stringify(requestBody),
        signal: controller.signal,
      });
      const text = await response.text();
      if (text === '') {
        return {status: response.status, json: true, body: null, networkError: false};
      }
      try {
        return {
          status: response.status,
          json: true,
          body: JSON.parse(text),
          networkError: false,
        };
      } catch {
        return {status: response.status, json: false, body: null, networkError: false};
      }
    } catch {
      return {status: 0, json: false, body: null, networkError: true};
    } finally {
      clearTimeout(timer);
    }
  }, {
    requestUrl: url.href,
    requestMethod: method,
    requestHeaders: headers,
    requestBody: body,
    timeoutMs: API_TIMEOUT_MS,
  });
}

function recipientMatches(recipients, expectedEmail) {
  return Array.isArray(recipients)
    && recipients.some((recipient) => recipient?.address?.toLowerCase() === expectedEmail);
}

function secureUrl(value, label) {
  let url;
  try {
    url = new URL(value);
  } catch {
    throw new Error(`${label} is not an absolute URL.`);
  }
  assert(url.username === '' && url.password === '', `${label} must not contain credentials.`);
  assert(
    url.protocol === 'https:' || ['localhost', '127.0.0.1', '::1'].includes(url.hostname),
    `${label} requires HTTPS outside loopback.`,
  );
  return url;
}

function boundedInteger(value, minimum, maximum, name) {
  assert(/^\d+$/u.test(value), `${name} must be an integer.`);
  const parsed = Number.parseInt(value, 10);
  assert(parsed >= minimum && parsed <= maximum, `${name} is outside its safe range.`);
  return parsed;
}

function safeErrorMessage(error, sensitive) {
  return redactSensitiveText(error instanceof Error ? error.message : String(error), sensitive);
}

function cryptoRandomId() {
  return randomUUID();
}

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function within(promise, milliseconds, message) {
  let timer;
  try {
    return await Promise.race([
      promise,
      new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error(message)), milliseconds);
      }),
    ]);
  } finally {
    clearTimeout(timer);
  }
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}
