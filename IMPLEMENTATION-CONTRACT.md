# Shared implementation contract

New standalone iOS 17+ SwiftUI app, displayed name WHOOP, bundle identifier local.whoop.reconstruction. The original NOOP repository is out of scope. Exact official-app parity is NOT established. Original assets are permitted by the user's explicit same-brand request; no WHOOP credentials or private API calls.

`WHOOPCore` local Swift package at project root, Foundation only, Swift language mode5. Core owns these public Codable/Equatable/Sendable values:

- `HeartRateSample`: `timestamp: Date`, `bpm: Double`, init(timestamp:bpm:), Identifiable with timestamp id.
- `DataSource: String, Codable, Sendable`: cases `.example`, `.imported`; `title: String`.
- `DailySnapshot: Codable, Identifiable, Equatable, Sendable`: `date:Date`, `recovery:Int?`, `strain:Double?`, `sleepPerformance:Int?`, `sleepMinutes:Int`, `sleepNeededMinutes:Int`, `restingHeartRate:Double?`, `hrv:Double?`, `respiratoryRate:Double?`, `steps:Int`, `energyKcal:Double`, `heartRates:[HeartRateSample]`, `source:DataSource`; public init of all fields, computed id Date. UI uses these exact names.
- `JournalEntry: Codable, Equatable, Sendable`: `date:Date`, `caffeine:Bool`, `alcohol:Bool`, `lateMeal:Bool`, `note:String`; public initializer with defaults for all booleans false/note empty.
- `ActivityRecord: Codable, Identifiable, Equatable, Sendable`: `id:UUID`, `start:Date`, `durationMinutes:Int`, `name:String`, `strain:Double?`; public init defaults idUUID, strain nil.
- `ExampleData.days(endingOn: Date = Date()) -> [DailySnapshot]`: deterministic example week, ordered ascending date; WHOOP scores explicitly sample data.
- `ImportReader.read(_ data:Data, filename:String) throws -> [DailySnapshot]`: supported ISO8601 JSON day archive and timestamp/heart_rate CSV. Imported heart-rate-only data must leave recovery/sleep scores nil; do not invent medical scores. CSV semantics and validation documented. Max input10MB/100k rows. Preserve daily timezones consistently.
- Recovered local strain selected equation + all211 lookup constants: API can be chosen by core agent, but document units, selected path boundaries and divergences; test appropriately against retained static constants and edge cases. Don't claim complete WHOOP scoring parity.

Parent owns `AppStore.swift`, `DeviceModel.swift`, `WHOOPApp.swift`, brand wordmark shape and Xcode project/integration. UI agent owns `App/Views/` only and may use these parent interfaces:

`@MainActor final class AppStore: ObservableObject` supplied as EnvironmentObject:
- `@Published var tab: AppTab` enum home/health/community/profile/menu, parent enum conforms CaseIterable/Identifiable with `title` and `symbol`.
- `@Published var selectedDate:Date`; `var selectedDay:DailySnapshot` (always returns a selected day or empty day, never fabricated imported scores)
- `@Published private(set) var days:[DailySnapshot]`, `activities:[ActivityRecord]`
- `var isExampleMode:Bool`; `var currentJournal:JournalEntry`; `var dayActivities:[ActivityRecord]`
- `func moveDay(_ offset:Int)`, `func saveJournal(_ entry:JournalEntry)`, `func logActivity(name:String, minutes:Int)`, `func importFile(_ url:URL) throws`, `func restoreExamples()`, `func clearData() throws`.

`@MainActor final class DeviceModel: ObservableObject` supplied as EnvironmentObject:
- `@Published private(set) var devices:[NearbyDevice]` where NearbyDevice Identifiable {id:UUID,name:String,rssi:Int}
- `@Published private(set) var status:String`, `heartRate:Double?`, `isScanning:Bool`, `connectedName:String?`
- `func scan()`, `func stop()`, `func connect(_ device:NearbyDevice)`, `func disconnect()`.
- Discovery includes recovered WHOOP service UUIDs and standard Heart Rate0x180D; live HR support only standard0x2A37 broadcast. No custom handshake/history/scores claimed.

Parent generates `WhoopWordmark: View` from original vector path; `WhoopWordmark().frame(width:110,height:22)` works. Original fonts resource registration: DINPro-Regular / DINPro-Medium / DINPro-Bold (verify names if needed), ProximaNova-Regular. UI Theme agent can use font(.custom(...)); fallback system if unavailable.

UI: dark WHOOP visual language, original wordmark and typeface assets, Home/Health/Community/Profile/Menu destinations from static route findings. No unavailable online/community functions that look live. Example data visibly labelled on all score/detail screens. Functional date selection, score-detail sheets, HR charts, journal save/edit, activity recording, data import/share/reset, device scanning/connection page. All buttons route or act; offline community explains data availability with actual import CTA or local sessions. No password entry/login imitation. Use health/sleep missing states honestly. Views can call context-appropriate actions; no implementation jargon in product UI.
