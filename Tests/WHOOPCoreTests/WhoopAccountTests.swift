import XCTest
@testable import WHOOPCore

/// Synthetic values using independently retrieved v2 keys/IDs from the pinned
/// SDK README/conftest documented in Docs/AccountAPI/SOURCES.json. No network.
final class WhoopAccountTests: XCTestCase {
    private let sleepID = "5c060dd1-975d-4544-880c-3def81bdfb0d"
    private let workoutID = "a1b2c3d4-0000-4444-8888-1234567890ab"

    private func fixture() -> [String: Any] {
        ["profile": ["user_id": 12345, "first_name": "Test", "last_name": "User", "email": "unused@example.com"],
         "cycles": [["id": 111, "user_id": 12345, "start": "2026-04-24T02:25:44.774Z",
                      "end": "2026-04-25T02:00:00Z", "timezone_offset": "-05:00", "score_state": "SCORED",
                      "score": ["strain": 5.0, "kilojoule": 8000.0, "average_heart_rate": 60, "max_heart_rate": 140]]],
         "recoveries": [["cycle_id": 111, "sleep_id": sleepID, "user_id": 12345, "score_state": "SCORED",
                          "score": ["user_calibrating": false, "recovery_score": 50, "resting_heart_rate": 60,
                                    "hrv_rmssd_milli": 30.0, "spo2_percentage": 95.0, "skin_temp_celsius": 33.0]]],
         "sleeps": [["id": sleepID, "cycle_id": 111, "user_id": 12345, "nap": false,
                     "start": "2026-04-23T18:25:44.774Z", "end": "2026-04-24T02:25:44.774Z", "score_state": "SCORED",
                     "score": ["stage_summary": ["total_in_bed_time_milli": 28_800_000,
                                                   "total_awake_time_milli": 1_800_000, "total_no_data_time_milli": 0,
                                                   "total_light_sleep_time_milli": 14_400_000,
                                                   "total_slow_wave_sleep_time_milli": 7_200_000,
                                                   "total_rem_sleep_time_milli": 5_400_000],
                               "sleep_needed": ["baseline_milli": 28_800_000, "need_from_sleep_debt_milli": 3_600_000,
                                                "need_from_recent_strain_milli": 1_800_000, "need_from_recent_nap_milli": -1_800_000],
                               "respiratory_rate": 16.0, "sleep_performance_percentage": 90,
                               "sleep_consistency_percentage": 85, "sleep_efficiency_percentage": 93.75]]],
         "workouts": [["id": workoutID, "user_id": 12345, "sport_id": 0,
                       "start": "2026-04-24T15:00:00Z", "end": "2026-04-24T15:45:00Z", "score_state": "SCORED",
                       "score": ["strain": 8.0, "average_heart_rate": 120, "max_heart_rate": 150, "kilojoule": 1500.0]]]]
    }
    private func map(_ value: [String: Any]) throws -> WhoopAccountImport {
        try WhoopAccountMapper.map(JSONSerialization.data(withJSONObject: value))
    }
    private func record(_ payload: inout [String: Any], _ collection: String, _ edit: (inout [String: Any]) -> Void) {
        var values = payload[collection] as! [[String: Any]]
        edit(&values[0]); payload[collection] = values
    }
    private func score(_ payload: inout [String: Any], _ collection: String, _ key: String, _ value: Any) {
        record(&payload, collection) { row in
            var score = row["score"] as! [String: Any]; score[key] = value; row["score"] = score
        }
    }

    func testSleepStagesCannotExceedWallClockInterval() throws {
        var value = fixture()
        record(&value, "sleeps") { sleep in
            sleep["start"] = "2026-04-24T02:24:44.774Z"
            sleep["end"] = "2026-04-24T02:25:44.774Z"
        }
        XCTAssertThrowsError(try map(value))
    }

    func testMapsOfficialSuppliedScoresAndUnitsWithoutInventingHR() throws {
        let result = try map(fixture())
        XCTAssertEqual(result.displayName, "Test User")
        XCTAssertEqual(result.userID, 12345)
        let day = try XCTUnwrap(result.days.first)
        XCTAssertEqual(day.date, ISO8601DateFormatter().date(from: "2026-04-24T00:00:00Z"))
        XCTAssertEqual(day.source, .imported)
        XCTAssertEqual(day.recovery, 50); XCTAssertEqual(day.strain, 5)
        XCTAssertEqual(day.sleepPerformance, 90); XCTAssertEqual(day.sleepMinutes, 450)
        XCTAssertEqual(day.sleepNeededMinutes, 540) // signed nap credit, not subtraction of negative
        XCTAssertEqual(day.energyKcal, 8000 / 4.184, accuracy: 0.0001)
        XCTAssertEqual(day.restingHeartRate, 60); XCTAssertEqual(day.hrv, 30); XCTAssertEqual(day.respiratoryRate, 16)
        XCTAssertEqual(day.steps, 0); XCTAssertTrue(day.heartRates.isEmpty)
        let activity = try XCTUnwrap(result.activities.first)
        XCTAssertEqual(activity.id, UUID(uuidString: workoutID)); XCTAssertEqual(activity.strain, 8)
        XCTAssertEqual(activity.durationMinutes, 45); XCTAssertEqual(activity.strainIsEstimate, false)
    }

    func testStableWorkoutIdentityMakesRepeatedImportsIdempotent() throws {
        XCTAssertEqual(try map(fixture()).activities, try map(fixture()).activities)
    }

