import Foundation

public enum MeasurementExportFormat: String, CaseIterable, Sendable {
    case json, dailyCSV, heartRateCSV, highlightsCSV
    public var fileExtension: String { self == .json ? "json" : "csv" }
}

public struct MeasurementExportFile: Sendable {
    public let data: Data
    public let filename: String
    public let dayCount: Int
    public let heartRateCount: Int
}

public enum MeasurementExportError: LocalizedError, Equatable {
    case noSavedDays, noHeartRates, invalidDate, tooLarge
    public var errorDescription: String? {
        switch self {
        case .noSavedDays: return "There are no saved measurements in this range. Home examples are never exported."
        case .noHeartRates: return "There are no saved heart-rate samples in this range. Choose JSON or Daily CSV for available day measurements."
        case .invalidDate: return "A saved record or selected range has an invalid date."
        case .tooLarge: return "This export is too large. Choose a shorter date range and try again."
        }
    }
}

/// Exports stored measurements, not the Home design fixtures. The existing archive
/// does not identify the provider of every imported field, so no WHOOP-only origin
/// is claimed. Only explicitly supplied profile preferences are added; account
/// tokens, journal notes and unrelated app state are never read.
public enum MeasurementExport {
    public static func selectedDays(_ days: [DailySnapshot], range: ClosedRange<Date>? = nil) throws -> [DailySnapshot] {
        var bounds: ClosedRange<Date>?
        if let range {
            guard validDate(range.lowerBound), validDate(range.upperBound) else { throw MeasurementExportError.invalidDate }
            bounds = DayCalendar.start(of: range.lowerBound)...DayCalendar.start(of: range.upperBound)
        }
        return try days.filter { $0.source == .imported }.compactMap { original in
            guard validDate(original.date) else { throw MeasurementExportError.invalidDate }
            var day = original
            day.date = DayCalendar.start(of: day.date)
            if let bounds, !bounds.contains(day.date) { return nil }
            return day
        }.sorted { $0.date < $1.date }
    }

