import Foundation
import XCTest
@testable import WHOOPCore

final class BackupTests: XCTestCase {
    func testAccountIdentityRoundtripAndLegacyAbsence() throws {
        let backup = LocalBackup(selectedDate: Date(timeIntervalSince1970: 1_700_000_000), days: [], journal: [], activities: [], whoopAccountUserID: 12345)
        let encoded = try LocalBackupCodec.encode(backup)
        XCTAssertEqual(try LocalBackupCodec.decode(encoded).whoopAccountUserID, 12345)
        var legacy = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        legacy.removeValue(forKey: "whoopAccountUserID")
        XCTAssertNil(try LocalBackupCodec.decode(JSONSerialization.data(withJSONObject: legacy)).whoopAccountUserID)
        var invalid = backup; invalid.whoopAccountUserID = -1
        XCTAssertThrowsError(try LocalBackupCodec.encode(invalid))
    }

    private let date = DayCalendar.start(of: Date(timeIntervalSince1970: 1_793_491_200))

    private func fixture() -> LocalBackup {
        var day = DailySnapshot.empty(on: date, source: .example)
        day.recovery = 87; day.strain = 12.4; day.sleepPerformance = 92
        day.sleepMinutes = 423; day.sleepNeededMinutes = 460
        day.restingHeartRate = 49.5; day.hrv = 82.3; day.respiratoryRate = 14.2
        day.steps = 8731; day.energyKcal = 2098.5
        day.heartRates = [.init(timestamp: date.addingTimeInterval(28_800.125), bpm: 72),
                         .init(timestamp: date.addingTimeInterval(28_800.875), bpm: 91.5)]
        let journal = JournalEntry(date: date.addingTimeInterval(0.125), caffeine: true,
                                   alcohol: true, lateMeal: true, note: "Café ☕️\nSleep: 良い — \"rested\"")
        let activity = ActivityRecord(id: UUID(uuidString: "F16B9A59-9A72-4B67-98A6-395BF90D0B92")!,
                                      start: date.addingTimeInterval(43_200.875),
                                      durationMinutes: 47, name: "Trail run 🏃", strain: 9.3,
                                      strainIsEstimate: true)
        return LocalBackup(exportedAt: date.addingTimeInterval(50_000.125),
                           selectedDate: date.addingTimeInterval(0.875), days: [day],
                           journal: [journal], activities: [activity])
    }

    private func rawData(_ backup: LocalBackup) throws -> Data {
        try ImportReader.jsonEncoder().encode(backup)
    }

    private func assertRejected(_ backup: LocalBackup, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertThrowsError(try LocalBackupCodec.encode(backup), file: file, line: line)
        XCTAssertThrowsError(try LocalBackupCodec.decode(rawData(backup)), file: file, line: line)
    }

