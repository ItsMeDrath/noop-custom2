import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { randomBytes, createHash } from 'node:crypto';
import { mkdtemp, readFile, writeFile, chmod, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { loadConfig, UPSTREAM } from '../config.mjs';
import { EncryptedStore, hash, lockStore } from '../store.mjs';
import { createBridge } from '../bridge.mjs';

const key = Buffer.alloc(32, 7);
const syntheticToken = (access = 'synthetic-provider-access', refresh = 'synthetic-provider-refresh', expires = 3600) =>
  ({ access_token: access, refresh_token: refresh, expires_in: expires, token_type: 'Bearer' });
const ok = data => Response.json(data);
const env = { PUBLIC_ORIGIN: 'https://bridge.example.test', WHOOP_CLIENT_ID: 'synthetic-client', WHOOP_CLIENT_SECRET: 'synthetic-client-secret', TOKEN_ENCRYPTION_KEY: key.toString('base64') };

async function fixture(t, options = {}) {
  const dir = await mkdtemp(join(tmpdir(), 'whoop-bridge-test-'));
  const config = loadConfig({ ...env, TOKEN_STORE_PATH: join(dir, 'sessions.enc'), ...options.env });
  let clock = Date.UTC(2026, 10, 8);
  const now = () => clock;
  const store = await new EncryptedStore(config.storePath, key, now).init();
  const calls = [];
  const transport = async (target, request) => {
    const url = new URL(target);
    calls.push({ url, request });
    if (options.transport) return options.transport(url, request, calls);
    if (url.toString() === UPSTREAM.token) return ok(syntheticToken());
    if (url.pathname.endsWith('/user/profile/basic')) return ok({ user_id: 42, first_name: 'Fixture', last_name: 'Member' });
    return ok({ records: [], next_token: null });
  };
  const handler = createBridge({ config, store, transport, now, limits: options.limits, nutritionConfig: options.nutritionConfig, nutritionTransport: options.nutritionTransport });
  const server = createServer(handler);
  server.on('close', handler.close);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  const request = (path, init = {}) => fetch(base + path, { ...init, redirect: 'manual' });
  const post = (path, data) => request(path, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data) });
  const begin = async () => {
    const verifier = randomBytes(32).toString('base64url');
    const challenge = createHash('sha256').update(verifier).digest('base64url');
    const appState = randomBytes(32).toString('base64url');
    const response = await post('/v1/link', { challenge, appState });
    assert.equal(response.status, 200);
    const authorization = new URL((await response.json()).authorizationURL);
    return { verifier, challenge, appState, authorization, state: authorization.searchParams.get('state') };
  };
  const callback = attempt => request(`/oauth/callback?code=synthetic-code&state=${attempt.state}`);
  const pair = async attempt => {
    const response = await callback(attempt);
    assert.equal(response.status, 302);
    const callbackURL = new URL(response.headers.get('location'));
    assert.equal(callbackURL.protocol, 'whooplocal:'); assert.equal(callbackURL.host, 'oauth');
    assert.equal(callbackURL.searchParams.get('state'), attempt.appState);
    const code = callbackURL.searchParams.get('code'); assert.ok(code);
    return { code, callbackURL };
  };
  const session = async () => {
    const attempt = await begin(), { code } = await pair(attempt);
    const response = await post('/v1/session', { code, verifier: attempt.verifier });
    assert.equal(response.status, 200);
    const { token } = await response.json();
    assert.match(token, /^[A-Za-z0-9_-]{43}$/);
    return token;
  };
  const authenticated = (token, path = '/v1/account-data?days=30', method = 'GET') => request(path, { method, headers: { Authorization: `Bearer ${token}` } });
  t.after(async () => { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); await rm(dir, { recursive: true, force: true }); });
  return { config, store, now, advance: ms => { clock += ms; }, calls, request, post, begin, callback, pair, session, authenticated };
}

