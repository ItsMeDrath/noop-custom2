# REA findings used by this project

## Artifact identity

WHOOP Android 5.444.1 / 431134, downloaded base SHA-256 `f2f84ab1b49fb69e5298ecab5acda706a47cd556df726662792f1cfd6a512c9a`. All eleven supplied DEX files match corresponding entries in that original base. REA used an unsigned repacked analysis container, SHA-256 `1a00151e0a6933e075167586290d07df648e1e3eab3f2f24e1c9b561ea41f241`. These containers must not be conflated.

The complete records, byte hashes, method representations and unknowns are in the separate `WHOOP-analysis-report.zip`. No WHOOP Android or native code was executed in this reconstruction.

## Source observations → implemented boundary

| Recovered observation | Evidence | Implemented use |
| --- | --- | --- |
| Home/Health/Community/settings/profile navigation variants | `ev_9b53387a319cb5818d1848fafa337b55b2704f90ad96ae015f9e049f3e74253a` plus supplemental resource/DEX bindings | Five local destinations. This does not establish the actual member's visible tab list. |
| Native Android main shell combines NavHost and Compose | `ev_d89f376d4cca935d0726590ba2d510f70e2545e46f19e038c9fef1b46c5741f6` | An independently implemented SwiftUI shell; no original Android UI runtime embedded. |
| Home request and typed server-fed response | `ev_695988b45f1b793476737bb5c04e46a48481eec5d2e74e3da413d5b25ca51965`, `ev_eb3660d69924494de36851c5fcef121ca0a64a6d774613c986a24485204ea5be` | Explains why original personalized Home contents are unavailable. This app uses labelled examples, supplied files or separately configured public-account imports. |
| Local strain reserve, weighting and aggregation | `ev_81250535675ce8c00ec3945c4f3e085be32c708c457c1733c98f387f2080e585`, `ev_dfa925e4bb1127a6ad992f8e79039d83b32fe105549d996ee5e766689ddaf989`, `ev_d5a1cb35513ddd636e8d59a32c1efc0b5116f9e5166682e72d8601e497f1548e` | Portable selected helper transcription and controlled reference scenario, not a daily-score replacement. |
| 211 raw-to-scaled score thresholds | `ev_642e0ca1bfc795078744bff00c7848b797c2be055e557eba5baf25b56ea4548c` plus bounded DEX literal decoding | Exact resource in Core/Resources/strain-lookup.json; boundary tests retained. |
| Live strain controller calls local helper | `ev_63aa9b9f6bef97dcd2472cbb91deedff906de8d12df8e15bfd75e7ec80454cb2` | Proves an implemented Android local path; this app does not claim its full stateful smoothing/subscription pipeline. |
| Strength-training packets call native PushCore | `ev_d78b16bc030bc11001b0b8b436d5f6e56bc4ee6ceca5a24766d94fcdeea1ec29` | Native internals remain unresolved and are not ported. Manual local activity logging supplies no invented strain. |
| Splash state and first-launch flag are separate from authentication | Phase4 STARTUP-GATES.md and its exact records | No fabricated WHOOP sign-in or activation success flow. |

## Later functional expansion

The later source includes read-only Apple Health import, full backup/restore, activity/journal management and foreground workout recording. These local operations are independently written integration code. Apple sleep intervals are unioned and clipped to UTC days; HRV SDNN is omitted rather than labelled RMSSD. The streaming strain engine preserves selected source helpers but deliberately avoids repeated last-used points, singleton duration ambiguity and extrapolated missing intervals; its output is a local estimate, not a daily WHOOP score.

Passive GEN4/MAVERICK/GOOSE decoding is supported by independently recovered layouts and CRCs. The narrow Hello/live-HR command contract and reply fields are recovered in `phase5/HELLO-STREAM.md` of the analysis bundle. GOOSE CRC-range evidence is `ev_98683339b53679e473264d8ae13c98c09696d0583490ec92663c9a93e6197c71`; the selected aligned outgoing builder is `ev_1e0e9698643ea54f7faf79dd246c2fda40c64f0204a10e472f7755e282317351`. The opt-in iPhone request workflow is a local policy, not the full Android initialization process. See [DEVICE-STREAM.md](DEVICE-STREAM.md) and [WHOOP-PROTOCOL.md](WHOOP-PROTOCOL.md).

## Account and passive history addition

[Device time](DEVICE-TIME.md) and [history headers](DEVICE-HISTORY.md) are derived independently from the supplied APK through REA and supplemental DEX decoding. The converter uses Unix seconds plus 1/32768-second ticks, rounded to milliseconds. Selected history revisions expose common headers and flags; physiological offsets are not guessed.

[Account sync](ACCOUNT-SYNC.md) is independently written integration code corroborated against the pinned external SDK in [SOURCES.json](AccountAPI/SOURCES.json). It is not recovered private-server source or live account evidence. The personal bridge/native adapter imports provider-supplied scores without reproducing private Recovery/sleep algorithms.

## Branding assets

[ASSET-PROVENANCE.json](ASSET-PROVENANCE.json) identifies selected compiled vector/font/icon members and their hashes. `WhoopWordmark.swift` preserves the coordinates of `res/drawable/whoop_logo_vector.xml` and scales them into a SwiftUI path. The bundled font PostScript names were read from their name tables and match the Info.plist registrations. `WhoopIcon.png` is the original 512×512 APKM icon, referenced as a legacy development-app icon; Apple distribution icon validation has not been performed.

The earlier five-item shell was replaced after the user supplied visual references. The current compact overview, four-tab bar, detail gauges and health tiles follow those screenshots, with version choices documented in REFERENCE-UI.md. Rendering details, local persistence, archive format, UTC days, input bounds, strain estimates and missing-value handling remain reconstruction choices. They are not observations of a signed-in official app. Fonts, names and path coordinates alone cannot establish exact visual equivalence.

## Validation boundary

Foundation-only code was compiled and tested on Linux. App Swift files were parsed, not typechecked against SwiftUI/CoreBluetooth/Charts Apple SDKs. A structural project check cannot establish iOS SDK compatibility or runtime behavior. No private API, account, live sensor or firmware operation was used to produce the project.
