import { randomBytes, timingSafeEqual, createHash } from 'node:crypto';
import { UPSTREAM, SCOPES } from './config.mjs';
import { hash } from './store.mjs';
import { createNutritionAPI, NutritionRouteError } from '../lib/nutrition/routes.ts';

const opaque = () => randomBytes(32).toString('base64url');
const validOpaque = value => typeof value === 'string' && /^[A-Za-z0-9_-]{43}$/.test(value);
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const SESSION_TTL = 30 * 86400_000;
const JSON_LIMIT = 64 * 1024;
const RESPONSE_LIMIT = 8 * 1024 * 1024;
export class BridgeError extends Error {
  constructor(status, code, message) { super(message); this.status = status; this.code = code; }
}
const fail = (status, code, message) => { throw new BridgeError(status, code, message); };
const unauthorized = () => fail(401, 'unauthorized', 'Connect your WHOOP account again.');
const unavailable = () => fail(503, 'upstream_unavailable', 'WHOOP data is unavailable. Try again later.');

async function readJSON(req, limit = JSON_LIMIT) {
  if (!/^application\/json(?:\s*;|$)/i.test(req.headers['content-type'] ?? '')) fail(400, 'invalid_request', 'Send a JSON request.');
  if (Number(req.headers['content-length']) > limit) fail(413, 'request_too_large', 'The request exceeds its supported size.');
  const chunks = []; let bytes = 0;
  for await (const chunk of req) {
    bytes += chunk.length;
    if (bytes > limit) fail(413, 'request_too_large', 'The request exceeds its supported size.');
    chunks.push(chunk);
  }
  try { const result = JSON.parse(Buffer.concat(chunks)); if (object(result)) return result; } catch { /* generic */ }
  fail(400, 'invalid_request', 'Send a valid JSON object.');
}

