# WHOOP account sync

The Account screen links through a personal HTTPS bridge using the provider’s official browser authorization page. It never collects a WHOOP password. The app and bridge are source implementations; no account sign-in, account request, live OAuth exchange, deployment, or iOS runtime build was performed here. A configured server, registered WHOOP OAuth application, and trusted HTTPS endpoint are required for real use. See [bridge setup and evidence](AccountAPI/README.md).

The official public specification could not be retrieved because the existing network policy denied the developer documentation host. The pinned, retrievable third-party public SDK corroborates the v2 route and record shape; it does not establish current official-service compatibility. [SOURCES.json](AccountAPI/SOURCES.json) retains URLs, SHA-256 hashes, pinned revisions, and retrieval limitations. The native mapping tests use fabricated values with those independently sourced keys, never live account responses. Confirm the current official specification before production integration.

## App flow and storage

1. Enter the HTTPS bridge origin. Paths, credentials, queries, fragments, and nonstandard ports are rejected. The origin is normalized and saved in UserDefaults; no account secret is stored there. Only the user-triggered Connect action makes a health check and begins linking.
2. The app generates a random ephemeral 256-bit verifier and app state. It sends `base64url(SHA256(verifier))` and app state to `POST /v1/link`. The verifier remains in memory for that attempt.
3. The returned address must be exactly the HTTPS origin `api.prod.whoop.com` with path `/oauth/oauth2/auth` and no user information. `ASWebAuthenticationSession` presents the official authorization page, using an existing window in an active `UIWindowScene`. The browser session requests ephemeral storage.
4. The app requires `whooplocal://oauth`, a single state parameter, and a single nonempty pairing code. State uses a fixed-length, full-byte comparison. Only code/state/error parameters are accepted. The callback contains a short-lived pairing code, never the backend bearer or WHOOP tokens.
5. `POST /v1/session` redeems the one-use code with the verifier. The opaque bridge bearer goes into a nonsynchronizing Keychain item with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, so it is excluded from device backups. Its Keychain account key is a hash of the normalized origin. The in-memory bearer is also bound to that exact origin; edited origins cannot receive it. Editing the URL is disabled while linked.
6. Choose 14 or 30 days and an “Ending on” date to sync recent or historical records. The calendar and its selected day use UTC, with supported ending dates from January 1, 2000 through today. Sync fetches `GET /v1/account-data?days=14|30&end=<UTC timestamp>`, maps the records, then calls the store’s atomic account merge. A failed local save retains the mapped import for Retry Saving. Cancellation leaves saved data unchanged.
7. Disconnect calls `DELETE /v1/session`, then deletes the Keychain item and in-memory session. If the server cannot confirm deletion, the app retains the connection for retry and reports the failure. The bridge deletes its session and saved provider credentials; provider grant revocation is not implemented. Previously imported data remains available for local deletion in Your Data Files. If the bridge is unavailable, Forget connection removes this iPhone’s Keychain session and attempts remote cleanup independently; its confirmation explains that the remote grant/session may remain.

Bridge requests use an ephemeral URLSession with no cookie store or URL cache. HTTP redirects are refused. Timeouts and a 16 MiB response acceptance bound apply; the server enforces stricter streaming and page/row bounds. Bearers, callback URLs, upstream bodies, and headers are never rendered or logged. A 401 clears only the matching current bearer/origin and its Keychain item; a late cleanup response cannot clear a newer session; the user reconnects. A missing server configuration, 429, cancellation, invalid callback, Keychain failure, and network failure have distinct redacted UI states. Authentication callbacks are scoped by attempt identity and resolve their continuation once, including cancellation and late callbacks. Cancellation or Keychain failure after pairing redemption triggers independent best-effort remote cleanup.

The app must register the `whooplocal` URL scheme and include these source files in its iOS target. The application privacy manifest must declare the UserDefaults API use for remembering this user-entered bridge origin. No WHOOP client secret or provider access/refresh token belongs in the application bundle, app configuration, or backup.

`AccountModel.fetch(days:ending:)` accepts an optional selected calendar day. With a selected day it sends an exclusive `end` equal to the earlier of now and the following UTC midnight, formatted as ISO 8601 UTC with a `Z` suffix and whole-second precision. This includes a past ending day in full and today only so far; future or unsupported ending dates are rejected before making the account-data request. The backend defines the range start as `end - days × 24 hours`. Omitting `ending` preserves the original behavior of omitting the query parameter so the bridge uses its current time. Neither date choice requests an unbounded history. Public record pagination and response limits still apply.

