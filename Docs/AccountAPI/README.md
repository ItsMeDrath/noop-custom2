# Personal account bridge

This Node built-in service implements the native account contract in `ACCOUNT-CONTRACT.md`. It imports WHOOP account-supplied profile, cycle, recovery, sleep and workout records. It does not supply private app features, device streaming or a reconstructed heart-rate series. No live credentials, login, deployment or WHOOP account HTTP requests were used to build or test it.

## Evidence and verification boundary

The existing network policy denied access to the official public specification at `https://developer.whoop.com/api/openapi.json` with CONNECT 403. A guessed official GitHub mirror returned 404. Neither is treated as retrieved official evidence. No network settings were changed and no alternate proxy or connection bypass was used.

The routes, scopes, OAuth client authentication, pagination spelling and v2 field shapes below were corroborated against the **third-party** `hedgertronic/whoop` SDK, pinned to `af099c974341284555dd738e23d5bcc80d2dbf67`. The files were read, never imported or executed. [SOURCES.json](SOURCES.json) records source URLs, byte counts, SHA-256 hashes, pinned-content hash checks and limitations; [evidence/](evidence/) retains relevant line-numbered excerpts. The SDK explicitly marks its fixture values synthetic. This evidence is not official specification verification or live WHOOP validation. Before production use, confirm the contract, scopes and registered redirect URI against the official WHOOP developer documentation and perform an authorized integration test.

## Local setup

Requires Node >=24.5 (tested with 24.22.1). The shared Nutrition routes add zod; run `npm ci` at the complete project root first. Then, from `Server/`:

```sh
cp .env.example .env
chmod 600 .env
# Edit .env locally; all credentials and key material stay on this server.
npm test
npm start
```

`npm start` uses Node's inherited proxy support (`--use-env-proxy`), normal CA trust and `.env` loading. Do not commit `.env`, storage, keys or credentials. `Server/.gitignore` excludes `.env` and the default `data/` directory. Do not put client secrets or token encryption keys into Xcode, app configuration or the IPA. For a custom storage path, keep it outside source control and use a private directory (0700) and file (0600).

Set `WHOOP_CLIENT_ID`, `WHOOP_CLIENT_SECRET`, `TOKEN_ENCRYPTION_KEY` (32 random bytes encoded as standard Base64), and `PUBLIC_ORIGIN` (your public HTTPS origin). Example: `PUBLIC_ORIGIN=https://bridge.example.com` means the **exact WHOOP dashboard redirect URI must be `https://bridge.example.com/oauth/callback`**. The server can validate an explicit port, but the bundled native app accepts only standard HTTPS port 443; use that port for this project. Origin must have no path, query, fragment or user information. The app's custom callback `whooplocal://oauth` is a separate bridge-to-native step; do not register it as the provider redirect URI.

The default listener is HTTP `127.0.0.1:8787`. Supply HTTPS termination with a trusted certificate at the configured public origin, forward the same paths, and disable proxy access/query/body logging for OAuth and account routes. Configure the iPhone with that HTTPS origin. No server was published and no reusable environment configuration was altered here. Missing credentials or key produce `configured:false` and actionable 503 responses; no fixture account is substituted.

## OAuth and provider contract

| Purpose | URL / behavior corroborated by SDK |
| --- | --- |
| Authorization | `https://api.prod.whoop.com/oauth/oauth2/auth`; `response_type=code`, `client_id`, exact `redirect_uri`, space-separated `scope`, random provider `state` |
| Code exchange / refresh | `POST https://api.prod.whoop.com/oauth/oauth2/token`; URL-encoded `client_secret_post`; `grant_type=authorization_code` + `code` + exact `redirect_uri`, or `grant_type=refresh_token` + `refresh_token` |
| Requested scopes | `read:profile read:cycles read:recovery read:sleep read:workout offline` |
| Basic profile | `GET https://api.prod.whoop.com/developer/v2/user/profile/basic` |
| Collections | Same base + `cycle`, `recovery`, `activity/sleep`, `activity/workout` |
| Pagination | `start`, `end` ISO UTC timestamps, `limit=25`; response `{records:[...],next_token:...}`; next request uses `nextToken` |

OAuth token responses must contain bearer `token_type`, nonempty `access_token`, `refresh_token` and numeric `expires_in`. Refresh may omit `refresh_token` when unchanged; rotated values are atomically persisted before use. Refresh is single-flight per session, including concurrent imports and one retry after upstream 401. Invalid grants clear the saved bridge session. 429, network, response and provider errors return generic redacted messages without provider bodies. Redirects from provider HTTP requests are rejected.

No provider revocation request is implemented: only third-party revocation evidence was reachable. Disconnect deletes this bridge's durable saved session and provider tokens; it does not delete the WHOOP account or revoke the developer application's provider grant. Users can also remove the grant through WHOOP account settings.

## Native routes

