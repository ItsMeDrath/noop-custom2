# Portable WHOOPCore implementation

`WHOOPCore` is a Foundation-only local Swift package for iOS 17+ and Linux verification. It contains models, explicitly labelled example data, import/export validation, the standard Bluetooth heart-rate measurement decoder, and a reference implementation of selected recovered Android strain helpers. It also maps validated public account records and decodes selected device-history headers and timestamp fields. Network authorization lives in the separate app/backend adapters. The core does not call private services, classify sleep, calculate daily Recovery, or execute the packaged native strength-training library. See Docs/ACCOUNT-SYNC.md, Docs/DEVICE-TIME.md and Docs/DEVICE-HISTORY.md.

## Shared model and date contracts

`DailySnapshot`, `HeartRateSample`, `JournalEntry`, `ActivityRecord` and `DayArchive` are public Codable/Equatable/Sendable values. `DataSource.example` is labelled **Example data**. JSON archives retain explicit `.example` provenance through export/import, so exporting an example week cannot remove its label. Missing source defaults to `.imported`, and CSV is imported. Imported means user-supplied data, not independently verified measurements. Example values are deterministic illustrative fixtures, not measured health results.

Dates are normalized/grouped using `DayCalendar.utc`, not the device timezone. Use `DayCalendar.start(of:)` for selection/storage keys and that calendar when displaying archive days. A CSV timestamp with a timezone offset is converted to its actual instant and assigned to its UTC day. This avoids changing a day archive when travelling or changing the device timezone; it is an app integration choice, not a recovered WHOOP server timezone policy.

## Supported files

`ImportReader.read(_:filename:)` accepts `.csv` and `.json` case-insensitively. The complete file must be at most **10 MiB**, with at most **100,000 total heart-rate rows**. Imports are validated before returned state is available; malformed records reject the import rather than silently skipping values.

### Heart-rate CSV

Required unique headers are `timestamp` and `heart_rate` (trimmed/case-insensitive). Additional columns are accepted and ignored. UTF-8 BOM, LF/CRLF, quoted fields and doubled quotes are supported. There may be at most 64 columns. Numeric epoch timestamps and timezone-less/date-only timestamps are deliberately rejected to avoid unit/timezone ambiguity.

```csv
timestamp,heart_rate
2026-11-08T08:00:00.125Z,72
2026-11-08T08:00:01.125Z,74
2026-11-08T12:00:00+04:00,81
```

Heart rates must be finite and above 0, at most 300 bpm. Samples are sorted. Exact same-time/same-value duplicates coalesce; conflicting values at one timestamp reject the file. Heart-rate-only imports leave Recovery, strain and sleep-performance scores **nil** and sleep/baseline aggregates unset. The importer does not invent a resting baseline, infer recovery, or treat incomplete heart-rate data as a nightly score.

### Day JSON

An object with a `days` array or a top-level day array is supported. `date` is required; other daily values are optional. Day dates accept `yyyy-MM-dd` (UTC) or ISO 8601 strings with an explicit timezone. Heart-rate sample timestamps require the model's timestamp field. Unknown JSON keys are ignored by Codable. Example:

```json
{
  "days": [{
    "date": "2026-11-08",
    "recovery": 78,
    "strain": 10.4,
    "sleepPerformance": 89,
    "sleepMinutes": 445,
    "sleepNeededMinutes": 500,
    "restingHeartRate": 52,
    "hrv": 74,
    "respiratoryRate": 14.2,
    "steps": 8000,
    "energyKcal": 2300,
    "heartRates": [{"timestamp":"2026-11-08T08:00:00.125Z","bpm":72}]
  }]
}
```

Recovery/sleep-performance must be 0–100; strain 0–21; sleep durations 0–1440 minutes; resting HR 1–300 bpm; HRV 0–1000 ms; respiratory rate 0–100; steps 0–1,000,000; energy 0–100,000 kcal. These are defensive import bounds, not medical advice or WHOOP's private validation rules. A sample must belong to its entry's UTC day. Duplicate day entries are rejected.

Use `ImportReader.jsonEncoder()` to export/persist `DayArchive` or app state, paired with `ImportReader.jsonDecoder()` for persistence; they handle fractional ISO 8601 dates so distinct millisecond samples in the same second remain distinct. Using Foundation's plain `.iso8601` encoding can omit fractional seconds and collapse those identities. Calling the decoder directly preserves stored provenance; importing through `read` additionally validates values and retains an explicit example label.

## Selected strain reference API

`StrainCalculator` deliberately exposes the recovered **selected helper boundary**, not a fabricated complete daily scorer:

