import XCTest
@testable import WHOOPCore

final class MeasurementExportTests: XCTestCase {
    private func date(_ text: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: text))
    }
    private func day(_ number: Int = 8) throws -> DailySnapshot {
        var value = DailySnapshot.empty(on: try date("2026-11-\(number < 10 ? "0" : "")\(number)T00:00:00Z"))
        value.recovery = 38; value.strain = 15.8; value.sleepPerformance = 33
        value.sleepMinutes = 224; value.sleepNeededMinutes = 480
        value.restingHeartRate = 58; value.hrv = 122.75; value.respiratoryRate = 19.7
        value.steps = 26_783; value.energyKcal = 2_886.5
        return value
    }

    func testJSONExcludesExamplesAndRoundTripsRealValuesAndFractionalSamples() throws {
        var real = try day()
        real.heartRates = [.init(timestamp: real.date.addingTimeInterval(100.125), bpm: 98)]
        var example = try day(7); example.source = .example
        let file = try MeasurementExport.make(days: [real, example], format: .json)
        XCTAssertEqual(try ImportReader.read(file.data, filename: file.filename), [real])
        XCTAssertEqual(file.dayCount, 1); XCTAssertEqual(file.heartRateCount, 1)
        XCTAssertEqual(file.filename, "WHOOP-saved-measurements-2026-11-08-to-2026-11-08.json")
    }

    func testExamplesAndEmptyInputNeverProduceAnExport() throws {
        var example = try day(); example.source = .example
        for format in MeasurementExportFormat.allCases {
            for days in [[], [example]] {
                XCTAssertThrowsError(try MeasurementExport.make(days: days, format: format)) {
                    XCTAssertEqual($0 as? MeasurementExportError, .noSavedDays)
                }
            }
        }
    }

    func testInclusiveUTCDayRangeAcrossMidnightAndOffset() throws {
        let days = try [day(7), day(8), day(9), day(10)]
        let range = try date("2026-11-08T23:00:00Z")...date("2026-11-09T01:00:00Z")
        let file = try MeasurementExport.make(days: days.reversed(), format: .json, range: range)
        XCTAssertEqual(try ImportReader.read(file.data, filename: file.filename), Array(days[1...2]))
        let sameUTCDate = try date("2026-11-08T03:00:00Z")...date("2026-11-09T01:00:00+04:00")
        XCTAssertEqual(try MeasurementExport.selectedDays(days, range: sameUTCDate), [days[1]])
    }

    func testDailyCSVRetainsUnitsAndLeavesUnavailableScoresEmpty() throws {
        var real = try day(); real.recovery = nil; real.restingHeartRate = nil
        let file = try MeasurementExport.make(days: [real], format: .dailyCSV)
        let text = try XCTUnwrap(String(data: file.data, encoding: .utf8))
        let rows = text.components(separatedBy: "\r\n")
        let columns = rows[1].components(separatedBy: ",")
        XCTAssertTrue(rows[0].contains("hrv_rmssd_ms"))
        XCTAssertEqual(columns, ["2026-11-08", "", "15.8", "33", "224", "480", "", "122.75", "19.7", "26783", "2886.5", "0", "imported"])
        XCTAssertTrue(text.hasSuffix("\r\n"))
    }

    func testHeartRateCSVIsSortedDeduplicatedAndCanBeImportedAgain() throws {
        var real = try day()
        let first = HeartRateSample(timestamp: real.date.addingTimeInterval(1.125), bpm: 72)
        let second = HeartRateSample(timestamp: real.date.addingTimeInterval(2.875), bpm: 98)
        real.heartRates = [second, first, first]
        let file = try MeasurementExport.make(days: [real], format: .heartRateCSV)
        let restored = try ImportReader.read(file.data, filename: file.filename)
        XCTAssertEqual(restored[0].heartRates, [first, second])
        XCTAssertEqual(file.heartRateCount, 2)
        XCTAssertEqual(String(data: file.data, encoding: .utf8)?.components(separatedBy: "\r\n").first, "timestamp,heart_rate")
    }

    func testHeartRateCSVNeverSynthesizesATraceFromSummaryMeasurements() throws {
        let real = try day()
        XCTAssertThrowsError(try MeasurementExport.make(days: [real], format: .heartRateCSV)) {
            XCTAssertEqual($0 as? MeasurementExportError, .noHeartRates)
        }
        XCTAssertNoThrow(try MeasurementExport.make(days: [real], format: .json))
        XCTAssertNoThrow(try MeasurementExport.make(days: [real], format: .dailyCSV))
    }

    func testInvalidMetricsRejectEveryExportFormat() throws {
        var invalid = try day(); invalid.strain = 22
        for format in MeasurementExportFormat.allCases {
            XCTAssertThrowsError(try MeasurementExport.make(days: [invalid], format: format))
        }
        invalid = try day(); invalid.energyKcal = .nan
        XCTAssertThrowsError(try MeasurementExport.make(days: [invalid], format: .json))
    }

    func testConflictingSamplesAndDuplicateDatesFailInsteadOfDroppingData() throws {
        var invalid = try day()
        let timestamp = invalid.date.addingTimeInterval(60)
        invalid.heartRates = [.init(timestamp: timestamp, bpm: 70), .init(timestamp: timestamp, bpm: 80)]
        XCTAssertThrowsError(try MeasurementExport.make(days: [invalid], format: .json))
        let same = try day()
        XCTAssertThrowsError(try MeasurementExport.make(days: [same, same], format: .dailyCSV))
    }

    func testOutOfDayHeartRateSamplesFail() throws {
        var invalid = try day()
        invalid.heartRates = [.init(timestamp: invalid.date.addingTimeInterval(86_400), bpm: 98)]
        XCTAssertThrowsError(try MeasurementExport.make(days: [invalid], format: .heartRateCSV))
    }

    func testInvalidDatesFailBeforeFormatting() throws {
        var invalid = try day(); invalid.date = Date(timeIntervalSince1970: .infinity)
        XCTAssertThrowsError(try MeasurementExport.make(days: [invalid], format: .json)) {
            XCTAssertEqual($0 as? MeasurementExportError, .invalidDate)
        }
        invalid = try day()
        invalid.heartRates = [.init(timestamp: Date(timeIntervalSince1970: .nan), bpm: 98)]
        XCTAssertThrowsError(try MeasurementExport.make(days: [invalid], format: .heartRateCSV)) {
            XCTAssertEqual($0 as? MeasurementExportError, .invalidDate)
        }
    }

    func testRecordBudgetIsCheckedBeforeSerialization() throws {
        var real = try day()
        real.heartRates = Array(repeating: .init(timestamp: real.date, bpm: 72), count: ImportReader.maximumRows + 1)
        XCTAssertThrowsError(try MeasurementExport.make(days: [real], format: .json)) {
            XCTAssertEqual($0 as? MeasurementExportError, .tooLarge)
        }
    }

    func testJSONAddsHighlightsMetadataButNoUnrelatedAppState() throws {
        let file = try MeasurementExport.make(days: [day()], format: .json)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: file.data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["days", "highlights", "metadata"])
        XCTAssertFalse(LocalBackupCodec.isBackup(file.data))
    }

    func testEmptyRangeDoesNotFallBackToAllData() throws {
        let range = try date("2026-12-01T00:00:00Z")...date("2026-12-03T00:00:00Z")
        XCTAssertThrowsError(try MeasurementExport.make(days: [day()], format: .json, range: range)) {
            XCTAssertEqual($0 as? MeasurementExportError, .noSavedDays)
        }
    }
}