    public static func make(days: [DailySnapshot], format: MeasurementExportFormat,
                            range: ClosedRange<Date>? = nil, profile: ProfilePersonalization? = nil,
                            asOf: Date = Date()) throws -> MeasurementExportFile {
        try Task.checkCancellation()
        guard validDate(asOf) else { throw MeasurementExportError.invalidDate }
        let personal = try profile?.validated()
        let selected = try selectedDays(days, range: range)
        guard !selected.isEmpty || ((format == .json || format == .highlightsCSV) && personal?.isPersonalized == true) else { throw MeasurementExportError.noSavedDays }
        guard selected.count <= ImportReader.maximumRows else { throw MeasurementExportError.tooLarge }
        var sampleCount = 0
        for day in selected {
            try Task.checkCancellation()
            guard day.heartRates.count <= ImportReader.maximumRows - sampleCount else { throw MeasurementExportError.tooLarge }
            sampleCount += day.heartRates.count
            guard day.heartRates.allSatisfy({ validDate($0.timestamp) }) else { throw MeasurementExportError.invalidDate }
        }
        // Reuse the importer to validate metrics, dates and conflicting samples.
        // JSON remains compatible with the existing day-data import path.
        let archive = try ImportReader.jsonEncoder().encode(DayArchive(days: selected))
        guard archive.count <= ImportReader.maximumBytes else { throw MeasurementExportError.tooLarge }
        let validated: [DailySnapshot] = selected.isEmpty ? [] : try ImportReader.read(archive, filename: "measurements.json")
        let highlights = ProfileHighlightsCalculator.calculate(days: validated, asOf: asOf)
        let actualSampleCount = validated.reduce(0) { $0 + $1.heartRates.count }
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var prefix: String
        let data: Data
        switch format {
        case .json:
            prefix = validated.isEmpty ? "WHOOP-profile" : "WHOOP-saved-measurements"
            let metadata = PersonalizedExportMetadata(format: "WHOOP_PERSONALIZED_EXPORT", version: 1, exportedAt: asOf,
                timeZone: "UTC", profileSource: "user_configured", highlightsSource: "saved_non_example_measurements_through_export_date",
                rangeStart: range.map { DayCalendar.start(of: $0.lowerBound) } ?? validated.first?.date,
                rangeEnd: range.map { DayCalendar.start(of: $0.upperBound) } ?? validated.last?.date, includesExamples: false)
            data = try ImportReader.jsonEncoder().encode(PersonalizedMeasurementArchive(days: validated, profile: personal, highlights: highlights, metadata: metadata))
        case .dailyCSV:
            prefix = "WHOOP-daily-measurements"
            var rows = ["date_utc,recovery_percent,strain,sleep_performance_percent,sleep_minutes,sleep_needed_minutes,resting_heart_rate_bpm,hrv_rmssd_ms,respiratory_rate_rpm,steps,energy_kcal,heart_rate_sample_count,data_source"]
            for day in validated {
                try Task.checkCancellation()
                rows.append([
                    String(formatter.string(from: day.date).prefix(10)), number(day.recovery), number(day.strain),
                    number(day.sleepPerformance), String(day.sleepMinutes), String(day.sleepNeededMinutes),
                    number(day.restingHeartRate), number(day.hrv), number(day.respiratoryRate),
                    String(day.steps), String(day.energyKcal), String(day.heartRates.count), day.source.rawValue
                ].joined(separator: ","))
            }
            data = Data((rows.joined(separator: "\r\n") + "\r\n").utf8)
        case .highlightsCSV:
            prefix = "WHOOP-profile-highlights"
            data = Data(highlightsCSV(profile: personal, highlights: highlights, formatter: formatter).utf8)
        case .heartRateCSV:
            guard actualSampleCount > 0 else { throw MeasurementExportError.noHeartRates }
            prefix = "WHOOP-heart-rate"
            var rows = ["timestamp,heart_rate"]
            for day in validated {
                try Task.checkCancellation()
                for sample in day.heartRates {
                    rows.append("\(formatter.string(from: sample.timestamp)),\(sample.bpm)")
                }
            }
            data = Data((rows.joined(separator: "\r\n") + "\r\n").utf8)
        }
        guard data.count <= ImportReader.maximumBytes else { throw MeasurementExportError.tooLarge }
        try Task.checkCancellation()
        let firstDate = formatter.string(from: validated.first?.date ?? DayCalendar.start(of: asOf)).prefix(10)
        let lastDate = formatter.string(from: validated.last?.date ?? DayCalendar.start(of: asOf)).prefix(10)
        return MeasurementExportFile(data: data, filename: "\(prefix)-\(firstDate)-to-\(lastDate).\(format.fileExtension)",
                                     dayCount: validated.count, heartRateCount: actualSampleCount)
    }

