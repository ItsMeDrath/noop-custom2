# Personalization and exported highlights

Tap the Home avatar to open the full-screen **Profile**. Tap **Edit** or the gear to change the display name, username, age, WHOOP Age display and chosen day streak. The same editor is available through **More → Export Data → Edit Profile**.

Age fields accept zero or any positive decimal value, with no numeric upper limit. They are stored as normalized decimal strings, not floating-point numbers, so values beyond ordinary human ages and very long numbers remain exact. Negative/non-numeric input is rejected. No slider or date-of-birth age cap is imposed. WHOOP Age is clearly a **personalized display**, not a health-age algorithm. These settings do not modify nutrition calculations or a WHOOP account.

The day-streak override is optional. Set any non-negative whole number supported by the device integer type, or turn the override off to use the calculated consecutive saved-day streak. Home's avatar/streak badge, profile name and sample review/Coach greeting follow the saved personalization. The existing illustration-only Home streak remains the fallback in example mode; it is not exported as measured history.

## Data Highlights

The profile uses the supplied dark card/ring layout, 1M / 3M / All Time selection, streak badges and notable-stat rows. Calculations use saved non-example data, with UTC dates and no future records:

- Best Sleep Performance, Peak Recovery and Max Strain, with record dates.
- Lowest Recovery, lowest/highest resting heart rate, lowest/highest HRV, max received heart rate and longest sleep duration.
- Current and longest logged-day streak; longest 70%+ Sleep, green Recovery (67%+) and 10+ Strain streaks.

Missing calendar dates break consecutive-day streaks. Duplicate dates do not increase a streak. A current streak can end today or yesterday, so a not-yet-logged current day does not immediately erase it. Empty days with no available measurements do not count. Tied records retain the earliest date. These are logged-data streaks, not verified WHOOP wear-time streaks. Missing records show a sync/empty state; no record is manufactured from Home examples.

The profile's saved-days badge replaces an unverified membership-level claim. The gold age orb is decorative and its value comes from the user's setting. Exact official font rendering, imagery and animation parity remain unverified.

## Export and restore

**Save JSON** now exports `days`, optional `profile`, `highlights` and `metadata`. Metadata identifies `WHOOP_PERSONALIZED_EXPORT` version 1, UTC, the selected date range, export time, user-configured profile values and saved-measurement highlights. Profile-only JSON is allowed after personalization, even without synced measurements. Existing day-data readers still read its `days` array.

**Save Profile & Highlights CSV** includes chosen profile values and all record/streak rows, with units, dates and source labels. CSV text cells are escaped and spreadsheet formulas are neutralized. Daily CSV and heart-rate CSV retain their earlier formats. Profile/highlight CSV is for spreadsheets; use JSON to restore personalization.

Importing the personalized JSON validates its profile and day records before any local mutation. Exported highlight values are ignored on import and recalculated, so edited highlight metadata cannot become a measured score. Legacy day JSON and heart-rate CSV remain supported. Profile-only import preserves existing day data. The app's existing full backup format gains an optional `profile`; backups and saved-state files without that field remain readable.

Personalization uses the existing protected `whoop-local-data.json` store. Profile saves and imports roll back their in-memory changes if persistence fails. Clearing all local data clears personalization; showing examples keeps preferences. Export still excludes journal notes, activities, nutrition and credentials; the separate complete backup includes the existing full data and now profile preferences.

## Validation

All 143 portable Core tests pass, including 13 new profile/highlight tests. Coverage includes a 500-digit age, exact decimals, normalization, invalid values, custom-versus-calculated streak separation, date gaps/duplicates, example/future exclusion, selected ranges, record extrema, CSV escaping, profile-only export/import, tampered highlight metadata, legacy imports and older backups. Swift UI sources pass syntax parsing and the generated Xcode project passes structural validation.

Six browser layout checks cover profile display, actual Swift-derived highlight values, unrestricted age inputs, custom streak updates, invalid-age feedback and the four export options. Review pictures use explicitly synthetic imported-day fixtures; they are not user data or native captures. No Apple SDK build, device storage UI run, native Files picker or signed IPA was produced in this Linux environment.

[Profile preview](../design/profile/01-Profile.png), [Highlights](../design/profile/02-Highlights.png), [Editor](../design/profile/03-Personalize.png), [Export](../design/profile/04-Export.png), [gallery](../design/profile/Profile-gallery.jpg).