final class ProfilePersonalizationTests: XCTestCase {
    private let today = Date(timeIntervalSince1970: 1_794_268_800)
    private func day(_ offset: Int, recovery: Int = 80, strain: Double = 12, sleep: Int = 88) -> DailySnapshot {
        var value = DailySnapshot.empty(on: today.addingTimeInterval(Double(offset) * 86_400))
        value.recovery = recovery; value.strain = strain; value.sleepPerformance = sleep
        value.sleepMinutes = 420; value.restingHeartRate = 58; value.hrv = 120
        return value
    }
    func testAgeHasNoNumericUpperLimitAndKeepsExactDecimalText() throws {
        let huge = String(repeating: "9", count: 500) + ".123456789123456789"
        let profile = try ProfilePersonalization(age: huge, whoopAge: "1000000000000000000000.5").validated()
        XCTAssertEqual(profile.age, huge)
        XCTAssertEqual(profile.whoopAge, "1000000000000000000000.5")
        XCTAssertEqual(try ProfilePersonalization(age: " 00022,600 ", whoopAge: ".500").validated().age, "22.6")
        XCTAssertEqual(try ProfilePersonalization(age: "0", whoopAge: ".500").validated().whoopAge, "0.5")
    }
    func testInvalidAgesAndNegativeChosenStreakAreRejected() {
        for value in ["-1", "NaN", "inf", "22..6", "hello", ".", "2e5"] {
            XCTAssertThrowsError(try ProfilePersonalization(age: value).validated())
            XCTAssertThrowsError(try ProfilePersonalization(whoopAge: value).validated())
        }
        XCTAssertThrowsError(try ProfilePersonalization(dayStreakOverride: -1).validated())
        XCTAssertNoThrow(try ProfilePersonalization(dayStreakOverride: Int.max).validated())
    }
    func testNamesAreNormalizedAndInitialsFollowPersonalization() throws {
        let profile = try ProfilePersonalization(displayName: " Abdullah Almaeeni ", username: " @l7keq ").validated()
        XCTAssertEqual(profile.displayName, "Abdullah Almaeeni"); XCTAssertEqual(profile.username, "l7keq")
        XCTAssertEqual(profile.initials(), "AA")
        XCTAssertEqual(ProfilePersonalization(displayName: "Pulse").initials(), "PU")
        XCTAssertThrowsError(try ProfilePersonalization(displayName: "unsafe\nname").validated())
    }
    func testHighlightsMatchSavedValuesAndTieDatesAreDeterministic() {
        var first = day(-2, recovery: 96, strain: 10.7, sleep: 88)
        first.restingHeartRate = 50; first.hrv = 48; first.sleepMinutes = 717
        first.heartRates = [.init(timestamp: first.date.addingTimeInterval(5), bpm: 190)]
        var second = day(-1, recovery: 75, strain: 15.8, sleep: 70)
        second.restingHeartRate = 77; second.hrv = 139
        let result = ProfileHighlightsCalculator.calculate(days: [second, first, day(0, recovery: 9)], asOf: today)
        XCTAssertEqual(result.bestSleepPerformance?.value, 88)
        XCTAssertEqual(result.peakRecovery?.value, 96)
        XCTAssertEqual(result.peakStrain?.value, 15.8)
        XCTAssertEqual(result.lowestRecovery?.value, 9)
        XCTAssertEqual(result.lowestRestingHeartRate?.value, 50)
        XCTAssertEqual(result.highestRestingHeartRate?.value, 77)
        XCTAssertEqual(result.lowestHRV?.value, 48); XCTAssertEqual(result.highestHRV?.value, 139)
        XCTAssertEqual(result.maxHeartRate?.value, 190); XCTAssertEqual(result.longestSleepMinutes?.value, 717)
        XCTAssertEqual(result.bestSleepPerformance?.date, first.date)
    }
    func testMissingDatesAndThresholdFailuresBreakStreaks() {
        let days = [day(-4), day(-3), day(-1), day(0, recovery: 66, strain: 9.9, sleep: 69)]
        let value = ProfileHighlightsCalculator.calculate(days: days, asOf: today)
        XCTAssertEqual(value.currentLoggedDayStreak, 2); XCTAssertEqual(value.longestLoggedDayStreak, 2)
        XCTAssertEqual(value.longestGreenRecoveryStreak, 2)
        XCTAssertEqual(value.longestSleep70Streak, 2); XCTAssertEqual(value.longestStrain10Streak, 2)
        XCTAssertEqual(ProfileHighlightsCalculator.calculate(days: [day(-4), day(-3)], asOf: today).currentLoggedDayStreak, 0)
        XCTAssertEqual(ProfileHighlightsCalculator.calculate(days: [day(-2), day(-1)], asOf: today).currentLoggedDayStreak, 2)
    }
    func testExamplesFutureRowsEmptyDaysAndDuplicateDatesDoNotInflateStreaks() {
        var example = day(-2, recovery: 100, strain: 21, sleep: 100); example.source = .example
        let current = day(-1)
        let value = ProfileHighlightsCalculator.calculate(days: [example, day(1, recovery: 100, strain: 21, sleep: 100), current, current, .empty(on: today)], asOf: today)
        XCTAssertEqual(value.savedDays, 1); XCTAssertEqual(value.longestLoggedDayStreak, 1)
        XCTAssertEqual(value.currentLoggedDayStreak, 1)
        XCTAssertEqual(value.peakRecovery?.value, 80); XCTAssertEqual(value.peakStrain?.value, 12)
    }
    func testChosenProfileValuesNeverReplaceCalculatedRecords() throws {
        let profile = ProfilePersonalization(age: "250", whoopAge: "999.9", dayStreakOverride: 9999)
        let file = try MeasurementExport.make(days: [day(-1)], format: .json, profile: profile, asOf: today)
        let decoded = try ImportReader.jsonDecoder().decode(PersonalizedMeasurementArchive.self, from: file.data)
        XCTAssertEqual(decoded.profile?.dayStreakOverride, 9999)
        XCTAssertEqual(decoded.highlights.currentLoggedDayStreak, 1)
        XCTAssertEqual(decoded.highlights.peakRecovery?.value, 80)
        XCTAssertEqual(decoded.metadata.profileSource, "user_configured")
        XCTAssertFalse(decoded.metadata.includesExamples)
        XCTAssertFalse(LocalBackupCodec.isBackup(file.data))
    }
    func testProfileAndHighlightsExportHonorSelectedRange() throws {
        let file = try MeasurementExport.make(days: [day(-4, recovery: 99), day(-1, recovery: 70)], format: .json,
                                             range: day(-1).date...today, profile: ProfilePersonalization(age: "18"), asOf: today)
        let value = try ImportReader.jsonDecoder().decode(PersonalizedMeasurementArchive.self, from: file.data)
        XCTAssertEqual(value.days.count, 1); XCTAssertEqual(value.highlights.peakRecovery?.value, 70)
    }
    func testProfileOnlyExportAndReimportPreserveUnlimitedAge() throws {
        let profile = try ProfilePersonalization(displayName: "Abdullah", age: String(repeating: "9", count: 200), whoopAge: "22.6", dayStreakOverride: 41).validated()
        let file = try MeasurementExport.make(days: [], format: .json, profile: profile, asOf: today)
        let result = try MeasurementExport.readImport(file.data, filename: file.filename)
        XCTAssertTrue(result.days.isEmpty); XCTAssertEqual(result.profile, profile)
        let decoded = try ImportReader.jsonDecoder().decode(PersonalizedMeasurementArchive.self, from: file.data)
        XCTAssertNil(decoded.highlights.peakStrain); XCTAssertEqual(decoded.highlights.savedDays, 0)
    }
    func testPersonalizedArchiveReimportValidatesProfileAndIgnoresTamperedHighlights() throws {
        let file = try MeasurementExport.make(days: [day(-1)], format: .json, profile: ProfilePersonalization(age: "18"), asOf: today)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: file.data) as? [String: Any])
        object["highlights"] = ["peakRecovery": ["value": 999, "date": "nonsense"]]
        let result = try MeasurementExport.readImport(JSONSerialization.data(withJSONObject: object), filename: "profile.json")
        XCTAssertEqual(ProfileHighlightsCalculator.calculate(days: result.days, asOf: today).peakRecovery?.value, 80)
        object["profile"] = ["displayName": "A", "username": "", "age": "-1", "whoopAge": "", "dayStreakOverride": 41]
        XCTAssertThrowsError(try MeasurementExport.readImport(JSONSerialization.data(withJSONObject: object), filename: "profile.json"))
    }
    func testLegacyDayJSONAndHeartRateCSVStillImport() throws {
        let data = try ImportReader.jsonEncoder().encode(DayArchive(days: [day(-1)]))
        XCTAssertEqual(try MeasurementExport.readImport(data, filename: "legacy.json").days.count, 1)
        let csv = Data("timestamp,heart_rate\n2026-11-08T08:00:00Z,72\n".utf8)
        XCTAssertEqual(try MeasurementExport.readImport(csv, filename: "heart.csv").days.first?.heartRates.first?.bpm, 72)
    }
    func testHighlightsCSVIncludesCustomValuesUnitsDatesAndNeutralizesFormulas() throws {
        let profile = ProfilePersonalization(displayName: "=SUM(1,2)", age: "9999.5", whoopAge: "22.6", dayStreakOverride: 41)
        let file = try MeasurementExport.make(days: [day(-1)], format: .highlightsCSV, profile: profile, asOf: today)
        let text = try XCTUnwrap(String(data: file.data, encoding: .utf8))
        XCTAssertTrue(text.contains("\"'=SUM(1,2)\""))
        XCTAssertTrue(text.contains("whoop_age,22.6,years_display_text"))
        XCTAssertTrue(text.contains("day_streak_override,41,days"))
        XCTAssertTrue(text.contains("peak_recovery,80.0,percent"))
        XCTAssertTrue(text.contains("max_strain,12.0,0_to_21"))
        XCTAssertTrue(text.contains("current_logged_day_streak,1,days"))
    }
    func testFullBackupPreservesProfileAndLegacyBackupWithoutProfileStillWorks() throws {
        let profile = ProfilePersonalization(age: "99999999.5", dayStreakOverride: 41)
        let backup = LocalBackup(selectedDate: today, days: [day(-1)], journal: [], activities: [], profile: profile)
        let data = try LocalBackupCodec.encode(backup)
        XCTAssertEqual(try LocalBackupCodec.decode(data).profile, profile)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]); object.removeValue(forKey: "profile")
        XCTAssertNil(try LocalBackupCodec.decode(JSONSerialization.data(withJSONObject: object)).profile)
        var invalid = backup; invalid.profile?.dayStreakOverride = -1
        XCTAssertThrowsError(try LocalBackupCodec.encode(invalid))
    }
}