- `lookupEntries()` returns all 211 retained `(lowerThreshold, score)` pairs.
- `scaledScore(raw:)` uses the recovered interval lookup, without interpolation. Exact finite lower boundaries enter the corresponding row; `raw >= 0.70195765` saturates at 21.0. The shipped loop's unusual final-row fallback makes finite negative input return 21.0; that behavior is retained explicitly. Nonfinite input is rejected by the Swift API rather than emulating unspecified Android NaN/infinity integration.
- `reserve(heartRate:restingHeartRate:maximumHeartRate:)` uses the recovered `M + 3` denominator offset, clips to 0–1 and zeroes values at or below 0.3.
- `weightedContribution(reserve:durationSeconds:)` evaluates `16 / (exp((1-reserve)/0.15)+1) * durationSeconds` for positive reserve and zero otherwise. It does not independently cap durations; the recovered timescale helper does that.
- `rawContribution(smoothedSamples:restingHeartRate:maximumHeartRate:terminalTimestampMilliseconds:)` accepts **already-smoothed samples**, raises the supplied maximum to the batch maximum, applies recovered duration weighting, divides by 691200 and clamps the batch result to 0–1. It does not run the complete Android stateful smoothing/leftover pipeline or perform the age/sex/fitness estimation/validation path. A caller must not pass ordinary unsmoothed recordings and label the result an official WHOOP day score.
- `durationScales(for:terminalTimestampMilliseconds:)` exposes the recovered upper cap of 3 seconds and literal singleton quirk. For multiple samples, zero terminal repeats the prior duration; otherwise the terminal delta is divided by 1000. For a singleton, terminal `-1` means one second; otherwise the recovered expression subtracts `timestamp / 1000` (integer division) from **undivided** terminal and caps at 3. Negative duration is not silently repaired; the aggregate raw result is clamped nonnegative as recovered.
- `quantile(_:fraction:)` provides the recovered sorted linear quantile helper, default fraction 0.25. The window/gap/leftover algorithm itself is deliberately not claimed as implemented.

Dates entering the reference API are interpreted as epoch milliseconds after rounding. This is an explicit boundary convention for the portable app. The analysis suggests a milliseconds/seconds relationship from literals 1000 and 30000, but did not validate the entire official timestamp producer. Inputs with duplicate/non-increasing rounded milliseconds, nonfinite values, unrepresentable timestamps or a nonpositive reserve denominator are rejected defensively. These validations go beyond selected Android helpers. No numerical/device parity with the installed official app has been measured.

### Evidence identity

The bundled `Core/Resources/strain-lookup.json` is copied byte-for-byte from the retained `STRAIN-LOOKUP-TABLE.json`, including its source DEX hash and REA Evidence ID. That source table is `vd0.p.<clinit>`, Evidence `ev_642e0ca1bfc795078744bff00c7848b797c2be055e557eba5baf25b56ea4548c`.

The selected helpers derive from static REA results:

| Helper | Evidence |
| --- | --- |
| Raw normalization/clamp, `vd0.o.h` | `ev_d5a1cb35513ddd636e8d59a32c1efc0b5116f9e5166682e72d8601e497f1548e` |
| Reserve cutoff, `vd0.d.b` | `ev_81250535675ce8c00ec3945c4f3e085be32c708c457c1733c98f387f2080e585` |
| Logistic weighting, `vd0.o.o` | `ev_dfa925e4bb1127a6ad992f8e79039d83b32fe105549d996ee5e766689ddaf989` |
| Durations, `vd0.o.l` | `ev_68ae8bfbb0987a9d8292d19d6283fde7aacaf6087bea69135164f5b77ea68cc1` |
| Lookup loop, `vd0.o.j` | `ev_eaf88078b89adab349b2ce84e4b28c4826b6b935c7efe0d9a17e2ee5df674a9f` |
| Quantile, `vd0.d.j` | `ev_6562933df5a9b2c1049ce3e8209b20d140062087c0a060c1cac391e18382c638` |

The Java lookup rendering had a misleading loop branch; the retained supplemental DEX disassembly, not that Java layout alone, established interval behavior. Full observations and limitations are in the accompanying WHOOP analysis bundle's `phase3/HEALTH-CALCULATIONS.md`. This package is newly written Swift code guided by those selected static findings, not the original WHOOP source project.

## Standard Bluetooth heart rate

`HeartRateMeasurement.decode(_:)` parses Bluetooth SIG characteristic **0x2A37** only. Flags bit 0 selects 8-bit or little-endian 16-bit heart rate. Insufficient payloads and values of 0 or above 300 return nil. Other optional measurement fields are ignored after the heart rate. It does not decode WHOOP custom characteristic frames, send hello/clock commands, retrieve historical packets or generate recovery/sleep scores.

## Verification

The package is tested with Swift 6.2.1 on Linux in Swift 5 language mode. Tests cover original lookup constants and interval boundaries, cutoff/logistic anchors, duration quirks, invalid inputs, standard Bluetooth measurement byte layouts, UTC grouping, CSV quote errors, conflicting duplicates, JSON bounds and archive round trips. This validates portable logic, not SwiftUI/Xcode compilation or iPhone/device operation.

The managed environment's default home caches are read-only. The successful verification command uses task-local compiler/SwiftPM caches:

```sh
CLANG_MODULE_CACHE_PATH=/tmp/whoop-core-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/whoop-core-module-cache \
/workspace/toolchains/swift-6.2.1-RELEASE-ubuntu24.04/usr/bin/swift test \
  --scratch-path /tmp/whoop-core-build \
  --cache-path /tmp/whoop-core-cache \
  --config-path /tmp/whoop-core-config \
  --security-path /tmp/whoop-core-security
```

On a normal Mac, `swift test` in the project root uses the system Swift toolchain without those managed-environment cache overrides.
