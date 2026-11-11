import Foundation

public enum DataSource: String, Codable, Sendable {
    case example, imported
    public var title: String { self == .example ? "Example data" : "Imported data" }
}

/// All archive dates and day grouping use UTC, independent of device timezone.
public enum DayCalendar {
    public static var utc: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    public static func start(of date: Date) -> Date { utc.startOfDay(for: date) }
}

/// A personal session starts empty and never adopts screenshot/example scores.
public struct LaunchDayData: Equatable, Sendable {
    public let days: [DailySnapshot]
    public let selectedDate: Date
    public init(savedDays: [DailySnapshot] = [], selectedDate: Date? = nil, now: Date = Date()) {
        days = savedDays.filter { $0.source != .example }.sorted { $0.date < $1.date }
        self.selectedDate = DayCalendar.start(of: days.isEmpty ? now : (selectedDate ?? now))
    }
}

public struct HeartRateSample: Codable, Identifiable, Equatable, Sendable {
    public var timestamp: Date
    public var bpm: Double
    public var id: Date { timestamp }
    public init(timestamp: Date, bpm: Double) { self.timestamp = timestamp; self.bpm = bpm }
}

public struct DailySnapshot: Codable, Identifiable, Equatable, Sendable {
    public var date: Date
    public var recovery: Int?
    public var strain: Double?
    public var sleepPerformance: Int?
    public var sleepMinutes: Int
    public var sleepNeededMinutes: Int
    public var restingHeartRate: Double?
    public var hrv: Double?
    public var respiratoryRate: Double?
    public var steps: Int
    public var energyKcal: Double
    public var heartRates: [HeartRateSample]
    public var source: DataSource
    public var id: Date { date }

    public init(date: Date, recovery: Int?, strain: Double?, sleepPerformance: Int?,
                sleepMinutes: Int, sleepNeededMinutes: Int, restingHeartRate: Double?,
                hrv: Double?, respiratoryRate: Double?, steps: Int, energyKcal: Double,
                heartRates: [HeartRateSample], source: DataSource) {
        self.date = date; self.recovery = recovery; self.strain = strain
        self.sleepPerformance = sleepPerformance; self.sleepMinutes = sleepMinutes
        self.sleepNeededMinutes = sleepNeededMinutes; self.restingHeartRate = restingHeartRate
        self.hrv = hrv; self.respiratoryRate = respiratoryRate; self.steps = steps
        self.energyKcal = energyKcal; self.heartRates = heartRates; self.source = source
    }

    public static func empty(on date: Date, source: DataSource = .imported) -> Self {
        .init(date: DayCalendar.start(of: date), recovery: nil, strain: nil, sleepPerformance: nil,
              sleepMinutes: 0, sleepNeededMinutes: 0, restingHeartRate: nil, hrv: nil,
              respiratoryRate: nil, steps: 0, energyKcal: 0, heartRates: [], source: source)
    }

    private enum CodingKeys: String, CodingKey {
        case date, recovery, strain, sleepPerformance, sleepMinutes, sleepNeededMinutes
        case restingHeartRate, hrv, respiratoryRate, steps, energyKcal, heartRates, source
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        date = try values.decode(Date.self, forKey: .date)
        recovery = try values.decodeIfPresent(Int.self, forKey: .recovery)
        strain = try values.decodeIfPresent(Double.self, forKey: .strain)
        sleepPerformance = try values.decodeIfPresent(Int.self, forKey: .sleepPerformance)
        sleepMinutes = try values.decodeIfPresent(Int.self, forKey: .sleepMinutes) ?? 0
        sleepNeededMinutes = try values.decodeIfPresent(Int.self, forKey: .sleepNeededMinutes) ?? 0
        restingHeartRate = try values.decodeIfPresent(Double.self, forKey: .restingHeartRate)
        hrv = try values.decodeIfPresent(Double.self, forKey: .hrv)
        respiratoryRate = try values.decodeIfPresent(Double.self, forKey: .respiratoryRate)
        steps = try values.decodeIfPresent(Int.self, forKey: .steps) ?? 0
        energyKcal = try values.decodeIfPresent(Double.self, forKey: .energyKcal) ?? 0
        heartRates = try values.decodeIfPresent([HeartRateSample].self, forKey: .heartRates) ?? []
        source = try values.decodeIfPresent(DataSource.self, forKey: .source) ?? .imported
    }
}