test('missing and malformed config stays unconfigured, health redacts values', async t => {
  for (const publicOrigin of ['http://localhost', 'https://x.test/path', 'https://user:pass@x.test', 'https://x.test/?q=1']) assert.equal(loadConfig({ ...env, PUBLIC_ORIGIN: publicOrigin }).configured, false);
  assert.equal(loadConfig({ ...env, TOKEN_ENCRYPTION_KEY: 'short' }).configured, false);
  const f = await fixture(t, { env: { WHOOP_CLIENT_SECRET: '' } });
  assert.deepEqual(await (await f.request('/health')).json(), { service: 'whoop-local-bridge', version: 1, configured: false });
  const response = await f.post('/v1/link', {}); assert.equal(response.status, 503);
  assert.match((await response.json()).message, /Configure WHOOP_CLIENT_ID/); assert.equal(f.calls.length, 0);
});

test('real local routes: OAuth state, proof-bound native pairing, import and encrypted disconnect', async t => {
  const f = await fixture(t), attempt = await f.begin();
  assert.equal(attempt.authorization.origin + attempt.authorization.pathname, UPSTREAM.authorization);
  assert.equal(attempt.authorization.searchParams.get('redirect_uri'), 'https://bridge.example.test/oauth/callback');
  assert.match(attempt.authorization.searchParams.get('scope'), /read:cycles.*offline/);
  assert.notEqual(attempt.state, attempt.appState);
  assert.equal(attempt.authorization.searchParams.has('client_secret'), false);
  const { code, callbackURL } = await f.pair(attempt);
  assert.deepEqual([...callbackURL.searchParams.keys()].sort(), ['code', 'state']);
  assert.equal((await f.callback(attempt)).status, 400);
  assert.equal((await f.post('/v1/session', { code, verifier: randomBytes(32).toString('base64url') })).status, 401);
  const paired = await f.post('/v1/session', { code, verifier: attempt.verifier });
  assert.equal(paired.status, 200); const { token } = await paired.json();
  assert.equal((await f.post('/v1/session', { code, verifier: attempt.verifier })).status, 401);
  const response = await f.authenticated(token); assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { profile: { user_id: 42, first_name: 'Fixture', last_name: 'Member' }, cycles: [], recoveries: [], sleeps: [], workouts: [] });
  assert.equal(response.headers.get('cache-control'), 'no-store');
  const plaintext = await readFile(f.config.storePath, 'utf8');
  for (const value of [token, 'synthetic-provider-access', 'synthetic-provider-refresh', 'synthetic-client-secret']) assert.equal(plaintext.includes(value), false);
  const reload = await new EncryptedStore(f.config.storePath, key, f.now).init();
  assert.equal(reload.get(hash(token)).provider.refresh_token, 'synthetic-provider-refresh');
  const exchangeBody = new URLSearchParams(f.calls[0].request.body);
  assert.equal(exchangeBody.get('grant_type'), 'authorization_code');
  assert.equal(exchangeBody.get('client_secret'), env.WHOOP_CLIENT_SECRET);
  assert.equal((await f.authenticated(token, '/v1/session', 'DELETE')).status, 200);
  assert.equal((await f.authenticated(token)).status, 401);
  const after = await new EncryptedStore(f.config.storePath, key, f.now).init(); assert.equal(after.get(hash(token)), undefined);
});

test('provider and native TTLs expire; callback nonce and duplicates are checked', async t => {
  const f = await fixture(t, { limits: { stateTTL: 100, pairingTTL: 100 } });
  const expired = await f.begin(); f.advance(101);
  assert.equal((await f.callback(expired)).status, 400); assert.equal(f.calls.length, 0);
  const attempt = await f.begin();
  assert.equal((await f.request(`/oauth/callback?code=x&state=${attempt.state}&state=${attempt.state}`)).status, 400);
  assert.equal((await f.request('/oauth/callback?code=x&state=wrong')).status, 400);
  const { code } = await f.pair(attempt); f.advance(101);
  assert.equal((await f.post('/v1/session', { code, verifier: attempt.verifier })).status, 401);
});

