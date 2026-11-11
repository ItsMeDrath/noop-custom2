# Current launch: welcome, tracker setup and personal Home

First launch now opens **Welcome → Profile → Find your tracker → Import data → Home**. Tracker search uses the existing Bluetooth adapter, and connecting/importing later is supported. Setup completion is remembered on this iPhone; later launches go to the functional Home dashboard with your saved data and fresh live readings. The supplied screenshot values are no longer the app's launch data. More keeps an explicit screenshot preview.

See [startup behavior, migration and validation](Docs/APP-STARTUP.md). All **146 portable tests** and **13 packaging tests** pass; physical-device behavior requires iPhone testing. The GitHub workflow runs an Apple build after relevant updates to main.

---

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

# WHOOP — iPhone reconstruction

A standalone iOS 17+ SwiftUI project named **WHOOP**, with the original supplied wordmark, icon and typefaces. It combines local functionality with client behavior recovered using REA. Exact official-app appearance and feature parity are not established.

## Run on your Mac

**Windows:** use the separate `WHOOP-Codemagic.zip` upload package and [Codemagic instructions](README-CODEMAGIC.md). Codemagic supplies the cloud Mac; no local Xcode is required. The included `codemagic.yaml` builds an unsigned IPA for later signing. Its cloud build has not been dispatched here.

For an IPA, double-click **Build IPA.command** after extracting the project on a Mac with full Xcode. The detailed [iPhone installation guide](Docs/INSTALL-IPHONE.md) covers Sideloadly, signed Xcode export and the included manual GitHub Mac-runner workflow. No IPA has been built in this Linux executor.

1. Extract `WHOOP-iOS-source.zip` and open **WHOOP.xcodeproj** in Xcode 16 or newer.
2. Select the **WHOOP** scheme and an iPhone simulator, then Run.
3. For your iPhone, select the device and your development team under **Signing & Capabilities**. The signing profile must support the included HealthKit entitlement. The display name stays WHOOP; its separate bundle identifier is `local.whoop.reconstruction`.

The iOS project uses bundled resources and system frameworks. The server’s shared Nutrition routes require `npm ci` at the project root. The `WHOOPCore` package is local. Apple SDKs, code signing and device installation require a Mac with Xcode; this Linux workspace has not built an iPhone binary.

```bash
./Scripts/build-on-mac.sh
```

That command tests the core and builds an unsigned simulator application. To attempt a real arm64 device build and create an **unsigned** IPA on your Mac:

```bash
./Scripts/package-ipa-on-mac.sh
```

The latter packages the actual device build, never a renamed simulator product. Installation still requires device signing, including compatible HealthKit entitlements. No IPA was generated or signed here.

## Functionality

[Nutrition](Docs/NUTRITION.md) adds offline food/exercise/weight logging, Mifflin targets, macro dials, 7/30-day charts, favorites, photo/text AI estimates and day reviews through the existing server. Its section uses Inter and its own unbranded dark palette. [Live media](Docs/LIVE-MEDIA.md) adds camera/photo overlays, transparent PNG exports and the WorkoutLive extension source. Native media and widget runtime behavior remain unverified.

- **Screenshot-guided interface:** compact overview with three rings, Health/Stress shortcuts, activities, sleep, journal and customizable dashboard rows; Home/Sleep/Recovery/Strain/Nutrition/More tabs, secondary Health/Community/Profile destinations, and full-screen Sleep/Recovery/Strain gauges. See [visual-reference notes](Docs/REFERENCE-UI.md). Day history, charts, UTC dates and example/imported/empty states remain connected.
- **WHOOP account:** browser OAuth through the included personal HTTPS bridge; imports account-supplied cycle, Recovery, sleep and workout records over selected 14/30-day UTC windows. Setup is required; no live account exchange has been tested.
- **Apple Health:** explicit read-only import of steps, active energy, resting heart rate, respiratory rate, heart rate and unioned time asleep over 14 or 30 UTC days. It does not write to Health. SDNN is not substituted for WHOOP's RMSSD HRV.
- **Local records:** journal creation/edit/deletion, manual activity logs, activity editing/deletion, foreground workout recording with actual received heart rate and separately labelled local strain estimates.
- **Files:** validated CSV/JSON day import, day export with millisecond timestamps, and full versioned backups that include journal notes and activities. Restore validates the whole backup before replacement.
- **Devices:** standard heart-rate broadcasts; recovered GEN4/MAVERICK/GOOSE frame decoding with CRC checks; opt-in experimental Hello → matched success → live-HR request handling, with pending/error/timeout states.
- **Passive history:** recovered common history headers, counters, Unix timestamps and revision flags; unknown payloads remain raw. It does not request, acknowledge or erase history, and historical physiological fields remain unresolved.
- **Calculations:** all 211 recovered strain thresholds, selected helper equations, a controlled reference calculator, and a conservative bounded live smoother/interval accumulator. Local estimates do not overwrite supplied daily scores.