    public static func readImport(_ data: Data, filename: String) throws -> ImportedMeasurementArchive {
        guard data.count <= ImportReader.maximumBytes else { throw ImportError.tooLarge }
        if URL(fileURLWithPath: filename).pathExtension.lowercased() == "json",
           data.first(where: { ![9, 10, 13, 32].contains($0) }) == 123 {
            let decoder = ImportReader.jsonDecoder()
            let probe = try decoder.decode(ProfileEnvelopeProbe.self, from: data)
            if probe.hasProfile || probe.format == "WHOOP_PERSONALIZED_EXPORT" {
                let header = try decoder.decode(ProfileImportHeader.self, from: data)
                guard header.metadata?.format == "WHOOP_PERSONALIZED_EXPORT", header.metadata?.version == 1,
                      let days = header.days else { throw ImportError.invalid("This personalized export has an unsupported format or version.") }
                let profile = try header.profile?.validated()
                let validated = days.isEmpty ? [] : try ImportReader.read(data, filename: filename)
                guard !validated.isEmpty || profile?.isPersonalized == true else { throw ImportError.noData }
                // Exported highlights are not imported as scores; always recalculate them.
                return ImportedMeasurementArchive(days: validated, profile: profile)
            }
        }
        return ImportedMeasurementArchive(days: try ImportReader.read(data, filename: filename), profile: nil)
    }
    private struct ProfileImportHeader: Decodable {
        let days: [DailySnapshot]?
        let profile: ProfilePersonalization?
        let metadata: ProfileImportMetadata?
    }
    private struct ProfileImportMetadata: Decodable { let format: String?; let version: Int? }
    private struct ProfileEnvelopeProbe: Decodable {
        let hasProfile: Bool
        let format: String?
        private enum CodingKeys: String, CodingKey { case profile, metadata }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            hasProfile = values.contains(.profile)
            format = (try? values.decodeIfPresent(ProfileImportMetadata.self, forKey: .metadata))?.format
        }
    }
    private static func highlightsCSV(profile: ProfilePersonalization?, highlights: ProfileHighlights, formatter: ISO8601DateFormatter) -> String {
        var rows = [["kind", "metric", "value", "unit", "date_utc", "source"]]
        if let profile {
            for (key, value, unit) in [("display_name", profile.displayName, "text"), ("username", profile.username, "text"),
                ("age", profile.age, "years_display_text"), ("whoop_age", profile.whoopAge, "years_display_text"),
                ("day_streak_override", profile.dayStreakOverride.map(String.init) ?? "", "days")] {
                rows.append(["profile", key, value, unit, "", "user_configured"])
            }
        }
        let records: [(String, ProfileRecord?, String)] = [
            ("best_sleep_performance", highlights.bestSleepPerformance, "percent"), ("peak_recovery", highlights.peakRecovery, "percent"),
            ("max_strain", highlights.peakStrain, "0_to_21"), ("lowest_recovery", highlights.lowestRecovery, "percent"),
            ("lowest_resting_heart_rate", highlights.lowestRestingHeartRate, "bpm"), ("highest_resting_heart_rate", highlights.highestRestingHeartRate, "bpm"),
            ("lowest_hrv", highlights.lowestHRV, "ms"), ("highest_hrv", highlights.highestHRV, "ms"),
            ("max_heart_rate", highlights.maxHeartRate, "bpm"), ("longest_sleep", highlights.longestSleepMinutes, "minutes")]
        for (key, record, unit) in records {
            rows.append(["highlight", key, record.map { number($0.value) } ?? "", unit, record.map { String(formatter.string(from: $0.date).prefix(10)) } ?? "", "saved_measurements"])
        }
        for (key, count) in [("saved_days", highlights.savedDays), ("current_logged_day_streak", highlights.currentLoggedDayStreak),
            ("longest_logged_day_streak", highlights.longestLoggedDayStreak), ("longest_sleep_70_streak", highlights.longestSleep70Streak),
            ("longest_green_recovery_streak", highlights.longestGreenRecoveryStreak), ("longest_strain_10_streak", highlights.longestStrain10Streak)] {
            rows.append(["streak", key, String(count), "days", "", "saved_measurements"])
        }
        return rows.map { $0.map(csvCell).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }
    private static func csvCell(_ raw: String) -> String {
        let first = raw.trimmingCharacters(in: .whitespacesAndNewlines).first
        let safe = first.map { "=+-@".contains($0) } == true ? "'" + raw : raw
        return safe.contains(where: { ",\"\r\n".contains($0) }) ? "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : safe
    }

    private static func number<T: CustomStringConvertible>(_ value: T?) -> String { value?.description ?? "" }
    private static func validDate(_ date: Date) -> Bool {
        date.timeIntervalSince1970.isFinite && (-62_135_596_800...253_402_300_799.999).contains(date.timeIntervalSince1970)
    }
}