public struct JournalEntry: Codable, Equatable, Sendable {
    public var date: Date
    public var caffeine: Bool
    public var alcohol: Bool
    public var lateMeal: Bool
    public var note: String
    public init(date: Date, caffeine: Bool = false, alcohol: Bool = false,
                lateMeal: Bool = false, note: String = "") {
        self.date = date; self.caffeine = caffeine; self.alcohol = alcohol
        self.lateMeal = lateMeal; self.note = note
    }
}

public struct ActivityRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var start: Date
    public var durationMinutes: Int
    public var name: String
    public var strain: Double?
    /// True only for a local reference estimate, never an imported official score.
    public var strainIsEstimate: Bool?
    public init(id: UUID = UUID(), start: Date, durationMinutes: Int, name: String, strain: Double? = nil, strainIsEstimate: Bool? = nil) {
        self.id = id; self.start = start; self.durationMinutes = durationMinutes
        self.name = name; self.strain = strain; self.strainIsEstimate = strainIsEstimate
    }
}

public struct DayArchive: Codable, Equatable, Sendable {
    public var days: [DailySnapshot]
    public init(days: [DailySnapshot]) { self.days = days }
}

/// Local display preferences. Ages are decimal strings so no arbitrary numeric age
/// ceiling or floating-point rounding is imposed on personalized display values.
public struct ProfilePersonalization: Codable, Equatable, Sendable {
    public var displayName: String
    public var username: String
    public var age: String
    public var whoopAge: String
    public var dayStreakOverride: Int?
    public init(displayName: String = "", username: String = "", age: String = "", whoopAge: String = "", dayStreakOverride: Int? = nil) {
        self.displayName = displayName; self.username = username; self.age = age
        self.whoopAge = whoopAge; self.dayStreakOverride = dayStreakOverride
    }
    public var isPersonalized: Bool {
        !displayName.isEmpty || !username.isEmpty || !age.isEmpty || !whoopAge.isEmpty || dayStreakOverride != nil
    }
    public func validated() throws -> Self {
        var result = self
        result.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        result.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.username.hasPrefix("@") { result.username.removeFirst() }
        guard result.displayName.count <= 100, result.username.count <= 80,
              !result.displayName.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              !result.username.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw ProfilePersonalizationError.invalid("Use a name up to 100 characters and a username up to 80 characters, without control characters.")
        }
        result.age = try Self.ageText(age)
        result.whoopAge = try Self.ageText(whoopAge)
        if let dayStreakOverride, dayStreakOverride < 0 {
            throw ProfilePersonalizationError.invalid("Your chosen day streak must be zero or greater.")
        }
        return result
    }
    public func initials(fallback: String = "AA") -> String {
        let words = displayName.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return fallback }
        return (words.count > 1 ? words.prefix(2).compactMap(\.first).map(String.init).joined() : String(words[0].prefix(2))).uppercased()
    }
    private static func ageText(_ input: String) throws -> String {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard !text.isEmpty else { return "" }
        guard text.unicodeScalars.allSatisfy({ (48...57).contains($0.value) || $0.value == 46 }),
              text.filter({ $0 == "." }).count <= 1, text.contains(where: { $0 != "." }) else {
            throw ProfilePersonalizationError.invalid("Enter an age of zero or greater, with an optional decimal point. There is no upper age limit.")
        }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        let whole = String(parts[0].drop(while: { $0 == "0" }))
        let fraction = parts.count == 2 ? String(parts[1].reversed().drop(while: { $0 == "0" }).reversed()) : ""
        return (whole.isEmpty ? "0" : whole) + (fraction.isEmpty ? "" : "." + fraction)
    }
}
public enum ProfilePersonalizationError: LocalizedError, Equatable {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}
public struct ProfileRecord: Codable, Equatable, Sendable {
    public let value: Double
    public let date: Date
}
public struct ProfileHighlights: Codable, Equatable, Sendable {
    public var bestSleepPerformance: ProfileRecord?
    public var peakRecovery: ProfileRecord?
    public var peakStrain: ProfileRecord?
    public var lowestRecovery: ProfileRecord?
    public var lowestRestingHeartRate: ProfileRecord?
    public var highestRestingHeartRate: ProfileRecord?
    public var lowestHRV: ProfileRecord?
    public var highestHRV: ProfileRecord?
    public var maxHeartRate: ProfileRecord?
    public var longestSleepMinutes: ProfileRecord?
    public var savedDays = 0
    public var currentLoggedDayStreak = 0
    public var longestLoggedDayStreak = 0
    public var longestSleep70Streak = 0
    public var longestGreenRecoveryStreak = 0
    public var longestStrain10Streak = 0
    public init() { }
}
