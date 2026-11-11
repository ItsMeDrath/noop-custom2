import Foundation

public struct WhoopAccountImport: Sendable {
    public let days: [DailySnapshot]
    public let activities: [ActivityRecord]
    public let displayName: String?
    public let userID: Int64
    public init(days: [DailySnapshot], activities: [ActivityRecord], displayName: String?, userID: Int64 = 0) {
        self.days = days; self.activities = activities; self.displayName = displayName; self.userID = userID
    }
}

public enum WhoopAccountError: LocalizedError {
    case invalidData(String)
    public var errorDescription: String? {
        switch self { case .invalidData(let reason): return "WHOOP account data could not be imported: \(reason)" }
    }
}

/// Maps the public v2 response shape. Cycle start's UTC date is this archive's day.
/// A second cycle on that UTC date is rejected rather than silently losing scores.
public enum WhoopAccountMapper {
    public static func map(_ data: Data) throws -> WhoopAccountImport {
        guard data.count <= 16 * 1_024 * 1_024 else { throw invalid("the response is too large.") }
        let payload: Payload
        do { payload = try JSONDecoder().decode(Payload.self, from: data) }
        catch { throw invalid("the response does not match the supported public v2 format.") }
        guard payload.profile.user_id > 0,
              payload.cycles.count + payload.recoveries.count + payload.sleeps.count + payload.workouts.count <= 20_000 else {
            throw invalid("the account identity or record count is invalid.")
        }
        let user = payload.profile.user_id
        var cycles: [Int64: Cycle] = [:]
        var days: [Date: DailySnapshot] = [:]
        for cycle in payload.cycles {
            guard cycle.id > 0, cycle.user_id == user, cycles[cycle.id] == nil else { throw invalid("cycle identities conflict.") }
            let start = try date(cycle.start)
            if let end = cycle.end { guard try date(end) > start else { throw invalid("a cycle has an invalid interval.") } }
            let key = DayCalendar.start(of: start)
            guard days[key] == nil else { throw invalid("multiple cycles fall on one UTC day. No scores were saved.") }
            try state(cycle.score_state, hasScore: cycle.score != nil)
            var day = DailySnapshot.empty(on: key)
            if cycle.score_state == "SCORED", let score = cycle.score {
                try bounds(score.strain, 0...21); try bounds(score.kilojoule, 0...418_400)
                day.strain = score.strain
                day.energyKcal = score.kilojoule / 4.184
            }
            cycles[cycle.id] = cycle; days[key] = day
        }
        var sleeps: [UUID: Sleep] = [:]
        for sleep in payload.sleeps {
            guard let id = UUID(uuidString: sleep.id), sleep.cycle_id > 0, sleep.user_id == user, sleeps[id] == nil else {
                throw invalid("sleep identities conflict.")
            }
            let start = try date(sleep.start), end = try date(sleep.end)
            guard end > start, end.timeIntervalSince(start) <= 86_400 else { throw invalid("a sleep interval is outside the supported range.") }
            try state(sleep.score_state, hasScore: sleep.score != nil)
            if sleep.score_state == "SCORED", let score = sleep.score {
                _ = try sleepValues(score)
                // Permit one second of timestamp rounding, never hours of invented duration.
                guard score.stage_summary.total_in_bed_time_milli <= end.timeIntervalSince(start) * 1000 + 1000 else {
                    throw invalid("reported time in bed exceeds the sleep interval.")
                }
            }
            sleeps[id] = sleep
        }
        var recovered = Set<Int64>()
        for recovery in payload.recoveries {
            guard recovery.cycle_id > 0, recovery.user_id == user,
                  let sleepID = UUID(uuidString: recovery.sleep_id), recovered.insert(recovery.cycle_id).inserted else {
                throw invalid("recovery identities conflict.")
            }
            try state(recovery.score_state, hasScore: recovery.score != nil)
            if let score = recovery.score {
                try bounds(score.recovery_score, 0...100); try bounds(score.resting_heart_rate, 1...300)
                try bounds(score.hrv_rmssd_milli, 0...1_000)
            }
            if let sleep = sleeps[sleepID], sleep.cycle_id != recovery.cycle_id || sleep.nap {
                throw invalid("a recovery references a different cycle or a nap.")
            }
            // Range edges may omit the referenced cycle or sleep. Never join by date proximity.
            guard let cycle = cycles[recovery.cycle_id] else { continue }
            let key = DayCalendar.start(of: try date(cycle.start))
            guard var day = days[key] else { continue }
            if recovery.score_state == "SCORED", let score = recovery.score {
                day.recovery = Int(score.recovery_score.rounded())
                day.restingHeartRate = score.resting_heart_rate; day.hrv = score.hrv_rmssd_milli
            }
            if let sleep = sleeps[sleepID], sleep.score_state == "SCORED", let score = sleep.score {
                let values = try sleepValues(score)
                day.sleepPerformance = Int(score.sleep_performance_percentage.rounded())
                day.sleepMinutes = values.asleep; day.sleepNeededMinutes = values.needed
                day.respiratoryRate = score.respiratory_rate
            }
            days[key] = day
        }
        // Sleep without a recovery can still be joined through its explicit cycle_id.
        // When recovery exists, its sleep_id is authoritative; naps never replace main sleep.
        var standaloneCycles = Set<Int64>()
        for sleep in payload.sleeps where !sleep.nap && !recovered.contains(sleep.cycle_id) {
            guard standaloneCycles.insert(sleep.cycle_id).inserted else { throw invalid("multiple main sleeps refer to one cycle.") }
            guard let cycle = cycles[sleep.cycle_id], sleep.score_state == "SCORED", let score = sleep.score else { continue }
            let key = DayCalendar.start(of: try date(cycle.start)); guard var day = days[key] else { continue }
            let values = try sleepValues(score)
            day.sleepPerformance = Int(score.sleep_performance_percentage.rounded())
            day.sleepMinutes = values.asleep; day.sleepNeededMinutes = values.needed; day.respiratoryRate = score.respiratory_rate
            days[key] = day
        }
        var workoutIDs = Set<UUID>(), activities: [ActivityRecord] = []
        for workout in payload.workouts {
            guard let id = UUID(uuidString: workout.id), workout.user_id == user, workout.sport_id >= -1,
                  workoutIDs.insert(id).inserted else { throw invalid("workout identities conflict.") }
            let start = try date(workout.start), end = try date(workout.end)
            let duration = end.timeIntervalSince(start)
            guard duration > 0, duration <= 86_400 else { throw invalid("a workout interval is outside the supported range.") }
            try state(workout.score_state, hasScore: workout.score != nil)
            var strain: Double?
            if workout.score_state == "SCORED", let score = workout.score { try bounds(score.strain, 0...21); strain = score.strain }
            activities.append(ActivityRecord(id: id, start: start, durationMinutes: max(1, Int((duration / 60).rounded(.down))),
                name: "WHOOP activity · sport \(workout.sport_id)", strain: strain, strainIsEstimate: false))
        }
        let name = [payload.profile.first_name, payload.profile.last_name].compactMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " ")
        guard name.count <= 200, name.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw invalid("the profile name is invalid.")
        }
        return WhoopAccountImport(days: days.values.sorted { $0.date < $1.date },
            activities: activities.sorted { $0.start == $1.start ? $0.id.uuidString < $1.id.uuidString : $0.start < $1.start },
            displayName: name.isEmpty ? nil : name, userID: user)
    }

    private static func invalid(_ reason: String) -> WhoopAccountError { .invalidData(reason) }
    private static func bounds(_ value: Double, _ range: ClosedRange<Double>) throws {
        guard value.isFinite, range.contains(value) else { throw invalid("a measurement is outside the supported range.") }
    }
    private static func state(_ value: String, hasScore: Bool) throws {
        guard ["SCORED", "PENDING_SCORE", "UNSCORABLE"].contains(value), (value == "SCORED") == hasScore else {
            throw invalid("a record has an inconsistent score state.")
        }
    }
    private static func date(_ text: String) throws -> Date {
        let parser = ISO8601DateFormatter(); parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let parsed = parser.date(from: text)
        parser.formatOptions = [.withInternetDateTime]
        guard let date = parsed ?? parser.date(from: text), (0...4_102_444_800).contains(date.timeIntervalSince1970) else {
            throw invalid("a timestamp is invalid.")
        }
        return date
    }
    private static func sleepValues(_ score: SleepScore) throws -> (asleep: Int, needed: Int) {
        let stage = score.stage_summary, need = score.sleep_needed
        let values = [stage.total_in_bed_time_milli, stage.total_awake_time_milli, stage.total_no_data_time_milli,
            stage.total_light_sleep_time_milli, stage.total_slow_wave_sleep_time_milli, stage.total_rem_sleep_time_milli,
            need.baseline_milli, need.need_from_sleep_debt_milli, need.need_from_recent_strain_milli]
        for value in values { try bounds(value, 0...86_400_000) }
        // Public SDK examples contain a negative nap adjustment; preserve its sign.
        try bounds(need.need_from_recent_nap_milli, -86_400_000...0)
        let asleep = stage.total_light_sleep_time_milli + stage.total_slow_wave_sleep_time_milli + stage.total_rem_sleep_time_milli
        let needed = need.baseline_milli + need.need_from_sleep_debt_milli + need.need_from_recent_strain_milli + need.need_from_recent_nap_milli
        try bounds(asleep, 0...stage.total_in_bed_time_milli); try bounds(needed, 0...86_400_000)
        guard asleep + stage.total_awake_time_milli + stage.total_no_data_time_milli <= stage.total_in_bed_time_milli else {
            throw invalid("sleep stages exceed time in bed.")
        }
        try bounds(score.sleep_performance_percentage, 0...100); try bounds(score.respiratory_rate, 0...100)
        return (Int(asleep / 60_000), Int(needed / 60_000))
    }
}