// Only production fetch is selected by server.mjs. Dependency injection is for
// tests; no config/environment variable can change the upstream target hosts.
export function createBridge({ config, store, transport = globalThis.fetch, now = Date.now,
  limits = {}, nutritionConfig = { apiKey: process.env.AI_API_KEY, apiURL: process.env.AI_API_URL, model: process.env.AI_MODEL }, nutritionTransport = globalThis.fetch }) {
  const pending = new Map(), pairings = new Map(), refreshing = new Map(), rates = new Map();
  let exchanges = 0;
  const nutrition = createNutritionAPI(nutritionConfig, nutritionTransport);
  const nutritionRoutes = new Set(['/api/nutrition/analyze-meal', '/api/nutrition/parse-food', '/api/nutrition/estimate-exercise', '/api/nutrition/day-review']);
  const stateTTL = limits.stateTTL ?? 10 * 60_000;
  const pairingTTL = limits.pairingTTL ?? 2 * 60_000;
  const maxPending = limits.maxPending ?? 100;
  const maxPages = limits.maxPages ?? 10;
  const maxRows = limits.maxRows ?? 1000;
  const deadlineMS = limits.deadlineMS ?? 30_000;

  const purge = map => { for (const [key, value] of map) if (value.expiresAt <= now()) map.delete(key); };
  const cleanup = setInterval(() => { purge(pending); purge(pairings); purge(rates); }, 30_000);
  cleanup.unref();
  function rateLimit(key, max = 60) {
    purge(rates);
    let bucket = rates.get(key);
    if (!bucket) {
      if (rates.size >= 2048) fail(429, 'rate_limited', 'Too many requests. Try again later.');
      rates.set(key, bucket = { count: 0, expiresAt: now() + 60_000 });
    }
    if (++bucket.count > max) fail(429, 'rate_limited', 'Too many requests. Try again later.');
  }
  async function upstream(url, options = {}, signal) {
    let response;
    try {
      response = await transport(url, { ...options, redirect: 'error',
        signal: AbortSignal.any([AbortSignal.timeout(10_000), ...(signal ? [signal] : [])]) });
    } catch { unavailable(); }
    if (response.status === 429) {
      await response.body?.cancel().catch(() => {});
      fail(429, 'rate_limited', 'WHOOP rate limit reached. Try again later.');
    }
    if (!response.ok) { await response.body?.cancel().catch(() => {}); return { status: response.status }; }
    if (!/^application\/json(?:\s*;|$)/i.test(response.headers.get('content-type') ?? '')) unavailable();
    if (Number(response.headers.get('content-length')) > 1024 * 1024) { await response.body?.cancel().catch(() => {}); unavailable(); }
    let bytes = 0, chunks = [];
    try {
      for await (const chunk of response.body) {
        bytes += chunk.length;
        if (bytes > 1024 * 1024) unavailable();
        chunks.push(chunk);
      }
      const data = JSON.parse(Buffer.concat(chunks), (_key, value) => {
        // Refuse numbers that JavaScript cannot preserve when this response is
        // serialized for the Int64-native mapper. Keep finite fractional scores.
        if (typeof value === 'number' && (!Number.isFinite(value) ||
          (Number.isInteger(value) && !Number.isSafeInteger(value)))) unavailable();
        return value;
      });
      if (!object(data)) unavailable();
      return { status: response.status, data, bytes };
    } catch { unavailable(); }
  }
  function checkedToken(data, previousRefresh) {
    if (!object(data) || typeof data.access_token !== 'string' || !data.access_token.length || data.access_token.length > 8192 ||
      typeof (data.refresh_token ?? previousRefresh) !== 'string' || !(data.refresh_token ?? previousRefresh).length ||
      (data.refresh_token ?? previousRefresh).length > 8192 || typeof data.expires_in !== 'number' ||
      !Number.isFinite(data.expires_in) || data.expires_in < 1 || data.expires_in > 366 * 86400 ||
      typeof data.token_type !== 'string' || data.token_type.toLowerCase() !== 'bearer') unavailable();
    // The refresh token may be rotated, or omitted if unchanged.
    return { access_token: data.access_token, refresh_token: data.refresh_token ?? previousRefresh,
      expires_at: now() + data.expires_in * 1000 };
  }
  async function tokenRequest(parameters, signal) {
    return upstream(UPSTREAM.token, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded', Accept: 'application/json' },
      body: new URLSearchParams({ ...parameters, client_id: config.clientId, client_secret: config.clientSecret }).toString() }, signal);
  }
  async function access(id, rejectedToken, signal) {
    const current = store.get(id); if (!current) unauthorized();
    if ((!rejectedToken && current.provider.expires_at > now() + 60_000) ||
        (rejectedToken && current.provider.access_token !== rejectedToken && current.provider.expires_at > now())) return current.provider.access_token;
    if (refreshing.has(id)) return refreshing.get(id);
    const work = (async () => {
      const response = await tokenRequest({ grant_type: 'refresh_token', refresh_token: current.provider.refresh_token }, signal);
      if (response.status === 400 || response.status === 401) { await store.delete(id); unauthorized(); }
      if (!response.data) unavailable();
      const provider = checkedToken(response.data, current.provider.refresh_token);
      if (!await store.update(id, provider)) unauthorized();
      return provider.access_token;
    })();
    refreshing.set(id, work);
    try { return await work; } finally { refreshing.delete(id); }
  }
  async function api(id, path, signal) {
    let token = await access(id, undefined, signal);
    let result = await upstream(new URL(path, UPSTREAM.api).toString(), { headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' } }, signal);
    if (result.status === 401) {
      token = await access(id, token, signal);
      result = await upstream(new URL(path, UPSTREAM.api).toString(), { headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' } }, signal);
    }
    if (result.status === 401 || result.status === 403) { await store.delete(id); unauthorized(); }
    if (!result.data) unavailable();
    return result;
  }
  const json = (res, status, data) => {
    res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' }); res.end(JSON.stringify(data));
  };
  function nativeRedirect(res, appState, values) {
    const target = new URL('whooplocal://oauth');
    target.search = new URLSearchParams({ ...values, state: appState }).toString();
    res.writeHead(302, { Location: target.toString() }); res.end();
  }
  function authenticate(req) {
    const match = /^Bearer ([A-Za-z0-9_-]{43})$/.exec(req.headers.authorization ?? '');
    if (!match) unauthorized();
    const id = hash(match[1]);
    if (!store.get(id)) unauthorized();
    rateLimit(`session:${id}`, 20);
    return id;
  }
  async function handle(req, res) {
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('Pragma', 'no-cache');
    res.setHeader('Referrer-Policy', 'no-referrer');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Content-Security-Policy', "default-src 'none'; frame-ancestors 'none'");
    try {
      if ((req.url?.length ?? 0) > 8192) fail(400, 'invalid_request', 'Invalid request.');
      const url = new URL(req.url, 'http://bridge.invalid');
      if (req.method === 'GET' && url.pathname === '/health') return json(res, 200, { service: 'whoop-local-bridge', version: 1, configured: config.configured });
      if (!['/v1/link', '/v1/session', '/v1/account-data', '/oauth/callback'].includes(url.pathname) && !nutritionRoutes.has(url.pathname)) return json(res, 404, { error: 'not_found', message: 'Route not found.' });
      if (!config.configured) fail(503, 'not_configured', 'Configure WHOOP_CLIENT_ID, WHOOP_CLIENT_SECRET, PUBLIC_ORIGIN and TOKEN_ENCRYPTION_KEY on the bridge server.');
      const signal = AbortSignal.timeout(deadlineMS);
      if (nutritionRoutes.has(url.pathname)) {
        if (req.method !== 'POST') return json(res, 405, { error: 'method_not_allowed', message: 'Use POST for nutrition analysis.' });
        const id = authenticate(req);
        rateLimit(`nutrition:${id}`, 6);
        const body = await readJSON(req, url.pathname === '/api/nutrition/analyze-meal' ? 1_500_000 : JSON_LIMIT);
        return json(res, 200, await nutrition(url.pathname, body, signal));
      }
      if (req.method === 'POST' && url.pathname === '/v1/link') {
        rateLimit(`link:${req.socket.remoteAddress}`, 10);
        const { challenge, appState } = await readJSON(req);
        if (!validOpaque(challenge) || typeof appState !== 'string' || !/^[A-Za-z0-9_-]{22,128}$/.test(appState)) fail(400, 'invalid_request', 'Invalid link challenge or state.');
        purge(pending); purge(pairings);
        if (pending.size + pairings.size + exchanges >= maxPending) fail(429, 'rate_limited', 'Too many pending connections. Try again later.');
        const state = opaque();
        pending.set(hash(state), { challenge, appState, expiresAt: now() + stateTTL });
        const target = new URL(UPSTREAM.authorization);
        target.search = new URLSearchParams({ client_id: config.clientId, redirect_uri: config.redirectURI, response_type: 'code', scope: SCOPES, state }).toString();
        return json(res, 200, { authorizationURL: target.toString() });
      }
      if (req.method === 'GET' && url.pathname === '/oauth/callback') {
        rateLimit(`callback:${req.socket.remoteAddress}`, 30);
        purge(pending); purge(pairings);
        const state = url.searchParams.get('state');
        const entry = validOpaque(state) && url.searchParams.getAll('state').length === 1 && pending.get(hash(state));
        if (!entry) fail(400, 'invalid_callback', 'Authorization expired or could not be verified. Start again.');
        pending.delete(hash(state)); // Claim synchronously before any exchange or redirect; replay cannot exchange twice.
        const code = url.searchParams.get('code');
        if (url.searchParams.has('error') || url.searchParams.getAll('code').length !== 1 || typeof code !== 'string' || code.length < 1 || code.length > 2048) return nativeRedirect(res, entry.appState, { error: 'authorization_failed' });
        exchanges++;
        try {
          const response = await tokenRequest({ grant_type: 'authorization_code', code, redirect_uri: config.redirectURI }, signal);
          if (!response.data) unavailable();
          const provider = checkedToken(response.data);
          purge(pairings);
          if (pairings.size >= maxPending) unavailable();
          const pairingCode = opaque();
          pairings.set(hash(pairingCode), { ...entry, provider, expiresAt: now() + pairingTTL });
          return nativeRedirect(res, entry.appState, { code: pairingCode });
        } catch { return nativeRedirect(res, entry.appState, { error: 'authorization_failed' }); }
        finally { exchanges--; }
      }
      if (req.method === 'POST' && url.pathname === '/v1/session') {
        rateLimit(`pair:${req.socket.remoteAddress}`, 20);
        const { code, verifier } = await readJSON(req);
        purge(pairings);
        const entry = validOpaque(code) && pairings.get(hash(code));
        if (!entry || typeof verifier !== 'string' || !/^[A-Za-z0-9._~-]{43,128}$/.test(verifier)) unauthorized();
        const proof = createHash('sha256').update(verifier).digest('base64url');
        if (!timingSafeEqual(Buffer.from(proof), Buffer.from(entry.challenge))) unauthorized();
        pairings.delete(hash(code)); // Single-use even if the durable write fails.
        const token = opaque();
        await store.create(hash(token), { expiresAt: now() + SESSION_TTL, provider: entry.provider });
        return json(res, 200, { token });
      }
      if (req.method === 'GET' && url.pathname === '/v1/account-data') {
        const id = authenticate(req);
        const daysValue = url.searchParams.get('days') ?? '30';
        if (url.searchParams.getAll('days').length > 1 || !/^\d{1,3}$/.test(daysValue) || Number(daysValue) < 1 || Number(daysValue) > 90 || [...url.searchParams.keys()].some(key => key !== 'days' && key !== 'end')) fail(400, 'invalid_request', 'days must be an integer from 1 to 90.');
        const endValue = url.searchParams.get('end');
        let endMillis = now();
        if (endValue !== null) {
          // Accept UTC Z only, with seconds and optional exactly-three-digit
          // milliseconds. Round-trip validation rejects Date's normalization of
          // invalid calendar dates (e.g. February 30) and leap-second garbage.
          if (url.searchParams.getAll('end').length !== 1 || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/.test(endValue)) fail(400, 'invalid_request', 'end must be a UTC timestamp from year 2000 through the present.');
          const normalized = endValue.includes('.') ? endValue : endValue.replace('Z', '.000Z');
          const parsed = Date.parse(normalized);
          if (!Number.isFinite(parsed) || parsed < Date.UTC(2000, 0, 1) || parsed > endMillis || new Date(parsed).toISOString() !== normalized) fail(400, 'invalid_request', 'end must be a UTC timestamp from year 2000 through the present.');
          endMillis = parsed;
        }
        const end = new Date(endMillis).toISOString(), start = new Date(endMillis - Number(daysValue) * 86400_000).toISOString();
        let totalBytes = 0, totalRows = 0;
        const profile = await api(id, 'user/profile/basic', signal); totalBytes += profile.bytes;
        const output = { profile: profile.data };
        for (const [key, path] of [['cycles', 'cycle'], ['recoveries', 'recovery'], ['sleeps', 'activity/sleep'], ['workouts', 'activity/workout']]) {
          const records = [], seen = new Set(); let cursor;
          for (let page = 0; page < maxPages; page++) {
            const query = new URLSearchParams({ start, end, limit: '25' });
            if (cursor) query.set('nextToken', cursor);
            const response = await api(id, `${path}?${query}`, signal);
            totalBytes += response.bytes;
            const data = response.data;
            if (!Array.isArray(data.records) || data.records.length > 25 || data.records.some(record => !object(record)) ||
                (data.next_token != null && typeof data.next_token !== 'string')) unavailable();
            totalRows += data.records.length;
            if (totalRows > maxRows || totalBytes > RESPONSE_LIMIT) fail(503, 'data_limit', 'The account response exceeds the import limit. Request fewer days.');
            records.push(...data.records);
            cursor = data.next_token;
            if (!cursor) break;
            if (cursor.length > 4096 || seen.has(cursor) || page === maxPages - 1) fail(503, 'data_limit', 'The account response exceeds the import limit. Request fewer days.');
            seen.add(cursor);
          }
          output[key] = records;
        }
        if (signal.aborted) unavailable();
        return json(res, 200, output);
      }
      if (req.method === 'DELETE' && url.pathname === '/v1/session') {
        const id = authenticate(req);
        await store.delete(id);
        return json(res, 200, { disconnected: true });
      }
      json(res, 405, { error: 'method_not_allowed', message: 'Method not allowed.' });
    } catch (error) {
      // Never expose exception text, URLs, query strings, provider bodies, tokens,
      // keys, file paths or request data. No request/access log is emitted.
      if (res.headersSent) return res.end();
      const known = error instanceof BridgeError || error instanceof NutritionRouteError;
      if (known && error.status === 429) res.setHeader('Retry-After', '60');
      json(res, known ? error.status : 503, { error: known ? error.code : 'service_unavailable',
        message: known ? error.message : 'The bridge could not complete the request. Try again later.' });
    }
  }
  handle.close = () => { clearInterval(cleanup); pending.clear(); pairings.clear(); rates.clear(); };
  return handle;
}