test('provider denial redirects with generic error and original app state, consumes state', async t => {
  const f = await fixture(t), attempt = await f.begin();
  const response = await f.request(`/oauth/callback?error=private-account-email&error_description=secret&state=${attempt.state}`);
  const location = new URL(response.headers.get('location'));
  assert.equal(location.searchParams.get('error'), 'authorization_failed');
  assert.equal(location.searchParams.get('state'), attempt.appState); assert.equal(location.toString().includes('secret'), false);
  assert.equal(f.calls.length, 0); assert.equal((await f.callback(attempt)).status, 400);
});

test('concurrent callback and pairing replays exchange and persist only once', async t => {
  const f = await fixture(t), attempt = await f.begin();
  const responses = await Promise.all([f.callback(attempt), f.callback(attempt)]);
  assert.deepEqual(responses.map(x => x.status).sort(), [302, 400]);
  const code = new URL(responses.find(x => x.status === 302).headers.get('location')).searchParams.get('code');
  const paired = await Promise.all([f.post('/v1/session', { code, verifier: attempt.verifier }), f.post('/v1/session', { code, verifier: attempt.verifier })]);
  assert.deepEqual(paired.map(x => x.status).sort(), [200, 401]); assert.equal(f.calls.length, 1);
});

test('pagination uses fixed host, ISO bounds and nextToken; unknown targets rejected', async t => {
  const f = await fixture(t, { transport: async (url, options) => {
    if (url.href === UPSTREAM.token) return ok(syntheticToken());
    if (url.pathname.endsWith('/basic')) return ok({ user_id: 42 });
    if (url.pathname.endsWith('/cycle') && !url.searchParams.has('nextToken')) return ok({ records: [{ id: 1 }], next_token: 'cursor/with?reserved&chars' });
    if (url.pathname.endsWith('/cycle')) { assert.equal(url.searchParams.get('nextToken'), 'cursor/with?reserved&chars'); return ok({ records: [{ id: 2 }], next_token: null }); }
    return ok({ records: [], next_token: null });
  } });
  const token = await f.session(), response = await f.authenticated(token);
  assert.equal(response.status, 200); assert.deepEqual((await response.json()).cycles, [{ id: 1 }, { id: 2 }]);
  for (const { url } of f.calls) assert.equal(url.origin, 'https://api.prod.whoop.com');
  const collection = f.calls.find(({ url }) => url.pathname.endsWith('/cycle')).url;
  assert.equal(collection.searchParams.get('limit'), '25'); assert.equal(collection.searchParams.get('end'), new Date(f.now()).toISOString());
  for (const query of ['days=0', 'days=91', 'days=1.5', 'days=30&days=1', 'url=https://evil.test']) assert.equal((await f.authenticated(token, '/v1/account-data?' + query)).status, 400);
});

test('repeated cursors and row/response bounds fail instead of truncating', async t => {
  const f = await fixture(t, { transport: async url => url.href === UPSTREAM.token ? ok(syntheticToken()) : url.pathname.endsWith('/basic') ? ok({}) : ok({ records: [{ id: 1 }], next_token: 'repeated' }) });
  const token = await f.session(), response = await f.authenticated(token);
  assert.equal(response.status, 503); assert.equal((await response.json()).error, 'data_limit');
});

test('expired access token refresh is single-flight during concurrent requests and rotation persists', async t => {
  let refreshes = 0;
  const f = await fixture(t, { transport: async (url, options) => {
    if (url.href === UPSTREAM.token) {
      if (new URLSearchParams(options.body).get('grant_type') === 'refresh_token') { refreshes++; return ok(syntheticToken('rotated-access', 'rotated-refresh')); }
      return ok(syntheticToken());
    }
    assert.equal(options.headers.Authorization, 'Bearer rotated-access');
    return url.pathname.endsWith('/basic') ? ok({ user_id: 42 }) : ok({ records: [], next_token: null });
  } });
  const token = await f.session(); f.advance(3600_000);
  const responses = await Promise.all([f.authenticated(token), f.authenticated(token), f.authenticated(token)]);
  assert.deepEqual(responses.map(x => x.status), [200, 200, 200]); assert.equal(refreshes, 1);
  const reloaded = await new EncryptedStore(f.config.storePath, key, f.now).init();
  assert.equal(reloaded.get(hash(token)).provider.refresh_token, 'rotated-refresh');
});

