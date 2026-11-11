# Apple Health import

Apple Health import is read-only and runs on demand on a supported iPhone. Opening the sheet never requests permission or starts a query. The **Import from Apple Health** button requests read access to steps, active energy, resting heart rate, respiratory rate, heart rate, and sleep analysis. No HealthKit write types are requested, and the adapter contains no HealthKit save or delete operation.

The user chooses 14 or 30 UTC dates, including today so far. Queries never request dates beyond the time the import started. Apple Health can return no records for an empty range or denied read access; its authorization completion callback does not disclose read permission. The app describes both possibilities and offers a retry, without claiming every permission was granted.

## Measurement mapping

| Apple Health | Saved daily measurement |
| --- | --- |
| Step count | HealthKit cumulative sum, rounded to a whole step |
| Active energy burned | HealthKit cumulative sum in kcal |
| Resting heart rate | HealthKit discrete average in beats/min |
| Respiratory rate | HealthKit discrete average in breaths/min |
| Heart rate | Timestamped beats/min samples |
| Sleep analysis | Union of asleep intervals, clipped to each UTC date, rounded down to whole minutes after union |

Statistics queries use individual UTC day bounds and strict sample-start matching. Samples that span a day boundary are assigned by their start time for quantity statistics. This is not a local-time Health app daily rollup. Today is incomplete. Days with no readable measurements are omitted; a recorded zero for steps or energy still counts as a readable measurement. Existing snapshot integer fields cannot express absent steps or sleep separately from zero; new days use zero for missing integer fields. The app does not treat those fields as proof that a person took no steps or did not sleep.

Sleep includes asleep-unspecified, core, deep, and REM values. Awake and in-bed records do not contribute. Duplicated or overlapping asleep intervals are counted once, even if multiple sources recorded them. Gaps remain gaps. A sleep period crossing midnight is split between two UTC dates; this does not reconstruct WHOOP nights or WHOOP sleep need.

Apple Health HRV is **SDNN**; WHOOP HRV is **RMSSD**. The archive's generic `hrv` field has no method metadata, so this adapter deliberately does not request or populate HRV. The import sheet explains the difference. It does not substitute SDNN for RMSSD.

New imported snapshots use `source: .imported`, with `recovery`, `sleepPerformance`, `strain`, and `hrv` absent, and `sleepNeededMinutes: 0`. HealthKit measurements do not provide WHOOP Recovery, Sleep Performance, Strain, or sleep need. No WHOOP score is derived or invented. The store merges available measurements into existing imported days without erasing supplied scores or unrelated measurements, and removes demonstration days when real measurements are first saved.

## Bounded queries, errors, and saving

Heart-rate sample queries request at most 100,001 records in ascending time order. The last is a sentinel; at most the first 90,000 raw records are retained. Reaching the sentinel produces a visible warning that later heart-rate records are omitted while other daily measurements still cover the requested dates. Invalid/nonfinite heart-rate values outside 1–300 beats/min are excluded. Distinct source records at exactly the same timestamp are resolved by the lexically smallest HealthKit UUID so the archive has one record per timestamp. This deterministic resolution is not a claim about preferred source accuracy.

Sleep queries request at most 50,001 raw records. Reaching the sentinel rejects the entire import and asks for a shorter range instead of saving a misleading partial sleep duration. Daily statistics are calculated by HealthKit, rather than downloading an unbounded quantity sample list. Out-of-range or nonfinite daily measurements reject the import before saving.

Each query has a checked continuation protected by a lock. Cancellation stops installed queries and resolves each continuation once, including cancellation racing query setup or completion. HealthKit authorization UI cannot be dismissed by the app; cancelling the app task discards its result. An empty result, request error, query error, unsupported device, and cancellation all have distinct handling. No query result is saved until the whole import completes. Saving uses the store's transactional persistence path. A failed save retains the fetched data in the sheet for **Retry Saving** or **Discard Unsaved Import**.

## Device validation still required

The portable interval union tests run on Linux. Parsing Swift sources does not type-check HealthKit/SwiftUI against the iOS SDK. An Xcode build and a signed physical-device test are required to validate HealthKit entitlements, the usage description, system authorization UI, denied/partial read access, empty ranges, cancellation, source overlaps, and actual HealthKit statistics behavior. Simulator data availability varies. No iOS build or HealthKit device execution was performed in the Linux environment.