private struct Payload: Decodable { let profile: Profile; let cycles: [Cycle]; let recoveries: [Recovery]; let sleeps: [Sleep]; let workouts: [Workout] }
private struct Profile: Decodable { let user_id: Int64; let first_name: String?; let last_name: String? }
private struct Cycle: Decodable { let id: Int64; let user_id: Int64; let start: String; let end: String?; let score_state: String; let score: CycleScore? }
private struct CycleScore: Decodable { let strain: Double; let kilojoule: Double }
private struct Recovery: Decodable { let cycle_id: Int64; let user_id: Int64; let sleep_id: String; let score_state: String; let score: RecoveryScore? }
private struct RecoveryScore: Decodable { let recovery_score: Double; let resting_heart_rate: Double; let hrv_rmssd_milli: Double }
private struct Sleep: Decodable { let id: String; let user_id: Int64; let cycle_id: Int64; let nap: Bool; let start: String; let end: String; let score_state: String; let score: SleepScore? }
private struct SleepScore: Decodable { let stage_summary: Stages; let sleep_needed: SleepNeed; let respiratory_rate: Double; let sleep_performance_percentage: Double }
private struct Stages: Decodable { let total_in_bed_time_milli: Double; let total_awake_time_milli: Double; let total_no_data_time_milli: Double; let total_light_sleep_time_milli: Double; let total_slow_wave_sleep_time_milli: Double; let total_rem_sleep_time_milli: Double }
private struct SleepNeed: Decodable { let baseline_milli: Double; let need_from_sleep_debt_milli: Double; let need_from_recent_strain_milli: Double; let need_from_recent_nap_milli: Double }
private struct Workout: Decodable { let id: String; let user_id: Int64; let sport_id: Int; let start: String; let end: String; let score_state: String; let score: WorkoutScore? }
private struct WorkoutScore: Decodable { let strain: Double }