    func testCompleteRoundTripPreservesAllFieldsAndMilliseconds() throws {
        var original = fixture()
        original.days.append(.empty(on: date.addingTimeInterval(86_400), source: .imported))
        let data = try LocalBackupCodec.encode(original)
        XCTAssertTrue(LocalBackupCodec.isBackup(data))
        XCTAssertEqual(try LocalBackupCodec.decode(data), original)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("WHOOP_LOCAL_BACKUP"))
        XCTAssertTrue(text.contains(".125Z"))
        XCTAssertTrue(text.contains(".875Z"))
    }

    func testEmptyBackupIsValidAndRetainsSelection() throws {
        let empty = LocalBackup(exportedAt: date, selectedDate: date, days: [], journal: [], activities: [])
        XCTAssertEqual(try LocalBackupCodec.decode(LocalBackupCodec.encode(empty)), empty)
    }

    func testWrongMagicAndFutureVersionRejectWithoutDayFallback() throws {
        var value = fixture(); value.format = "ANOTHER_BACKUP"
        XCTAssertTrue(LocalBackupCodec.isBackup(try rawData(value)))
        try assertRejected(value)
        value = fixture(); value.version = 2
        XCTAssertThrowsError(try LocalBackupCodec.decode(rawData(value))) {
            XCTAssertEqual($0 as? LocalBackupError, .unsupportedVersion(2))
        }
        value.version = 0; try assertRejected(value)
    }

    func testRoutingRecognizesDamagedEnvelopesAndLeavesDayArchivesAlone() throws {
        for json in ["{\"format\":null,\"days\":[]}", "{\"version\":2,\"days\":[]}",
                     "{\"journal\":[],\"days\":[]}", "{\"activities\":[],\"days\":[]}"] {
            let data = Data(json.utf8)
            XCTAssertTrue(LocalBackupCodec.isBackup(data))
            XCTAssertThrowsError(try LocalBackupCodec.decode(data))
        }
        XCTAssertFalse(LocalBackupCodec.isBackup(try ImportReader.jsonEncoder().encode(DayArchive(days: fixture().days))))
        XCTAssertFalse(LocalBackupCodec.isBackup(Data("[]".utf8)))
        XCTAssertFalse(LocalBackupCodec.isBackup(Data("{broken".utf8)))
    }

    func testMissingRequiredEnvelopeFieldsAndMalformedUUIDReject() throws {
        let data = try rawData(fixture())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["format", "version", "exportedAt", "selectedDate", "days", "journal", "activities"] {
            var damaged = object; damaged.removeValue(forKey: key)
            XCTAssertThrowsError(try LocalBackupCodec.decode(JSONSerialization.data(withJSONObject: damaged)))
        }
        var damaged = object
        var activities = try XCTUnwrap(damaged["activities"] as? [[String: Any]])
        activities[0]["id"] = "invalid UUID"; damaged["activities"] = activities
        XCTAssertThrowsError(try LocalBackupCodec.decode(JSONSerialization.data(withJSONObject: damaged)))
        damaged = object; damaged["selectedDate"] = "2026-11-08T00:00:00"
        XCTAssertThrowsError(try LocalBackupCodec.decode(JSONSerialization.data(withJSONObject: damaged)))
    }

    func testDailyAndJournalDaysAreUniqueInUTC() throws {
        var value = fixture(); value.days.append(value.days[0]); try assertRejected(value)
        value = fixture(); value.days[0].date = date.addingTimeInterval(3_600); try assertRejected(value)
        value = fixture(); value.journal.append(.init(date: date.addingTimeInterval(86_399)))
        try assertRejected(value)
        value = fixture(); value.journal.append(.init(date: date.addingTimeInterval(86_400)))
        XCTAssertNoThrow(try LocalBackupCodec.encode(value))
    }

    func testHeartRateConflictsAndWrongDayRejectWholeBackup() throws {
        var value = fixture(); value.days[0].heartRates.append(value.days[0].heartRates[0]); try assertRejected(value)
        value = fixture()
        value.days[0].heartRates.append(.init(timestamp: value.days[0].heartRates[0].timestamp, bpm: 100))
        try assertRejected(value)
        value = fixture(); value.days[0].heartRates[0].timestamp = date.addingTimeInterval(86_400)
        try assertRejected(value)
        for rate in [0.0, -1, 300.01] {
            value = fixture(); value.days[0].heartRates[0].bpm = rate; try assertRejected(value)
        }
    }

    func testEveryDailyMetricRangeIsValidated() throws {
        let invalidChanges: [(inout DailySnapshot) -> Void] = [
            { $0.recovery = -1 }, { $0.recovery = 101 }, { $0.sleepPerformance = 101 },
            { $0.strain = -0.1 }, { $0.strain = 21.1 }, { $0.sleepMinutes = -1 },
            { $0.sleepNeededMinutes = 1441 }, { $0.restingHeartRate = 0 },
            { $0.hrv = 1001 }, { $0.respiratoryRate = 101 }, { $0.steps = -1 },
            { $0.steps = 1_000_001 }, { $0.energyKcal = -1 }, { $0.energyKcal = 100_001 }
        ]
        for change in invalidChanges {
            var value = fixture(); change(&value.days[0]); try assertRejected(value)
        }
    }

    func testNonfiniteValuesAndUnrepresentableDatesCannotBeExported() {
        let mutations: [(inout LocalBackup) -> Void] = [
            { $0.exportedAt = Date(timeIntervalSince1970: .infinity) },
            { $0.selectedDate = Date(timeIntervalSince1970: .nan) },
            { $0.selectedDate = Date(timeIntervalSince1970: 253_402_300_800) },
            { $0.days[0].date = Date(timeIntervalSince1970: -.infinity) },
            { $0.days[0].strain = .nan }, { $0.days[0].restingHeartRate = .infinity },
            { $0.days[0].hrv = .nan }, { $0.days[0].respiratoryRate = -.infinity },
            { $0.days[0].energyKcal = .nan }, { $0.days[0].heartRates[0].bpm = .infinity },
            { $0.days[0].heartRates[0].timestamp = Date(timeIntervalSince1970: .nan) },
            { $0.journal[0].date = Date(timeIntervalSince1970: .infinity) },
            { $0.activities[0].start = Date(timeIntervalSince1970: .nan) },
            { $0.activities[0].strain = .infinity }
        ]
        for mutate in mutations {
            var value = fixture(); mutate(&value)
            XCTAssertThrowsError(try LocalBackupCodec.encode(value))
        }
    }

    func testActivityIdentifiersNamesDurationAndStrainAreValidated() throws {
        var value = fixture(); value.activities.append(value.activities[0]); try assertRejected(value)
        for name in ["", " \n\t", String(repeating: "a", count: 81)] {
            value = fixture(); value.activities[0].name = name; try assertRejected(value)
        }
        for duration in [0, -1, 1441] {
            value = fixture(); value.activities[0].durationMinutes = duration; try assertRejected(value)
        }
        for strain in [-0.1, 21.1] {
            value = fixture(); value.activities[0].strain = strain; try assertRejected(value)
        }
        value = fixture(); value.activities[0].strain = nil
        value.activities[0].name = String(repeating: "a", count: 80)
        value.activities[0].durationMinutes = 1440
        XCTAssertNoThrow(try LocalBackupCodec.encode(value))
    }

    func testJournalNoteAndEntryLimits() throws {
        var value = fixture(); value.journal[0].note = String(repeating: "é", count: 20_000)
        XCTAssertEqual(try LocalBackupCodec.decode(LocalBackupCodec.encode(value)), value)
        value.journal[0].note.append("x"); try assertRejected(value)
        value = fixture(); value.journal = Array(repeating: value.journal[0], count: 10_001)
        try assertRejected(value)
    }

    func testCombinedRecordLimitIncludesHeartRatesJournalAndActivities() throws {
        var value = fixture()
        value.days[0].heartRates = Array(repeating: value.days[0].heartRates[0], count: 99_998)
        // 1 day + 99,998 samples + 1 journal entry + 1 activity = 100,001.
        XCTAssertThrowsError(try LocalBackupCodec.encode(value)) {
            XCTAssertEqual($0 as? LocalBackupError, .tooManyRows)
        }
        XCTAssertThrowsError(try LocalBackupCodec.decode(rawData(value))) {
            XCTAssertEqual($0 as? LocalBackupError, .tooManyRows)
        }
    }

    func testByteLimitAndBackupLargerThanDayImportLimit() throws {
        XCTAssertThrowsError(try LocalBackupCodec.decode(Data(repeating: 32, count: LocalBackupCodec.maximumBytes + 1))) {
            XCTAssertEqual($0 as? LocalBackupError, .tooLarge)
        }
        var value = fixture()
        let note = String(repeating: "x", count: 20_000)
        value.journal = (0..<600).map { .init(date: date.addingTimeInterval(Double($0) * 86_400), note: note) }
        let largeValid = try LocalBackupCodec.encode(value)
        XCTAssertGreaterThan(largeValid.count, ImportReader.maximumBytes)
        XCTAssertEqual(try LocalBackupCodec.decode(largeValid), value)
        value.journal = (0..<1100).map { .init(date: date.addingTimeInterval(Double($0) * 86_400), note: note) }
        XCTAssertThrowsError(try LocalBackupCodec.encode(value)) {
            XCTAssertEqual($0 as? LocalBackupError, .tooLarge)
        }
    }
}