/// Highlights describe saved non-example days, not official wear-time or a
/// proprietary health-age calculation. Missing calendar dates break a streak.
public enum ProfileHighlightsCalculator {
    public static func calculate(days: [DailySnapshot], asOf: Date = Date()) -> ProfileHighlights {
        guard validDate(asOf) else { return ProfileHighlights() }
        let today = DayCalendar.start(of: asOf)
        let eligible = days.filter { $0.source == .imported && validDate($0.date) && DayCalendar.start(of: $0.date) <= today }
            .sorted { $0.date < $1.date }
        var result = ProfileHighlights()
        var logged = Set<Date>(), sleep70 = Set<Date>(), green = Set<Date>(), strain10 = Set<Date>()
        func record(_ current: inout ProfileRecord?, _ value: Double?, date: Date, range: ClosedRange<Double>, highest: Bool = true) {
            guard let value, value.isFinite, range.contains(value) else { return }
            if let old = current, highest ? value <= old.value : value >= old.value { return }
            current = ProfileRecord(value: value, date: date)
        }
        for day in eligible {
            let date = DayCalendar.start(of: day.date)
            let rates = day.heartRates.filter { validDate($0.timestamp) && $0.timestamp <= asOf && DayCalendar.start(of: $0.timestamp) == date && $0.bpm.isFinite && (1...300).contains($0.bpm) }
            let validRecovery = day.recovery.map { (0...100).contains($0) } ?? false
            let validSleep = day.sleepPerformance.map { (0...100).contains($0) } ?? false
            let validStrain = day.strain.map { $0.isFinite && (0...21).contains($0) } ?? false
            if validRecovery || validSleep || validStrain || (1...1440).contains(day.sleepMinutes) || !rates.isEmpty ||
                day.restingHeartRate.map({ $0.isFinite && (1...300).contains($0) }) == true ||
                day.hrv.map({ $0.isFinite && (0...1000).contains($0) }) == true ||
                day.respiratoryRate.map({ $0.isFinite && (0...100).contains($0) }) == true ||
                (1...1_000_000).contains(day.steps) || (day.energyKcal.isFinite && (0.001...100_000).contains(day.energyKcal)) {
                logged.insert(date)
            }
            record(&result.bestSleepPerformance, day.sleepPerformance.map(Double.init), date: date, range: 0...100)
            record(&result.peakRecovery, day.recovery.map(Double.init), date: date, range: 0...100)
            record(&result.peakStrain, day.strain, date: date, range: 0...21)
            record(&result.lowestRecovery, day.recovery.map(Double.init), date: date, range: 0...100, highest: false)
            record(&result.lowestRestingHeartRate, day.restingHeartRate, date: date, range: 1...300, highest: false)
            record(&result.highestRestingHeartRate, day.restingHeartRate, date: date, range: 1...300)
            record(&result.lowestHRV, day.hrv, date: date, range: 0...1000, highest: false)
            record(&result.highestHRV, day.hrv, date: date, range: 0...1000)
            record(&result.maxHeartRate, rates.map(\.bpm).max(), date: date, range: 1...300)
            record(&result.longestSleepMinutes, (1...1440).contains(day.sleepMinutes) ? Double(day.sleepMinutes) : nil, date: date, range: 1...1440)
            if validSleep, (day.sleepPerformance ?? 0) >= 70 { sleep70.insert(date) }
            if validRecovery, (day.recovery ?? 0) >= 67 { green.insert(date) }
            if validStrain, (day.strain ?? 0) >= 10 { strain10.insert(date) }
        }
        result.savedDays = logged.count
        result.longestLoggedDayStreak = longest(logged)
        result.longestSleep70Streak = longest(sleep70)
        result.longestGreenRecoveryStreak = longest(green)
        result.longestStrain10Streak = longest(strain10)
        var cursor = logged.contains(today) ? today : DayCalendar.utc.date(byAdding: .day, value: -1, to: today) ?? today
        while logged.contains(cursor) {
            result.currentLoggedDayStreak += 1
            guard let previous = DayCalendar.utc.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return result
    }
    private static func longest(_ dates: Set<Date>) -> Int {
        var last: Date?, current = 0, best = 0
        for date in dates.sorted() {
            current = last.flatMap { DayCalendar.utc.date(byAdding: .day, value: 1, to: $0) } == date ? current + 1 : 1
            best = max(best, current); last = date
        }
        return best
    }
    private static func validDate(_ value: Date) -> Bool {
        value.timeIntervalSince1970.isFinite && (-62_135_596_800...253_402_300_799.999).contains(value.timeIntervalSince1970)
    }
}

public struct PersonalizedExportMetadata: Codable, Equatable, Sendable {
    public let format: String
    public let version: Int
    public let exportedAt: Date
    public let timeZone: String
    public let profileSource: String
    public let highlightsSource: String
    public let rangeStart: Date?
    public let rangeEnd: Date?
    public let includesExamples: Bool
}
public struct PersonalizedMeasurementArchive: Codable, Equatable, Sendable {
    public let days: [DailySnapshot]
    public let profile: ProfilePersonalization?
    public let highlights: ProfileHighlights
    public let metadata: PersonalizedExportMetadata
}
public struct ImportedMeasurementArchive: Sendable {
    public let days: [DailySnapshot]
    public let profile: ProfilePersonalization?
}