test('upstream 401 refreshes once, concurrent stale responses share rotated access token', async t => {
  let refreshes = 0;
  const f = await fixture(t, { transport: async (url, options) => {
    if (url.href === UPSTREAM.token) {
      if (new URLSearchParams(options.body).get('grant_type') === 'refresh_token') { refreshes++; return ok(syntheticToken('rotated-access', 'rotated-refresh')); }
      return ok(syntheticToken());
    }
    if (options.headers.Authorization === 'Bearer synthetic-provider-access') return new Response('private provider detail', { status: 401 });
    return url.pathname.endsWith('/basic') ? ok({}) : ok({ records: [], next_token: null });
  } });
  const token = await f.session(), responses = await Promise.all([f.authenticated(token), f.authenticated(token)]);
  assert.deepEqual(responses.map(x => x.status), [200, 200]); assert.equal(refreshes, 1);
});

test('disconnect racing refresh never resurrects encrypted provider session', async t => {
  let releaseRefresh, refreshStarted;
  const started = new Promise(resolve => { refreshStarted = resolve; });
  const gate = new Promise(resolve => { releaseRefresh = resolve; });
  const f = await fixture(t, { transport: async (url, options) => {
    if (url.href === UPSTREAM.token && new URLSearchParams(options.body).get('grant_type') === 'refresh_token') { refreshStarted(); await gate; return ok(syntheticToken('rotated', 'rotated')); }
    if (url.href === UPSTREAM.token) return ok(syntheticToken());
    return ok({ records: [], next_token: null });
  } });
  const token = await f.session(); f.advance(3600_000);
  const syncing = f.authenticated(token); await started;
  assert.equal((await f.authenticated(token, '/v1/session', 'DELETE')).status, 200); releaseRefresh();
  assert.equal((await syncing).status, 401);
  assert.equal(f.store.get(hash(token)), undefined);
  const reload = await new EncryptedStore(f.config.storePath, key, f.now).init(); assert.equal(reload.get(hash(token)), undefined);
});

test('invalid refresh grant removes saved session, provider errors and exceptions are redacted', async t => {
  const f = await fixture(t, { transport: async (url, options) => {
    if (url.href === UPSTREAM.token && new URLSearchParams(options.body).get('grant_type') === 'refresh_token') return Response.json({ error: 'invalid_grant', error_description: 'private secret' }, { status: 400 });
    return ok(syntheticToken());
  } });
  const token = await f.session(); f.advance(3600_000);
  const response = await f.authenticated(token); assert.equal(response.status, 401);
  assert.equal((await response.text()).includes('private secret'), false); assert.equal(f.store.get(hash(token)), undefined);
  const broken = await fixture(t, { transport: async () => { throw new Error('synthetic-client-secret /private/path private-account'); } });
  const attempt = await broken.begin(), callback = await broken.callback(attempt);
  assert.equal(callback.status, 302); assert.equal(callback.headers.get('location').includes('synthetic-client-secret'), false);
  assert.equal(new URL(callback.headers.get('location')).searchParams.get('error'), 'authorization_failed');
});