| Route | Request | Response |
| --- | --- | --- |
| `GET /health` | — | `{service:"whoop-local-bridge",version:1,configured:Bool}` |
| `POST /v1/link` | JSON `{challenge,appState}` | `{authorizationURL}` pointing only to the fixed provider authorization host |
| `GET /oauth/callback` | Provider `code` and exact pending provider `state` | Fixed `whooplocal://oauth?code=...&state=...` or generic `error=authorization_failed` |
| `POST /v1/session` | JSON `{code,verifier}` | `{token}`: opaque bridge bearer, never provider access/refresh tokens |
| `GET /v1/account-data?days=30` | `Authorization: Bearer <bridge token>` | `{profile,cycles,recoveries,sleeps,workouts}` |
| `DELETE /v1/session` | Same bearer; explicit disconnect | `{disconnected:true}` |

`GET /v1/account-data` also accepts optional `end` for historical windows, for example `?days=14&end=2022-06-15T12%3A34%3A56Z`. The end timestamp must be UTC `YYYY-MM-DDTHH:mm:ssZ` or `YYYY-MM-DDTHH:mm:ss.SSSZ` (exactly three fractional digits), a real calendar time, and between `2000-01-01T00:00:00.000Z` and the server's present time, inclusive. Offsets, duplicate values, future dates, date-only input and dates JavaScript would silently normalize are rejected with 400 before upstream access. Accepted input is normalized to UTC milliseconds for the provider query. Every collection receives `end=selected timestamp` and `start=end−days×24 hours`; absent `end` retains the current-time default, with `days=30` by default (or an explicitly requested 14-day window). The response JSON and existing pagination/size/rate/time bounds remain the same. The provider end is exclusive according to the SDK evidence; a date picker intending to include an entire historical UTC day should select the next UTC midnight, capped at the current time for today. These are UTC windows, not a claim to reproduce official WHOOP day boundaries.

The app generates an ephemeral verifier (43–128 RFC 7636 unreserved characters), challenge `base64url(SHA256(verifier))` (43 characters), and random URL-safe `appState` (22–128 characters). Provider state is a separate random 256-bit value. The provider callback verifies and consumes provider state before making a token request. The native callback carries only a random single-use two-minute pairing code, bound to the verifier challenge and appState. Only possession of the verifier can redeem it. Pairing codes are stored by hash, consumed synchronously before persistence, and never reused. A failed verifier does not consume a valid code. Unknown/expired provider state does not redirect. No arbitrary redirect or upstream URL can be supplied by a client.

The bearer lasts 30 days and is stored only as a hash on the server. Provider access/refresh material is AES-256-GCM encrypted with an independent server-only key. Pending provider tokens are held only in bounded process memory until pairing. Expiry is checked on use and a 30-second cleanup sweep clears expired memory; restart drops pending attempts. They never appear in callback URLs, route responses, logs or files as plaintext. The iOS adapter stores the bridge bearer in Keychain.

## Bounds and operation

JSON request limit 64 KiB; headers 16 KiB; pending attempts/codes/exchanges 100 total; provider state TTL 10 minutes; pairing TTL 2 minutes; persisted sessions 10; days 1–90; 10 pages per collection; 25 rows per page; 1,000 total rows; 1 MiB per upstream response and 8 MiB aggregate response; 10-second upstream request timeout and 30-second import deadline. The service returns a limit error rather than silently returning truncated collections. Incoming requests have header/body timeouts. Rate buckets are bounded to 2,048 with one-minute windows, anonymous link 10/minute/IP, pairing 20/minute/IP, callback 30/minute/IP, account operations 20/minute/session. It uses the socket peer address, not untrusted forwarded headers. Configure additional reverse-proxy limits if needed; behind one proxy the anonymous limits are shared.

Upstream JSON parsing rejects nonfinite numbers and numeric integers outside JavaScript's safe integer range (−9,007,199,254,740,991 through 9,007,199,254,740,991), returning generic 503. This deliberately bounds unsupported future large WHOOP IDs instead of silently rounding them before the native Int64 mapper receives them. Finite fractional scores remain numeric and are preserved; declared integer IDs are never converted to strings.

Storage mutations are serialized, encrypted and written with a private temporary file, fsync and atomic rename. Startup refuses an unreadable, corrupt, insecure or wrongly keyed store. A process lock prevents two service instances from sharing a file. After a crash, verify no instance remains and remove only the stale `<TOKEN_STORE_PATH>.lock` file before restarting. Keep the encryption key and backups private; key rotation and distributed/multi-process storage are not implemented. Expired sessions are inaccessible and are physically removed on the next storage mutation. Secure deletion of historical encrypted backups is an operator responsibility.

All HTTP responses are non-cacheable and errors use `{error,message}`. Authentication failures are 401, invalid input 400 (oversized JSON 413), rate limits 429, unavailable configuration/upstream/storage 503. No request logger is installed. The included tests run actual local HTTP route handlers with synthetic records and an injected fake upstream transport; they do not contact WHOOP.
