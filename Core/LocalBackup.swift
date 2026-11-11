import Foundation

/// A complete, versioned copy of the app's local user data.
public struct LocalBackup: Codable, Equatable, Sendable {
    public var format: String
    public var version: Int
    public var exportedAt: Date
    public var selectedDate: Date
    public var days: [DailySnapshot]
    public var journal: [JournalEntry]
    public var activities: [ActivityRecord]
    public var whoopAccountUserID: Int64?
    public var nutrition: NutritionData?
    public var profile: ProfilePersonalization?

    public init(format: String = "WHOOP_LOCAL_BACKUP", version: Int = 1,
                exportedAt: Date = Date(), selectedDate: Date, days: [DailySnapshot],
                journal: [JournalEntry], activities: [ActivityRecord], whoopAccountUserID: Int64? = nil, nutrition: NutritionData? = nil, profile: ProfilePersonalization? = nil) {
        self.format = format; self.version = version; self.exportedAt = exportedAt
        self.selectedDate = selectedDate; self.days = days
        self.journal = journal; self.activities = activities; self.whoopAccountUserID = whoopAccountUserID; self.nutrition = nutrition; self.profile = profile
    }
}

public enum LocalBackupError: Error, LocalizedError, Equatable {
    case tooLarge, tooManyRows, wrongFormat, unsupportedVersion(Int)
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        case .tooLarge: return "Choose a local backup no larger than 20 MiB."
        case .tooManyRows: return "A local backup may contain at most 100,000 total records."
        case .wrongFormat: return "This file is not a WHOOP local backup."
        case .unsupportedVersion(let version): return "Local backup version \(version) is not supported."
        case .invalid(let message): return message
        }
    }
}

/// Validates the complete backup before returning any data to the application.
public enum LocalBackupCodec {
    public static let maximumBytes = 20 * 1024 * 1024
    public static let maximumRows = 100_000
    public static let maximumJournalEntries = 10_000
    public static let maximumNoteCharacters = 20_000
    public static let maximumActivityNameCharacters = 80

    public static func encode(_ backup: LocalBackup) throws -> Data {
        try validate(backup)
        let data = try ImportReader.jsonEncoder().encode(backup)
        guard data.count <= maximumBytes else { throw LocalBackupError.tooLarge }
        return data
    }

    public static func decode(_ data: Data) throws -> LocalBackup {
        guard data.count <= maximumBytes else { throw LocalBackupError.tooLarge }
        let backup: LocalBackup
        do {
            backup = try ImportReader.jsonDecoder().decode(LocalBackup.self, from: data)
        } catch {
            throw LocalBackupError.invalid("The local backup is incomplete or invalid. All backup fields and valid ISO 8601 dates are required.")
        }
        try validate(backup)
        return backup
    }

    /// Routes recognizable backup envelopes to strict backup decoding, including
    /// an invalid marker or version. A failed backup must never fall back to a day import.
    public static func isBackup(_ data: Data) -> Bool {
        guard data.count <= maximumBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return ["format", "version", "exportedAt", "selectedDate", "journal", "activities"].contains {
            object.keys.contains($0)
        }
    }

    private static func validate(_ backup: LocalBackup) throws {
        guard backup.format == "WHOOP_LOCAL_BACKUP" else { throw LocalBackupError.wrongFormat }
        guard backup.version == 1 else { throw LocalBackupError.unsupportedVersion(backup.version) }
        if let profile = backup.profile { _ = try profile.validated() }
        if let userID = backup.whoopAccountUserID, userID <= 0 { throw LocalBackupError.invalid("The saved WHOOP account identity is invalid.") }
        guard validDate(backup.exportedAt), validDate(backup.selectedDate) else {
            throw LocalBackupError.invalid("Backup dates must be finite dates in years 0001–9999.")
        }
        guard backup.journal.count <= maximumJournalEntries else {
            throw LocalBackupError.invalid("A backup may contain at most 10,000 journal entries.")
        }
        var rows = 0
        func count(_ amount: Int) throws {
            guard amount <= maximumRows - rows else { throw LocalBackupError.tooManyRows }
            rows += amount
        }
        try count(backup.days.count)
        try count(backup.journal.count)
        try count(backup.activities.count)
        if let nutrition = backup.nutrition {
            try NutritionValidation.validate(nutrition)
            try count(nutrition.foods.count + nutrition.exercises.count + nutrition.weights.count + nutrition.favorites.count + nutrition.completedDays.count)
        }
        var dayDates = Set<Date>()
        for day in backup.days {
            guard validDate(day.date), DayCalendar.start(of: day.date) == day.date,
                  dayDates.insert(day.date).inserted else {
                throw LocalBackupError.invalid("Daily entries must have unique UTC midnight dates.")
            }
            guard optional(day.recovery, in: 0...100), optional(day.sleepPerformance, in: 0...100),
                  optional(day.strain, in: 0...21),
                  (0...1440).contains(day.sleepMinutes), (0...1440).contains(day.sleepNeededMinutes),
                  optional(day.restingHeartRate, in: 1...300), optional(day.hrv, in: 0...1000),
                  optional(day.respiratoryRate, in: 0...100),
                  (0...1_000_000).contains(day.steps), day.energyKcal.isFinite,
                  (0...100_000).contains(day.energyKcal) else {
                throw LocalBackupError.invalid("A daily metric is outside its supported range.")
            }
            try count(day.heartRates.count)
            var timestamps = Set<Date>()
            for sample in day.heartRates {
                guard validDate(sample.timestamp), sample.bpm.isFinite,
                      sample.bpm > 0, sample.bpm <= 300,
                      DayCalendar.start(of: sample.timestamp) == day.date,
                      timestamps.insert(sample.timestamp).inserted else {
                    throw LocalBackupError.invalid("Heart rates must be unique by timestamp, between 0 and 300 bpm, and belong to their entry's UTC day.")
                }
            }
        }
        var journalDates = Set<Date>()
        for entry in backup.journal {
            guard validDate(entry.date), journalDates.insert(DayCalendar.start(of: entry.date)).inserted,
                  entry.note.count <= maximumNoteCharacters else {
                throw LocalBackupError.invalid("Journal entries need unique UTC days and notes of at most 20,000 characters.")
            }
        }
        var activityIDs = Set<UUID>()
        for activity in backup.activities {
            guard activityIDs.insert(activity.id).inserted, validDate(activity.start),
                  (1...1440).contains(activity.durationMinutes),
                  !activity.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  activity.name.count <= maximumActivityNameCharacters,
                  optional(activity.strain, in: 0...21) else {
                throw LocalBackupError.invalid("Activities need unique UUIDs, a name of 1–80 characters, a duration of 1–1,440 minutes, and strain between 0 and 21.")
            }
        }
    }

    private static func validDate(_ date: Date) -> Bool {
        let seconds = date.timeIntervalSince1970
        return seconds.isFinite && seconds >= -62_135_596_800 && seconds < 253_402_300_800
    }

    private static func optional(_ value: Int?, in range: ClosedRange<Int>) -> Bool {
        value.map(range.contains) ?? true
    }

    private static func optional(_ value: Double?, in range: ClosedRange<Double>) -> Bool {
        value.map { $0.isFinite && range.contains($0) } ?? true
    }
}
