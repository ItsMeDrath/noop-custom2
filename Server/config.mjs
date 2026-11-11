import { resolve } from 'node:path';

export const UPSTREAM = Object.freeze({
  authorization: 'https://api.prod.whoop.com/oauth/oauth2/auth',
  token: 'https://api.prod.whoop.com/oauth/oauth2/token',
  api: 'https://api.prod.whoop.com/developer/v2/',
});
export const SCOPES = 'read:profile read:cycles read:recovery read:sleep read:workout offline';

export function loadConfig(env = process.env) {
  let origin, key;
  try {
    const u = new URL(env.PUBLIC_ORIGIN);
    if (u.protocol === 'https:' && !u.username && !u.password && u.pathname === '/' && !u.search && !u.hash) origin = u.origin;
  } catch { /* Missing or invalid configuration is reported by /health and 503. */ }
  if (/^[A-Za-z0-9+/]{43}=$/.test(env.TOKEN_ENCRYPTION_KEY ?? '')) {
    const candidate = Buffer.from(env.TOKEN_ENCRYPTION_KEY, 'base64');
    if (candidate.length === 32) key = candidate;
  }
  const clientId = env.WHOOP_CLIENT_ID?.trim();
  const clientSecret = env.WHOOP_CLIENT_SECRET?.trim();
  const configured = Boolean(origin && key && clientId && clientSecret);
  const port = Number(env.PORT ?? 8787);
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Invalid PORT');
  return Object.freeze({ configured, origin, key, clientId, clientSecret,
    redirectURI: origin ? `${origin}/oauth/callback` : undefined,
    storePath: resolve(env.TOKEN_STORE_PATH ?? './data/sessions.enc'),
    host: env.HOST ?? '127.0.0.1', port });
}