    func testPendingAndUnscorableDoNotBecomeZeroScores() throws {
        var payload = fixture()
        for collection in ["cycles", "recoveries", "sleeps", "workouts"] {
            record(&payload, collection) { row in row["score_state"] = "PENDING_SCORE"; row["score"] = NSNull() }
        }
        let result = try map(payload), day = try XCTUnwrap(result.days.first)
        XCTAssertNil(day.recovery); XCTAssertNil(day.strain); XCTAssertNil(day.sleepPerformance)
        XCTAssertNil(day.hrv); XCTAssertNil(result.activities.first?.strain)
        record(&payload, "cycles") { $0["score_state"] = "UNSCORABLE" }
        XCTAssertNoThrow(try map(payload))
    }

    func testUnknownAndInconsistentStatesAreRejected() {
        for state in ["scored", "DELETED", "PENDING_SCORE"] {
            var payload = fixture(); record(&payload, "cycles") { $0["score_state"] = state }
            XCTAssertThrowsError(try map(payload))
        }
        var payload = fixture(); record(&payload, "recoveries") { $0["score"] = NSNull() }
        XCTAssertThrowsError(try map(payload))
    }

    func testSleepJoinsBothCycleAndRecoveryIdentity() {
        var payload = fixture(); record(&payload, "sleeps") { $0["cycle_id"] = 112 }
        XCTAssertThrowsError(try map(payload))
        payload = fixture(); record(&payload, "sleeps") { $0["nap"] = true }
        XCTAssertThrowsError(try map(payload))
    }

    func testMissingReferencedSleepDoesNotUseNearbySleep() throws {
        var payload = fixture()
        record(&payload, "recoveries") { $0["sleep_id"] = "00000000-0000-4000-8000-000000000001" }
        let day = try XCTUnwrap(map(payload).days.first)
        XCTAssertEqual(day.recovery, 50); XCTAssertNil(day.sleepPerformance); XCTAssertEqual(day.sleepMinutes, 0)
    }

    func testMainSleepUsesCycleIDWhenRecoveryMissing() throws {
        var payload = fixture(); payload["recoveries"] = []
        let day = try XCTUnwrap(map(payload).days.first)
        XCTAssertNil(day.recovery); XCTAssertEqual(day.sleepPerformance, 90)
        record(&payload, "sleeps") { $0["nap"] = true }
        XCTAssertNil(try map(payload).days.first?.sleepPerformance)
    }

    func testDuplicateIdentitiesAndCrossAccountRecordsAreRejected() {
        for collection in ["cycles", "recoveries", "sleeps", "workouts"] {
            var payload = fixture(); let rows = payload[collection] as! [[String: Any]]; payload[collection] = rows + rows
            XCTAssertThrowsError(try map(payload), collection)
            payload = fixture(); record(&payload, collection) { $0["user_id"] = 999 }
            XCTAssertThrowsError(try map(payload), collection)
        }
    }

    func testMultipleCyclesOnSameUTCDateFailAtomically() {
        var payload = fixture(), rows = payload["cycles"] as! [[String: Any]]
        var second = rows[0]; second["id"] = 112; second["start"] = "2026-04-24T20:00:00Z"
        rows.append(second); payload["cycles"] = rows
        XCTAssertThrowsError(try map(payload))
    }

    func testUTCGroupingUsesTimestampOffsetRatherThanDeviceTimezone() throws {
        var payload = fixture()
        record(&payload, "cycles") { $0["start"] = "2026-04-24T00:15:00+04:00" }
        XCTAssertEqual(try map(payload).days.first?.date, ISO8601DateFormatter().date(from: "2026-04-23T00:00:00Z"))
    }

    func testInvalidBoundsDatesAndIDsAreRejected() {
        for (collection, key, value) in [("cycles", "strain", -0.1), ("cycles", "strain", 21.1),
                                         ("cycles", "kilojoule", 418_401.0), ("recoveries", "recovery_score", 101.0),
                                         ("recoveries", "resting_heart_rate", 0.0), ("recoveries", "hrv_rmssd_milli", 1001.0),
                                         ("sleeps", "sleep_performance_percentage", 101.0), ("workouts", "strain", 22.0)] {
            var payload = fixture(); score(&payload, collection, key, value); XCTAssertThrowsError(try map(payload), key)
        }
        var payload = fixture(); record(&payload, "workouts") { $0["id"] = "123" }; XCTAssertThrowsError(try map(payload))
        payload = fixture(); record(&payload, "cycles") { $0["id"] = -1 }; XCTAssertThrowsError(try map(payload))
        payload = fixture(); record(&payload, "sleeps") { $0["end"] = "nonsense" }; XCTAssertThrowsError(try map(payload))
        payload = fixture(); record(&payload, "workouts") { $0["end"] = "2026-04-24T14:00:00Z" }; XCTAssertThrowsError(try map(payload))
    }

    func testNonfiniteJSONAndOversizedPayloadAreRejected() {
        let valid = String(data: try! JSONSerialization.data(withJSONObject: fixture()), encoding: .utf8)!
        XCTAssertThrowsError(try WhoopAccountMapper.map(Data(valid.replacingOccurrences(of: "8000", with: "1e9999").utf8)))
        XCTAssertThrowsError(try WhoopAccountMapper.map(Data(repeating: 32, count: 16 * 1_024 * 1_024 + 1)))
    }

    func testInvalidSleepComponentsCannotInventTime() {
        var payload = fixture()
        record(&payload, "sleeps") { row in
            var score = row["score"] as! [String: Any], stage = score["stage_summary"] as! [String: Any]
            stage["total_in_bed_time_milli"] = 1; score["stage_summary"] = stage; row["score"] = score
        }
        XCTAssertThrowsError(try map(payload))
        payload = fixture()
        record(&payload, "sleeps") { row in
            var score = row["score"] as! [String: Any], need = score["sleep_needed"] as! [String: Any]
            need["need_from_recent_nap_milli"] = -86_400_000; score["sleep_needed"] = need; row["score"] = score
        }
        XCTAssertThrowsError(try map(payload))
    }
}
