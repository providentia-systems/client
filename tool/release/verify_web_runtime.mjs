#!/usr/bin/env node

import {randomUUID} from 'node:crypto';
import {writeFile} from 'node:fs/promises';
import process from 'node:process';
import {chromium, firefox, webkit} from 'playwright';

const [targetUrl, browserName, evidenceFile] = process.argv.slice(2);
if (!targetUrl || !browserName || !evidenceFile) {
  throw new Error('Usage: verify_web_runtime.mjs URL BROWSER EVIDENCE_FILE');
}
const target = new URL(targetUrl);
if (target.protocol !== 'https:' && !['localhost', '127.0.0.1', '::1'].includes(target.hostname)) {
  throw new Error('Browser acceptance requires HTTPS outside loopback.');
}

const browserType = browserName === 'firefox' ? firefox : browserName === 'webkit' ? webkit : chromium;
const launchOptions = browserName === 'chrome'
  ? {channel: 'chrome'}
  : browserName === 'edge'
    ? {channel: 'msedge'}
    : {};
const browser = await browserType.launch(launchOptions);
const context = await browser.newContext({serviceWorkers: 'allow'});
const page = await context.newPage();
const evidence = {
  schemaVersion: 1,
  target: target.origin,
  browser: browserName,
  startedAt: new Date().toISOString(),
  checks: {},
};

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

  await page.waitForFunction(() => 'serviceWorker' in navigator);
  await page.evaluate(() => navigator.serviceWorker.ready);
  evidence.checks.serviceWorker = true;

  const persistenceKey = randomUUID();
  await page.evaluate(async (value) => {
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
  }, persistenceKey);
  await page.reload({waitUntil: 'networkidle'});
  const persisted = await page.evaluate(async () => {
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
  });
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
    await verifyCookieAuthentication(page, evidence);
  } else {
    evidence.checks.authentication = 'not-requested';
  }
  evidence.finishedAt = new Date().toISOString();
  evidence.outcome = 'passed';
} catch (error) {
  evidence.finishedAt = new Date().toISOString();
  evidence.outcome = 'failed';
  evidence.error = error instanceof Error ? error.message : String(error);
  throw error;
} finally {
  await writeFile(evidenceFile, `${JSON.stringify(evidence, null, 2)}\n`, 'utf8');
  await context.close();
  await browser.close();
}

async function verifyCookieAuthentication(page, record) {
  for (const name of ['E2E_API_BASE_URL', 'E2E_USER_EMAIL', 'E2E_USER_PASSWORD']) {
    assert(process.env[name], `${name} is required when authenticated browser acceptance is enabled.`);
  }
  const apiBase = new URL(process.env.E2E_API_BASE_URL);
  const result = await page.evaluate(async ({api, email, password, deviceId, browser}) => {
    const login = await fetch(new URL('/api/v1/auth/login', api), {
      method: 'POST',
      credentials: 'include',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({
        email,
        password,
        deviceId,
        deviceName: `release-${browser}`,
        platform: `web-${browser}`,
        transport: 'web',
      }),
    });
    if (!login.ok) return {ok: false, stage: 'login', status: login.status};
    const loginSession = await login.json();
    const csrfToken = typeof loginSession.csrfToken === 'string' ? loginSession.csrfToken : '';
    const csrfHeaders = csrfToken ? {'X-CSRF-Token': csrfToken} : {};
    const homes = await fetch(new URL('/api/v1/homes', api), {credentials: 'include'});
    if (!homes.ok) return {ok: false, stage: 'authorized-read', status: homes.status};
    const refresh = await fetch(new URL('/api/v1/auth/refresh', api), {
      method: 'POST',
      credentials: 'include',
      headers: {'Content-Type': 'application/json', ...csrfHeaders},
      body: '{}',
    });
    if (!refresh.ok) return {ok: false, stage: 'refresh', status: refresh.status};
    const refreshedSession = await refresh.json();
    const refreshedCsrf = typeof refreshedSession.csrfToken === 'string'
      ? refreshedSession.csrfToken
      : csrfToken;
    const logout = await fetch(new URL('/api/v1/auth/logout', api), {
      method: 'POST',
      credentials: 'include',
      headers: refreshedCsrf ? {'X-CSRF-Token': refreshedCsrf} : {},
    });
    if (!logout.ok) return {ok: false, stage: 'logout', status: logout.status};
    const afterLogout = await fetch(new URL('/api/v1/homes', api), {credentials: 'include'});
    return {
      ok: afterLogout.status === 401 || afterLogout.status === 403,
      stage: 'post-logout-read',
      status: afterLogout.status,
    };
  }, {
    api: apiBase.href,
    email: process.env.E2E_USER_EMAIL,
    password: process.env.E2E_USER_PASSWORD,
    deviceId: randomUUID(),
    browser: browserName,
  });
  assert(result.ok, `Authenticated browser check failed at ${result.stage} with HTTP ${result.status}.`);
  record.checks.authentication = true;
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}
