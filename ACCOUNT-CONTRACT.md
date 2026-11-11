# Account-sync expansion contract

User requests completing the WHOOP-branded iPhone reconstruction, with no chat questions. Build source and tests; no real account login, private API call, deployment, configuration publication or NOOP repository change. No WHOOP password collection. Real OAuth must use the official authorization page. Live configuration/credentials are unavailable and must be stated as such.

Backend (`Server/`, Node built-ins) and native iOS adapter are independent. Verify public WHOOP OAuth/v2 routes and fields against retrievable source before relying on them. Retain URLs/hashes/scope. Existing egress policy stays unchanged; do not work around blocked hosts or ask to publish changes. Test real local routes with fake upstream responses; never pretend those tests are live WHOOP validation.

Internal backend ↔ iOS contract:

- GET `/health`: `{service:"whoop-local-bridge",version:1,configured:Bool}`; no secrets.
- POST `/v1/link`, JSON `{challenge:String, appState:String}`: challenge=base64url(SHA256(iOS verifier)); appState=random per attempt. Return `{authorizationURL:String}` on success. Server callback uses configured public HTTPS origin + `/oauth/callback`; after provider success, redirect ONLY to `whooplocal://oauth?code=ONE_TIME_PAIR_CODE&state=APP_STATE` (or generic error+same state). This is server-to-native linking, distinct from provider OAuth state.
- POST `/v1/session`, JSON `{code:String,verifier:String}`: validate single-use, short-lived pairing code/challenge. Return `{token:String}` (opaque backend bearer, never WHOOP refresh token).
- GET `/v1/account-data?days=30` with `Authorization: Bearer ...`: return `{profile:Object,cycles:[Object],recoveries:[Object],sleeps:[Object],workouts:[Object]}` containing documented public v2 records. Cap rows/pages/response/time. Backend owns upstream pagination/refresh/expiry; no client-supplied target URLs.
- DELETE `/v1/session` with same bearer: delete this bridge's saved session/provider secrets; no WHOOP account deletion. Provider revoke only if documented and authorized by explicit disconnect action.
- Errors: JSON `{error:String,message:String}` with appropriate 400/401/429/503, generic/redacted messages. Max incoming JSON64KiB. Config missing must return actionable503, never simulate configured.

Backend storage: encrypted refresh/session token material with server-only key; atomic private storage, backend bearer hashes, no token logs. Fixed official upstream hosts in production; mock transport injection only in tests. Pending state/challenges/codes single-use and bounded TTL/memory; callback nonce/correlation verified; no open redirects, client secrets in app, or bearer token in callback URL. Backend bearer is stored in iOS Keychain, excluded from backups. Binding callback code to iOS verifier prevents custom-scheme interception reuse.

Core mapping (new `Core/WhoopAccountData.swift`): `WhoopAccountMapper.map(_ data:Data) throws -> WhoopAccountImport` with `days:[DailySnapshot]`, `activities:[ActivityRecord]`, `displayName:String?`. Public v2 record matching by cycle_id and sleep_id. UTC-cycle mapping choice must be explicit and not called identical to official day boundaries. Preserve WHOOP-supplied scores; do not recompute Recovery/sleep or infer 1Hz HR. Validate bounds, states, IDs, finite units and conflicting cycles; source .imported. Source labels must say account-supplied and missing data honestly.

Native adapter/new view (`App/AccountModel.swift`, `App/Views/AccountView.swift`): @MainActor ObservableObject AccountModel; user configures HTTPS bridge URL in UI, official ASWebAuthenticationSession OAuth, session bearer in Keychain, verifier/state ephemeral. Parent will supply AccountModel environment object and route. `AccountView` uses AppStore.mergeAccount(_ result:WhoopAccountImport) throws (parent implements) to merge scores/activities atomically. No passwords. Saved server URL uses UserDefaults; no session secrets in published state or backup. Clear auth on401; explicit disconnect; cancellation/error/no-config states. Actual sign-in is not run here.

Parent owns AppStore/Root/WHOOPApp/Info/project/packaging. Agent ownerships: backendAgent Server/ + Docs/AccountAPI/; nativeAgent new AccountModel/AccountView/Core mapping/newtests + Docs/ACCOUNT-SYNC.md. Shared fields/types existing Models.swift unchanged unless parent communicates.
