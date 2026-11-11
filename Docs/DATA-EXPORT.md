# In-app measurement export

Open **More** in the current Home screen to open **Export Data**. This is a feature inside this app; it does not ask the user to export from the official WHOOP app.

Choose all saved dates or a custom inclusive UTC date range, then choose:

- **Save JSON**: personalized profile, calculated highlights, daily measurements, supplied scores and saved heart-rate samples. Compatible with this app's updated importer; older day-data readers can still read the `days` array.
- **Save Profile & Highlights CSV**: chosen age/streak/name values and calculated extrema/streaks, with units, dates and source labels. Use JSON for re-import.
- **Save Daily CSV**: one spreadsheet row per UTC day, explicit units in column headers and a sample count. Optional unavailable scores are empty cells. This summary CSV is for spreadsheets, not the heart-rate CSV importer.
- **Save Heart-Rate CSV**: `timestamp,heart_rate`, sorted samples with fractional ISO 8601 UTC timestamps. Compatible with the existing heart-rate CSV importer. Disabled when there are no saved samples; no trace is generated from summary heart rates.

The iOS Files exporter lets the user choose where to save each file. Preparation runs in a cancellable background task. Canceling does not change stored measurements. Nothing is uploaded automatically.

## Where records come from

The screen uses the existing `AppStore` and `whoop-local-data.json` persistence. Home's separate `pulse-home-mock.json` is never read. Days marked `example` are filtered out. If the app has no saved non-example days, daily/heart-rate export is disabled. Personalized profile-only JSON and highlights CSV remain available after the user configures a profile; records stay unavailable rather than being fabricated.

The saved archive's `imported` provenance covers WHOOP account sync, Apple Health imports, tracker recordings and imported files. It does not authenticate the origin of every field, and merged days may combine providers. Accordingly this feature exports **saved measurements**, not a verified WHOOP-only raw account archive. It preserves stored values rather than recalculating Recovery, Strain or Sleep Performance. Missing non-optional fields retain the existing model's stored zero defaults; the exporter does not infer availability.

Use **Connect WHOOP account / Sync WHOOP account** to open the retained Account screen and its existing OAuth bridge workflow. A deployed/configured bridge and authorized account are required for that connection. Use **Import profile/day JSON or heart-rate CSV** to reuse the existing file import path. This does not parse the official WHOOP ZIP/CSV bundle.

JSON exports contain `days`, optional `profile`, `highlights` and `metadata`. See [personalization and highlight semantics](PROFILE-PERSONALIZATION.md). Activities, journal notes, nutrition, account identity, OAuth credentials and the mock Home state are excluded. Complete backups remain a separate existing feature. The retained legacy day-data export also uses the same example-excluding codec.

## Implementation

- `Core/MeasurementExport.swift`: shared selection, validation, JSON and CSV encoding, record/size bounds and filenames.
- `App/Views/MeasurementExportView.swift`: range controls, empty/error/loading states, Files exporter/importer and existing account sheet.
- `App/WHOOPApp.swift`: owns the existing `AppStore` and `AccountModel`, shared through environment objects.
- `App/Pulse/PulseComponents.swift`, `App/Pulse/PulseHomeView.swift`: More opens the export screen.
- `App/Views/RootView.swift`: retained export uses the same codec.
- `Tests/WHOOPCoreTests/MeasurementExportTests.swift`: real codec tests with explicitly synthetic fixtures, not user data.

Validation: all 143 portable Core tests passed on Linux, including 13 original export tests and 13 new profile/highlight tests. Tests cover example exclusion, inclusive UTC range boundaries, fractional timestamps, missing values, units, archive reimport, CSV reimport, duplicate/conflicting records, invalid dates/metrics, empty ranges and size bounds. Swift frontend syntax and Xcode project structural checks passed. An Apple SDK build, Files picker interaction and native UI execution are unverified because this executor has no Xcode/iPhone simulator. No actual user export or IPA was generated here.
