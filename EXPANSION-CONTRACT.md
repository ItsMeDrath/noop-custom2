# Functional expansion

No environment changes/publication and no original NOOP repository edits. Existing WHOOP brand retained. Parent integrates new portable components and AppStore/Root/DeviceModel. New code must preserve source provenance and not present local estimates as official daily scores.

- Passive custom GATT notifications + validated GEN4/MAVERICK/GOOSE frames where exact layout proven. No unknown command/firmware writes.
- Read-only HealthKit import by explicit in-app action. SDNN omitted from generic WHOOP-style HRV display because RMSSD equivalence is false. Daily Recovery/sleepPerformance/strain absent unless explicitly supplied.
- Full JSON local backup/restore, journal/activity CRUD.
- Foreground recorded workout using actual received heart-rate timestamps, conservative recovered local strain estimate, no estimated calories or day-score overwrite.
- Recovered helper equations remain distinct from conservative streaming integration. Native MSK and private services remain unavailable.

AppStore additions parent implements: `mergeMeasurements([DailySnapshot]) throws`, `makeBackup() throws -> Data`, `readBackupFile(URL) async throws -> LocalBackup`, `restoreBackup(LocalBackup) throws`, `deleteActivity(UUID)`, `deleteJournal()`, `saveRecordedWorkout(name:start:durationSeconds:heartRates:localStrain:) throws`.

The legacy implementation contract's importFile is now async. Apple SDK compilation is unavailable on Linux; no result should imply an Xcode build occurred.
