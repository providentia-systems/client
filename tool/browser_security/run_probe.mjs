import {spawn} from 'node:child_process';
import {createServer} from 'node:http';
import {mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';

// Both endpoints are owned by this process. Chromium is discovered only from
// DevToolsActivePort inside this new temporary profile, never a guessed port.
// No user browser/profile/account or production application is attached.
const profile = await mkdtemp(join(tmpdir(), 'providentia-browser-proof-'));
const assets = new Map([
  ['/', ['index.html', 'text/html']],
  ['/probe.js', ['probe.js', 'text/javascript']],
  ['/sqlite3.wasm', ['sqlite3.wasm', 'application/wasm']],
]);
const server = createServer(async (request, response) => {
  const asset = assets.get(new URL(request.url, 'http://localhost').pathname);
  if (!asset) { response.writeHead(404).end(); return; }
  try {
    const bytes = await readFile(join('build/browser-security-proof', asset[0]));
    response.writeHead(200, {'Content-Type': asset[1], 'Cache-Control': 'no-store'}).end(bytes);
  } catch { response.writeHead(500).end(); }
});
let browser;
let browserErrors = '';
let launchError;
let socket;
const delay = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
async function connect(url) {
  socket = new WebSocket(url);
  await new Promise((resolve, reject) => { socket.onopen = resolve; socket.onerror = reject; });
  let sequence = 0;
  const pending = new Map();
  function failAll() {
    for (const entry of pending.values()) { clearTimeout(entry.timer); entry.reject(new Error('Owned Chromium connection closed')); }
    pending.clear();
  }
  socket.onclose = failAll;
  socket.onerror = failAll;
  socket.onmessage = event => {
    const value = JSON.parse(event.data);
    const entry = pending.get(value.id);
    if (entry) {
      clearTimeout(entry.timer); pending.delete(value.id);
      value.error ? entry.reject(new Error(JSON.stringify(value.error))) : entry.resolve(value.result);
    }
  };
  return (method, params, sessionId) => new Promise((resolve, reject) => {
    if (socket.readyState !== WebSocket.OPEN) { reject(new Error('Owned Chromium is disconnected')); return; }
    const id = ++sequence;
    const timer = setTimeout(() => { pending.delete(id); reject(new Error(`CDP ${method} timed out`)); }, 15000);
    pending.set(id, {resolve, reject, timer});
    socket.send(JSON.stringify({id, method, params, ...(sessionId ? {sessionId} : {})}));
  });
}
async function resultFrom(call) {
  const deadline = Date.now() + 120000;
  while (Date.now() < deadline) {
    const answer = await call('Runtime.evaluate', {expression: 'window.probeResult', returnByValue: true});
    if (answer.result?.value) {
      const result = JSON.parse(answer.result.value);
      if (!result.ok) throw new Error(JSON.stringify(result, null, 2));
      return result.results;
    }
    await delay(100);
  }
  throw new Error('Browser proof timed out without a result');
}
try {
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
  const origin = `http://127.0.0.1:${server.address().port}`;
  browser = spawn(process.env.CHROME_EXECUTABLE || '/usr/bin/chromium', [
    '--headless', '--no-sandbox', '--disable-gpu', `--user-data-dir=${profile}`,
    '--remote-debugging-port=0', 'about:blank',
  ], {stdio: ['ignore', 'ignore', 'pipe'], env: {...process.env, HOME: profile}});
  browser.on('error', error => { launchError = error; });
  browser.stderr.on('data', chunk => { browserErrors += chunk.toString(); });
  let endpoint;
  for (let i = 0; i < 100; i++) {
    if (launchError || browser.exitCode !== null) throw new Error(`Chromium did not launch: ${launchError ?? browserErrors}`);
    try {
      const [port, path] = (await readFile(join(profile, 'DevToolsActivePort'), 'utf8')).trim().split('\n');
      if (/^\d+$/.test(port) && path.startsWith('/devtools/browser/')) {
        endpoint = `ws://127.0.0.1:${port}${path}`; break;
      }
    } catch {}
    await delay(100);
  }
  if (!endpoint) throw new Error(`Owned Chromium did not become ready: ${browserErrors}`);
  const control = await connect(endpoint);
  const version = await control('Browser.getVersion');
  async function open(mode) {
    const {targetId} = await control('Target.createTarget', {url: `${origin}/?mode=${mode}`});
    const {sessionId} = await control('Target.attachToTarget', {targetId, flatten: true});
    return {id: targetId, call: (method, params) => control(method, params, sessionId)};
  }
  const seed = await open('seed');
  const results = await resultFrom(seed.call);
  const busy = await open('busy');
  results.push(...await resultFrom(busy.call));
  await control('Target.closeTarget', {targetId: busy.id});
  // Destroy the document without vault.close(). A fresh page has neither the
  // original key reference nor the original SQLite/WASM connection.
  await control('Target.closeTarget', {targetId: seed.id});
  const reopened = await open('reopen');
  results.push(...await resultFrom(reopened.call));
  results.push('full document destruction and fresh-tab passphrase unlock preserve projection and outbox');
  const evidence = JSON.stringify({ok: true, browser: version.product, results}, null, 2);
  await writeFile('build/browser-security-proof/result.json', `${evidence}\n`);
  console.log(evidence);
} finally {
  socket?.close();
  browser?.kill();
  await new Promise(resolve => server.close(resolve));
  await delay(300);
  await rm(profile, {recursive: true, force: true, maxRetries: 5, retryDelay: 200});
}