test('storage authenticates ciphertext, refuses permissive files and excludes multiple writers', async t => {
  const f = await fixture(t), token = await f.session();
  const envelope = JSON.parse(await readFile(f.config.storePath, 'utf8'));
  await assert.rejects(new EncryptedStore(f.config.storePath, Buffer.alloc(32, 8)).init());
  const ciphertext = Buffer.from(envelope.data, 'base64'); ciphertext[0] ^= 1; envelope.data = ciphertext.toString('base64');
  await writeFile(f.config.storePath, JSON.stringify(envelope));
  await assert.rejects(new EncryptedStore(f.config.storePath, key).init());
  await chmod(f.config.storePath, 0o644); await assert.rejects(new EncryptedStore(f.config.storePath, key).init(), /Unsafe token store/);
  const release = await lockStore(f.config.storePath);
  await assert.rejects(lockStore(f.config.storePath), { code: 'EEXIST' }); await release();
  assert.ok(f.store.get(hash(token)));
});

test('malformed input, JSON size, auth, bounded pending state and rate limiting are enforced', async t => {
  const f = await fixture(t, { limits: { maxPending: 1 } });
  assert.equal((await f.post('/v1/link', { challenge: 'short', appState: 'short' })).status, 400);
  assert.equal((await f.request('/v1/link', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{' })).status, 400);
  assert.equal((await f.post('/v1/link', { padding: 'a'.repeat(65536) })).status, 413);
  assert.equal((await f.request('/v1/account-data')).status, 401);
  const attempt = await f.begin();
  const response = await f.post('/v1/link', { challenge: attempt.challenge, appState: attempt.appState }); assert.equal(response.status, 429);
  assert.equal(response.headers.get('retry-after'), '60');
  for (let i = 0; i < 21; i++) await f.post('/v1/session', { code: 'invalid', verifier: 'invalid' });
  assert.equal((await f.post('/v1/session', {})).status, 429);
});

test('session expiry is enforced and refreshed tokens cannot extend bridge bearer life', async t => {
  const f = await fixture(t), token = await f.session(); f.advance(30 * 86400_000 + 1);
  assert.equal((await f.authenticated(token)).status, 401); assert.equal(f.calls.length, 1);
});

test('row, page, upstream response size and malformed envelopes are bounded with redacted errors', async t => {
  for (const scenario of [
    { name: 'row-limit', limits: { maxRows: 1 }, data: { records: [{ id: 1 }, { id: 2 }], next_token: null }, code: 'data_limit' },
    { name: 'page-limit', limits: { maxPages: 1 }, data: { records: [], next_token: 'next' }, code: 'data_limit' },
    { name: 'page-size', data: { records: Array.from({ length: 26 }, (_, id) => ({ id })), next_token: null }, code: 'upstream_unavailable' },
    { name: 'cursor-type', data: { records: [], next_token: { secret: 'private-provider-value' } }, code: 'upstream_unavailable' },
    { name: 'record-type', data: { records: [null], next_token: null }, code: 'upstream_unavailable' },
    { name: 'body-limit', data: { records: [{ value: 'x'.repeat(1024 * 1024) }], next_token: null }, code: 'upstream_unavailable' },
  ]) {
    await t.test(scenario.name, async child => {
      const f = await fixture(child, { limits: scenario.limits, transport: async url =>
        url.href === UPSTREAM.token ? ok(syntheticToken()) : url.pathname.endsWith('/basic') ? ok({}) : ok(scenario.data) });
      const token = await f.session(), response = await f.authenticated(token);
      assert.equal(response.status, 503); const body = await response.json(); assert.equal(body.error, scenario.code);
      assert.equal(JSON.stringify(body).includes('private-provider-value'), false);
    });
  }
});

test('upstream 429, 500, non-JSON and second 401 use generic errors', async t => {
  for (const scenario of [
    { name: 'rate-limit', response: () => new Response('private-provider-value', { status: 429 }), expected: 429 },
    { name: 'server-error', response: () => new Response('private-provider-value', { status: 500 }), expected: 503 },
    { name: 'non-json', response: () => new Response('private-provider-value'), expected: 503 },
    { name: 'invalid-json', response: () => new Response('{private-provider-value', { headers: { 'Content-Type': 'application/json' } }), expected: 503 },
    { name: 'second-unauthorized', response: () => new Response('private-provider-value', { status: 401 }), expected: 401 },
  ]) {
    await t.test(scenario.name, async child => {
      const f = await fixture(child, { transport: async url => url.href === UPSTREAM.token ? ok(syntheticToken()) : scenario.response() });
      const token = await f.session(), response = await f.authenticated(token);
      assert.equal(response.status, scenario.expected); assert.equal((await response.text()).includes('private-provider-value'), false);
      if (scenario.expected === 429) assert.equal(response.headers.get('retry-after'), '60');
      if (scenario.expected === 401) assert.equal(f.store.get(hash(token)), undefined);
    });
  }
});

test('whole import deadline aborts a stalled fake upstream without leaking its details', async t => {
  const f = await fixture(t, { limits: { deadlineMS: 25 }, transport: async (url, request) => {
    if (url.href === UPSTREAM.token) return ok(syntheticToken());
    return new Promise((resolve, reject) => {
      if (request.signal.aborted) reject(new Error('private-provider-value'));
      else request.signal.addEventListener('abort', () => reject(new Error('private-provider-value')), { once: true });
    });
  } });
  const token = await f.session(), response = await f.authenticated(token);
  assert.equal(response.status, 503); assert.equal((await response.text()).includes('private-provider-value'), false);
});

test('chunked JSON bodies enforce the 64 KiB limit without relying on Content-Length', async t => {
  const f = await fixture(t);
  const body = new ReadableStream({ start(controller) { controller.enqueue(Buffer.from(JSON.stringify({ padding: 'a'.repeat(65536) }))); controller.close(); } });
  const response = await f.request('/v1/link', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body, duplex: 'half' });
  assert.equal(response.status, 413);
  assert.equal((await response.json()).error, 'request_too_large');
  assert.equal(f.calls.length, 0);
});

test('historical end timestamp selects a bounded window for every upstream collection', async t => {
  const f = await fixture(t), token = await f.session();
  for (const [endValue, expected] of [['2022-06-15T12:34:56Z', '2022-06-15T12:34:56.000Z'], ['2022-06-15T12:34:56.123Z', '2022-06-15T12:34:56.123Z']]) {
    const before = f.calls.length;
    const response = await f.authenticated(token, '/v1/account-data?' + new URLSearchParams({ days: '14', end: endValue }));
    assert.equal(response.status, 200);
    assert.deepEqual(Object.keys(await response.json()).sort(), ['cycles', 'profile', 'recoveries', 'sleeps', 'workouts']);
    const collections = f.calls.slice(before).filter(({ url }) => !url.pathname.endsWith('/basic'));
    assert.equal(collections.length, 4);
    for (const { url } of collections) {
      assert.equal(url.searchParams.get('end'), expected);
      assert.equal(url.searchParams.get('start'), new Date(Date.parse(expected) - 14 * 86400_000).toISOString());
      assert.equal(url.origin, 'https://api.prod.whoop.com');
    }
  }
});

test('historical end rejects invalid, duplicate, non-UTC, pre-2000 and future values before upstream access', async t => {
  const f = await fixture(t), token = await f.session(), before = f.calls.length;
  for (const end of ['', 'garbage', '2022-02-30T00:00:00Z', '2022-06-15', '2022-06-15T24:00:00Z', '2022-06-15T12:34:56+00:00', '2022-06-15T12:34:56.1Z', '2022-06-15T12:34:56.123456Z', '1999-12-31T23:59:59Z', new Date(f.now() + 1).toISOString()]) {
    const response = await f.authenticated(token, '/v1/account-data?' + new URLSearchParams({ days: '30', end }));
    assert.equal(response.status, 400, end); assert.equal((await response.json()).error, 'invalid_request');
  }
  const duplicate = '/v1/account-data?end=2022-06-15T12:34:56Z&end=2022-06-15T12:34:56Z';
  assert.equal((await f.authenticated(token, duplicate)).status, 400);
  assert.equal(f.calls.length, before);
});

test('historical end accepts exact boundary timestamps; absent end retains current default window', async t => {
  const f = await fixture(t), token = await f.session();
  for (const end of ['2000-01-01T00:00:00Z', new Date(f.now()).toISOString()]) {
    assert.equal((await f.authenticated(token, '/v1/account-data?' + new URLSearchParams({ end }))).status, 200);
    const cycle = f.calls.at(-4).url;
    assert.equal(cycle.searchParams.get('end'), new Date(end).toISOString());
    assert.equal(cycle.searchParams.get('start'), new Date(Date.parse(end) - 30 * 86400_000).toISOString());
  }
  assert.equal((await f.authenticated(token, '/v1/account-data?days=14')).status, 200);
  assert.equal(f.calls.at(-4).url.searchParams.get('end'), new Date(f.now()).toISOString());
  assert.equal(f.calls.at(-4).url.searchParams.get('start'), new Date(f.now() - 14 * 86400_000).toISOString());
});

test('upstream literal unsafe integers and nonfinite numbers fail generically; fractional scores survive', async t => {
  for (const scenario of [
    { literal: '{"records":[{"id":9007199254740993}],"next_token":null}', status: 503 },
    { literal: '{"records":[{"id":111,"score":{"strain":1e999}}],"next_token":null}', status: 503 },
    { literal: '{"records":[{"id":111,"score":{"strain":5.2951527}}],"next_token":null}', status: 200 },
  ]) {
    const f = await fixture(t, { transport: async url => {
      if (url.href === UPSTREAM.token) return ok(syntheticToken());
      if (url.pathname.endsWith('/basic')) return ok({ user_id: 42 });
      if (url.pathname.endsWith('/cycle')) return new Response(scenario.literal, { headers: { 'Content-Type': 'application/json' } });
      return ok({ records: [], next_token: null });
    } });
    const token = await f.session(), response = await f.authenticated(token);
    assert.equal(response.status, scenario.status);
    const body = await response.json();
    if (scenario.status === 503) {
      assert.deepEqual(body, { error: 'upstream_unavailable', message: 'WHOOP data is unavailable. Try again later.' });
      assert.equal(JSON.stringify(body).includes('9007199254740993'), false);
    } else assert.equal(body.cycles[0].score.strain, 5.2951527);
  }
});


test('nutrition routes reuse authenticated sessions and never forward a key to the client', async t => {
  let calls = 0;
  const result = { items: [{ name: 'Egg', grams: 50, kcal: 72, protein: 6, carbs: 0.5, fat: 5, confidence: 0.8 }] };
  const f = await fixture(t, { nutritionConfig: { apiKey: 'synthetic-ai-private', apiURL: 'https://ai.example.test/v1/chat/completions' },
    nutritionTransport: async (_url, request) => { calls++; assert.equal(request.headers.Authorization, 'Bearer synthetic-ai-private'); return Response.json({ choices: [{ message: { content: JSON.stringify(result) } }] }); } });
  const denied = await f.post('/api/nutrition/parse-food', { text: 'one egg' }); assert.equal(denied.status, 401); assert.equal(calls, 0);
  const token = await f.session();
  const response = await f.request('/api/nutrition/parse-food', { method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ text: 'one egg' }) });
  assert.equal(response.status, 200); assert.deepEqual(await response.json(), result); assert.equal(calls, 1);
});
test('authenticated nutrition missing-key and oversized-image failures stay friendly and bounded', async t => {
  const f = await fixture(t, { nutritionConfig: {} }), token = await f.session();
  const post = (path, body) => f.request(path, { method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  const missing = await post('/api/nutrition/parse-food', { text: 'egg' }); assert.equal(missing.status, 503); assert.equal((await missing.json()).error, 'ai_not_configured');
  const large = await post('/api/nutrition/analyze-meal', { image: 'x'.repeat(1_500_001) }); assert.equal(large.status, 413);
});