## Mapping and provenance

`WhoopAccountMapper.map(Data)` returns `WhoopAccountImport(days:activities:displayName:userID:)`. It requires profile identity and checks every record’s `user_id`, valid positive numeric cycle IDs, UUID sleep/workout IDs, known score states, consistent score presence, unique identities, finite units, dates, supported durations, and measurement bounds. Invalid payloads fail before anything is merged. Extra public fields that this app does not display are ignored. Scored in-bed milliseconds must fit the sleep start/end interval, with at most one second of timestamp rounding tolerance. The validated profile ID is saved as optional local account-owner metadata and included in backups; importing a different known account requires exporting/clearing the current dataset first. This metadata is not an authentication credential. Existing raw HR samples and steps survive an account-day refresh because this API import supplies neither.

| Archive field | Account source and policy |
| --- | --- |
| Daily date | UTC calendar date of `cycle.start`, regardless of `timezone_offset` or device timezone |
| Strain | Scored cycle `score.strain`, preserved as supplied |
| Energy | Scored cycle `score.kilojoule / 4.184` kcal; this is cycle energy, not Apple Health active energy |
| Recovery, resting HR, HRV | Scored recovery `recovery_score`, `resting_heart_rate`, `hrv_rmssd_milli`; recovery joins by exact `cycle_id` |
| Sleep Performance | Scored main sleep `sleep_performance_percentage`; if recovery exists, both its `cycle_id` and `sleep_id` must match |
| Sleep duration | Sum of supplied light, slow-wave and REM stage milliseconds, converted to whole minutes; no awake/no-data time included |
| Sleep need | Supplied baseline + sleep debt + recent strain + signed recent nap adjustment, converted to whole minutes; the SDK example’s nap credit is negative |
| Respiratory rate | That matched scored sleep’s `respiratory_rate` |
| Activities | Supplied workout UUID, start/end, sport ID label and scored `strain`; UUID is stable across repeated imports, and Strain is marked as supplied rather than estimated |
| Display name | Trimmed first and last name; email is not retained |
| Steps / raw HR | No steps or raw HR samples are supplied by this import; zero/empty are the archive’s missing-value representation, not invented measurements |

Percentage fields are displayed at the archive’s whole-number precision; no Recovery or Sleep Performance formula is applied. Sleep and workout durations are truncated to whole minutes; positive subminute workouts occupy the archive’s minimum one-minute duration. HRV retains WHOOP’s supplied RMSSD value. No 1 Hz heart-rate series is reconstructed from summary heart rates.

Each cycle becomes one archive day. Multiple cycles starting on the same UTC day are rejected atomically, including distinct valid cycle IDs, because the current archive can hold only one set of scores per date. This explicit UTC mapping is not claimed to match the official WHOOP application’s cycle/day boundaries. Missing boundary-cycle/sleep records are not matched by temporal proximity. A main sleep can join its explicit `cycle_id` if no recovery record exists; naps never replace main sleep. A recovery referencing a nap or a sleep belonging to a different cycle is rejected. Pending/unscorable records have unavailable scores. Data from this adapter has `.imported` provenance; the Account screen identifies the scores as account supplied and explains missing data and UTC grouping.

## Validation performed

The isolated `WhoopAccountTests` suite passed 14 tests using Swift 6.2.1 on Linux. It covers account scores/units, signed nap adjustment, stable activity identity, pending/unscorable states, exact joins, missing referenced sleep, main sleep without recovery, cross-account identities, duplicates, conflicting UTC cycles, timestamp offsets, supported bounds, malformed/nonfinite JSON, oversized input, and inconsistent sleep components. The two new iOS files passed Swift frontend syntax parsing. The Linux executor has no iOS SDK, so this is not an iOS typecheck, device run, browser OAuth validation, or evidence of live WHOOP connectivity.

Reproduce the Core checks from the repository root:

```sh
swift test --cache-path /tmp/whoop-account-cache --scratch-path /tmp/whoop-account-build --jobs 4 --filter WhoopAccountTests
swiftc -frontend -parse App/AccountModel.swift App/Views/AccountView.swift
```