First launch displays a labelled example week. **Menu → WHOOP account** opens account setup. **Import from Apple Health**, **Import day data**, or **Record a workout** adds actual measurements. **Save full backup** includes your day data, journal and activity records; **Export day data** deliberately exports only the days. Example provenance survives backup and import.

## Important boundaries

| Area | State |
| --- | --- |
| Original name, wordmark and typefaces | Included with source provenance |
| Local features and portable helpers | Implemented; see source and tests |
| Standard/custom Bluetooth and HealthKit adapters | Implemented but untested on an iPhone/strap |
| Hello/live-HR commands | Narrow experimental opt-in; not full clock/identity/history initialization |
| Public WHOOP account sync | Native OAuth adapter + Node bridge source implemented; requires registered client and trusted HTTPS service |
| Personalized Home, online teams/coaching/payments | Private services unresolved |
| Daily Recovery/sleep scoring and native MSK formulas | Unrecovered; not replaced with fake measurements |
| Full history sync, exact visuals and official-app parity | Not established |
| Xcode device build and signed IPA | Still required on a Mac |

The app explains its local-reconstruction status in **Menu → About this edition**. It does not collect WHOOP passwords or claim affiliation. No private WHOOP service, firmware operation or physical sensor was used during development.

## Connect your WHOOP account

Follow [account setup](Docs/ACCOUNT-SYNC.md) and [server setup](Docs/AccountAPI/README.md). Register your own WHOOP OAuth client, configure the server-only credentials, and expose the bridge over trusted HTTPS on port 443. Enter that origin in the Account screen, Connect, then Sync. No password or client secret goes into this app. API compatibility was corroborated against a pinned third-party SDK because the official specification host was inaccessible; live validation remains required.

## Verification

**104 Swift core tests and 33 Node server tests pass.** Server tests use local HTTP handlers and synthetic upstream records, without contacting WHOOP.

The portable Swift suite covers imports, provenance, timestamp roundtrips, complete backups, sleep-interval union, standard BLE bytes, recovered frame/command golden fixtures, malformed/fragmented streams, bounded live strain and reply-state handling. Exact results are in [VALIDATION.json](VALIDATION.json) and [Validation/core-tests.log](Validation/core-tests.log).

Application Swift files pass frontend parsing and the Xcode project passes structural checks. **Those checks are not an Apple SDK typecheck, an Xcode build, a simulator run or a device test.**

See [STATUS.md](STATUS.md), [CORE-NOTES.md](CORE-NOTES.md), [Apple Health](Docs/APPLE-HEALTH.md), [backups](Docs/BACKUP-FORMAT.md), [live strain](Docs/LIVE-STRAIN.md), [device stream](Docs/DEVICE-STREAM.md), [packet decoding](Docs/WHOOP-PROTOCOL.md), [device history](Docs/DEVICE-HISTORY.md), [device time](Docs/DEVICE-TIME.md) and [reconstruction evidence](Docs/RECONSTRUCTION.md). [Examples](Examples) contains sample import files. The full REA records are delivered separately as `WHOOP-analysis-report.zip`.

The [parity ledger](Docs/PARITY.md) separates the current implementation from the requested exact WHOOP experience and identifies the missing evidence and behavior.

## Repository migration

The previous NOOP application is preserved on [the recovery branch](https://github.com/abdullahalmaeeni7-dot/noop-custom1/tree/backup/noop-before-whoop-5e7f970). Its app targets, packages, tools and workflows have been removed from this branch. The root LICENSE, NOTICE, ATTRIBUTION.md and DISCLAIMER.md are retained as historical copyright and attribution records for that prior source; their descriptions of NOOP do not describe the current application.
