# WHOOP local backup format, version 1

A local backup is a UTF-8 JSON object containing the complete local dataset. Export it from Settings and restore it through Import. Restore replaces the current days, journal, activities, and selected date after an in-app confirmation. Validation finishes before the current dataset changes. A rejected file leaves existing data intact.

```json
{
  "format": "WHOOP_LOCAL_BACKUP",
  "version": 1,
  "exportedAt": "2026-11-08T14:00:00.125Z",
  "selectedDate": "2026-11-08T00:00:00.000Z",
  "days": [],
  "journal": [],
  "activities": []
}
```

All seven fields shown above are required. The optional `whoopAccountUserID` is a positive integer identifying the account that supplied synchronized records; absent/null remains valid for older backups. It preserves account-owner safeguards across restores and contains no token or credential. Empty arrays are valid. Unknown future versions and incorrect format markers are rejected. The importer treats top-level `format`, `version`, `exportedAt`, `selectedDate`, `journal`, or `activities` as backup envelope keys, including when their values are invalid. It never retries a rejected backup as a daily archive. A plain `{ "days": [...] }` object remains a daily import, which merges daily data rather than restoring a backup.

Dates use the same ISO 8601 encoder and decoder as daily archives, with explicit timezones and millisecond precision. Export uses UTC and fractional seconds. All dates must be finite and within years 0001–9999. The selected date, journal dates, activity start times, and export time retain their timestamps. Daily dates must be UTC midnight. Journal uniqueness compares UTC calendar days regardless of the stored time.

Each `days` entry follows `DailySnapshot`: `date`, optional `recovery`, optional `strain`, optional `sleepPerformance`, `sleepMinutes`, `sleepNeededMinutes`, optional `restingHeartRate`, optional `hrv`, optional `respiratoryRate`, `steps`, `energyKcal`, `heartRates`, and `source`. Absent optional metrics remain absent. The existing daily decoder defaults omitted sleep durations, steps, energy, and samples to zero/empty, and omitted provenance to `imported`. An explicit `example` or `imported` source is retained; restoring never relabels example data. Scores and metrics are copied without recomputation.

Daily entries must have unique UTC dates. Recovery and sleep scores are integers from 0–100; strain is 0–21; sleep durations are 0–1,440 minutes; resting heart rate is 1–300; HRV is 0–1,000; respiratory rate is 0–100; steps are 0–1,000,000; energy is 0–100,000 kcal. Floating-point values must be finite. Heart-rate samples contain `timestamp` and `bpm`; rates must be greater than 0 and at most 300, timestamps must belong to their entry's UTC day, and every sample timestamp must be unique within the day. Both conflicting and identical duplicate samples are rejected rather than silently dropping rows.

Each journal entry requires `date`, Boolean `caffeine`, `alcohol`, and `lateMeal` flags, and a `note` string. Notes preserve Unicode and newlines and may contain up to 20,000 Swift characters. There may be at most 10,000 journal entries, one per UTC day. Journal entries do not need a matching daily snapshot.

Each activity requires a valid unique UUID `id`, `start`, integer `durationMinutes` from 1–1,440, and a nonblank `name` of at most 80 Swift characters. Optional `strain` must be finite and from 0–21. Optional Boolean `strainIsEstimate` preserves the score's provenance. Activity timestamps and names are preserved. Activities do not need a matching daily snapshot.

Both encoding and decoding enforce a file size of at most 20 MiB (20 × 1,024 × 1,024 bytes), and at most 100,000 total records, counting days, individual heart-rate samples, journal entries, and activities together. Daily CSV/JSON imports retain their separate 10 MiB limit. The backup codec validates directly so a valid backup between 10 and 20 MiB can be restored. Malformed dates, missing envelope fields, invalid values, duplicate identities, and exceeded limits reject the whole backup.

The file is ordinary unencrypted JSON and includes journal notes and health metrics. Store and share the exported file as personal data. The backup contains local data only; it does not include Bluetooth pairing, device configuration, or remote service credentials.

## Optional Nutrition data

The optional `nutrition` object contains foods, exercises, weights, favorites, completed UTC day keys and settings. It uses typed contracts in Core/NutritionModels.swift, at most 10,000 combined records and the same full-backup total size/record limits. Older backups omit it and remain valid. Photos, AI keys and bridge tokens are excluded. Restoring a complete older backup replaces nutrition with an empty dataset after the existing confirmation; Reset Nutrition only affects this object.
