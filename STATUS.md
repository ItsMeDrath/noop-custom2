# Current update: personal profile and exported highlights

Tap the Home avatar → **Edit** to set your name, username, age, WHOOP Age display and day streak. Ages have no numeric upper limit. Data Highlights show saved-data extrema and consecutive-day streaks in the reference Profile layout. **More → Export Data** now includes personalization and highlights in JSON, plus a profile/highlights CSV. Profile-only export and JSON re-import are supported.

Read [personalization, export schema and verification](Docs/PROFILE-PERSONALIZATION.md) and [the browser gallery](design/profile/Profile-gallery.jpg). User-chosen values are labeled separately from calculated records. All 143 portable tests pass. Native Apple compilation, exact visual parity and Files/storage UI execution remain unverified; no IPA is included. Earlier update notes below are historical.

---

# Current update: full-screen Live camera

Home → **+ → Create WHOOP Live** now opens the full-screen camera layout from the supplied screenshot: Overview dials, large Strain/Recovery/Sleep gauges, native capture controls and a bottom mode selector. The existing camera, photo, recorder and Live Activities paths are reused. More → Export Data remains available.

See [Live implementation and validation limits](Docs/LIVE-REFERENCE.md) and [the browser preview](design/live/01-Overview.png). Preview values are labeled examples; live HR requires fresh sensor data. All 130 portable tests pass. Native iPhone rendering and capture remain unverified. Earlier update notes below are historical.

---

# Current update: in-app data export

**More → Export Data** now saves non-example measurements as JSON, daily CSV or heart-rate CSV, with inclusive UTC date filters and the iOS Files picker. The existing storage and account connection are reused. Home mock values never enter these exports. Saved imports may combine providers, so this is not a verified WHOOP-only raw account archive.

Read [data export and validation](Docs/DATA-EXPORT.md). All 123 portable Core tests pass, including 13 new export tests. Native iOS compilation and Files picker execution remain unverified. No IPA is included.

---

# Current launch: WHOOP Home revision 05

WHOOP display name, supplied wordmark/monogram, and DIN Pro / Proxima Nova typography are restored by explicit request. The expiry banner remains removed. Home's date control, floating navigation icon and motion are revised. Scores remain illustrative and real tracker readings stay separate.

See [revision 05 and remaining differences](design/home/REVISION-05.md), [the current Home gallery](design/home/revision-05/Home-review-gallery.jpg), and [validation](VALIDATION.json). Exact visual/animation parity and native compilation are unverified. Other primary screens remain pending the requested Home review.

---

# Delivery status — 9 November 2026

The existing native iOS project now includes Nutrition, Live camera/photo overlays and a WorkoutLive Lock Screen/Dynamic Island extension. No replacement project or authentication system was created.

## Nutrition

Six primary tabs: Home, Sleep, Recovery, Strain, Nutrition and More. Nutrition includes date navigation; calorie-left, protein and net-balance dials; meals, macros, exercise and weight logs; favorites/recents; calorie/protein/deficit trends; profile-based targets and overrides; export/reset; and explicit AI photo/text/exercise/review requests with editable estimates. Manual functions work offline. New screens use Inter and an unbranded dark palette. See [implementation and server setup](Docs/NUTRITION.md).

All energy calculations live in `lib/nutrition/calc.ts`, packaged unchanged for native JavaScriptCore execution. Existing atomic storage, optional backup fields and authenticated bridge transport are reused. AI keys remain on the server. Historical deficits include only days explicitly marked fully logged; energy-equivalent fat change is an estimate.

## Live media and local editions

Source includes foreground video with telemetry overlays and optional microphone, recorded-day photo overlays, transparent PNG export, save/share actions and opt-in Live Activities. Workout calories and heart-rate zones are unavailable from the current recorder; daily photo calories are distinctly labeled. Media and ActivityKit require real device verification. See [behavior and limits](Docs/LIVE-MEDIA.md).

The One/Peak/Life selector is a free local presentation preference. It does not purchase, activate or unlock any official membership, service or hardware feature.

## Existing functions retained

Local health dashboards, example/imported/empty states, Apple Health read import, CSV/JSON import/export, versioned full backup/restore, journals/activities, foreground heart-rate workouts, local strain estimates, selected recovered frame decoding and opt-in Hello/live-HR requests remain available. Public account OAuth/Keychain/session/history mapping and encrypted server token storage remain in place. No account was linked or service deployed here.

## Verified here

110 portable Swift tests, 20 Nutrition calculator/API tests, 35 existing-server/integration tests and 12 synthetic IPA-validator tests pass. TypeScript builds/typechecks. Twenty-five app Swift sources plus the widget pass frontend syntax parsing. Project references, fonts, offline calculator provenance and widget dependency/embed structure pass checks. Retained logs and source hashes are in [VALIDATION.json](VALIDATION.json).

A separate browser preview uses illustrative logs and the actual shared calculator. Its date navigation, deep-dive range selection and manual draft-save checks pass. It is not an iPhone screenshot or native runtime test.

## iPhone delivery and remaining work

Mac build/export scripts, manual GitHub Mac-runner workflow and Codemagic configuration are supplied. The flat cloud-upload archive contains the complete native build inputs; full source also contains the separately deployed AI/account server. See [Windows/Codemagic instructions](README-CODEMAGIC.md) and [installation steps](Docs/INSTALL-IPHONE.md).

This Linux executor has no Apple SDK or usable Codemagic/GitHub credential. Apple SDK typechecking, Xcode compilation, provisioning, camera/audio/photo permissions, video orientation/synchronization, HealthKit, BLE background delivery, Live Activities, configured AI provider calls and a signed installable IPA remain unverified. No IPA was produced.

Exact official WHOOP parity, private algorithms/services, ECG/AFib/Blood Pressure hardware features, online coaching/community/payments and complete device-history interoperability remain unresolved. See [parity ledger](Docs/PARITY.md). Source implementation is not evidence that those services have been reproduced or unlocked.
