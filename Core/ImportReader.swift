import Foundation

public enum ImportError: Error, LocalizedError, Equatable {
    case tooLarge, tooManyRows, unsupported, noData
    case invalid(String)
    public var errorDescription: String? {
        switch self {
        case .tooLarge: return "Choose a file smaller than 10 MB."
        case .tooManyRows: return "This file has more than 100,000 heart-rate rows."
        case .unsupported: return "Choose a JSON archive or a heart-rate CSV file."
        case .noData: return "The file contains no daily or heart-rate data."
        case .invalid(let detail): return detail
        }
    }
}

public enum ImportReader {
    public static let maximumBytes = 10 * 1024 * 1024
    public static let maximumRows = 100_000

    public static func read(_ data: Data, filename: String) throws -> [DailySnapshot] {
        guard data.count <= maximumBytes else { throw ImportError.tooLarge }
        guard !data.isEmpty else { throw ImportError.noData }
        switch URL(fileURLWithPath: filename).pathExtension.lowercased() {
        case "csv": return try readCSV(data)
        case "json": return try readJSON(data)
        default: throw ImportError.unsupported
        }
    }

    public static func jsonEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var value = encoder.singleValueContainer()
            try value.encode(formatter.string(from: date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    /// Paired date codec for app persistence as well as imported day archives.
    public static func jsonDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        let parser = DateParser()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            guard let date = parser.parse(value, allowDayOnly: true) else {
                throw ImportError.invalid("Use ISO 8601 dates with an explicit timezone, such as 2026-11-08T08:00:00Z.")
            }
            return date
        }
        return decoder
    }

    private static func readJSON(_ data: Data) throws -> [DailySnapshot] {
        let decoder = jsonDecoder()
        let snapshots: [DailySnapshot]
        do {
            // A leading JSON array and a {"days": [...]} archive are both supported.
            if data.first(where: { ![9, 10, 13, 32].contains($0) }) == 91 {
                snapshots = try decoder.decode([DailySnapshot].self, from: data)
            } else {
                snapshots = try decoder.decode(DayArchive.self, from: data).days
            }
        } catch let error as ImportError { throw error }
        catch {
            throw ImportError.invalid("The JSON archive is invalid. It must contain a days array with ISO 8601 dates and numeric metric values.")
        }
        guard !snapshots.isEmpty else { throw ImportError.noData }
        guard snapshots.count <= maximumRows else { throw ImportError.tooManyRows }
        var days = Set<Date>()
        var sampleCount = 0
        return try snapshots.map { original in
            var day = original
            day.date = DayCalendar.start(of: day.date)
            guard days.insert(day.date).inserted else {
                throw ImportError.invalid("The JSON archive contains more than one entry for the same UTC day.")
            }
            sampleCount += day.heartRates.count
            guard sampleCount <= maximumRows else { throw ImportError.tooManyRows }
            try validate(day)
            day.heartRates = try uniqueSamples(day.heartRates)
            // Preserve explicit example provenance when an example archive is exported/reimported.
            // Missing source defaults to imported in the model decoder; CSV is always imported.
            return day
        }.sorted { $0.date < $1.date }
    }

    private static func readCSV(_ data: Data) throws -> [DailySnapshot] {
        guard var text = String(data: data, encoding: .utf8) else {
            throw ImportError.invalid("The CSV file must use UTF-8 text.")
        }
        if text.first == "\u{feff}" { text.removeFirst() }
        let rows = try csvRows(text)
        guard let header = rows.first else { throw ImportError.noData }
        let names = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard Set(names).count == names.count,
              let timeIndex = names.firstIndex(of: "timestamp"),
              let rateIndex = names.firstIndex(of: "heart_rate") else {
            throw ImportError.invalid("CSV headers must include timestamp and heart_rate, with no duplicate column names.")
        }
        guard rows.count > 1 else { throw ImportError.noData }
        var samples: [HeartRateSample] = []
        let parser = DateParser()
        for (offset, row) in rows.dropFirst().enumerated() {
            let number = offset + 2
            guard row.count == header.count else {
                throw ImportError.invalid("CSV row \(number) has the wrong number of columns.")
            }
            let time = row[timeIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            let heartRate = row[rateIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let date = parser.parse(time, allowDayOnly: false),
                  let bpm = Double(heartRate), bpm.isFinite, bpm > 0, bpm <= 300 else {
                throw ImportError.invalid("CSV row \(number) needs an ISO 8601 timestamp with timezone and a heart_rate above 0 and at most 300.")
            }
            samples.append(.init(timestamp: date, bpm: bpm))
        }
        let grouped = Dictionary(grouping: try uniqueSamples(samples)) { DayCalendar.start(of: $0.timestamp) }
        return grouped.keys.sorted().map { date in
            var day = DailySnapshot.empty(on: date)
            day.heartRates = grouped[date] ?? []
            return day
        }
    }

    private final class DateParser {
        let fractional = ISO8601DateFormatter()
        let whole = ISO8601DateFormatter()
        let day = DateFormatter()
        init() {
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            whole.formatOptions = [.withInternetDateTime]
            day.calendar = DayCalendar.utc
            day.locale = Locale(identifier: "en_US_POSIX")
            day.timeZone = TimeZone(secondsFromGMT: 0)
            day.dateFormat = "yyyy-MM-dd"
            day.isLenient = false
        }
        func parse(_ string: String, allowDayOnly: Bool) -> Date? {
            if let date = fractional.date(from: string) { return date }
            if let date = whole.date(from: string) { return date }
            if allowDayOnly, string.count == 10,
               let date = day.date(from: string), day.string(from: date) == string { return date }
            return nil
        }
    }

    private static func uniqueSamples(_ samples: [HeartRateSample]) throws -> [HeartRateSample] {
        var seen: [Date: Double] = [:]
        for sample in samples {
            if let old = seen[sample.timestamp], old != sample.bpm {
                throw ImportError.invalid("The file has conflicting heart rates at the same timestamp.")
            }
            seen[sample.timestamp] = sample.bpm
        }
        return seen.keys.sorted().map { .init(timestamp: $0, bpm: seen[$0]!) }
    }

    private static func validate(_ day: DailySnapshot) throws {
        func optionalRange<T: Comparable>(_ value: T?, _ range: ClosedRange<T>) -> Bool {
            value.map(range.contains) ?? true
        }
        guard optionalRange(day.recovery, 0...100), optionalRange(day.sleepPerformance, 0...100),
              optionalRange(day.strain, 0.0...21.0),
              (0...1440).contains(day.sleepMinutes), (0...1440).contains(day.sleepNeededMinutes),
              optionalRange(day.restingHeartRate, 1.0...300.0), optionalRange(day.hrv, 0.0...1000.0),
              optionalRange(day.respiratoryRate, 0.0...100.0),
              (0...1_000_000).contains(day.steps), day.energyKcal.isFinite, day.energyKcal >= 0,
              day.energyKcal <= 100_000 else {
            throw ImportError.invalid("A daily metric is outside the supported range. Recovery and sleep scores must be 0–100, and strain must be 0–21.")
        }
        for sample in day.heartRates {
            guard sample.bpm.isFinite, sample.bpm > 0, sample.bpm <= 300,
                  DayCalendar.start(of: sample.timestamp) == day.date else {
                throw ImportError.invalid("Heart-rate samples must be valid and belong to their archive entry's UTC day.")
            }
        }
    }

    /// RFC4180-style fields, including doubled quotes and CRLF. No silent quote repair.
    private static func csvRows(_ text: String) throws -> [[String]] {
        let chars = Array(text)
        var rows: [[String]] = [], row: [String] = [], field = ""
        var quoted = false, closedQuote = false, index = 0
        func finishField() throws {
            row.append(field); field = ""; closedQuote = false
            if row.count > 64 { throw ImportError.invalid("CSV files may have at most 64 columns.") }
        }
        func finishRow() throws {
            try finishField()
            if row.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { rows.append(row) }
            row = []
            if rows.count > maximumRows + 1 { throw ImportError.tooManyRows }
        }
        while index < chars.count {
            let char = chars[index]
            if quoted {
                if char == "\"" {
                    if index + 1 < chars.count, chars[index + 1] == "\"" { field.append("\""); index += 1 }
                    else { quoted = false; closedQuote = true }
                } else { field.append(char) }
            } else if char == "," { try finishField() }
            else if char == "\n" || char == "\r" || char == "\r\n" {
                try finishRow()
                if char == "\r", index + 1 < chars.count, chars[index + 1] == "\n" { index += 1 }
            } else if char == "\"" {
                guard field.isEmpty, !closedQuote else { throw ImportError.invalid("The CSV contains an unexpected quote.") }
                quoted = true
            } else {
                if closedQuote {
                    guard char == " " || char == "\t" else { throw ImportError.invalid("The CSV has text after a closing quote.") }
                } else { field.append(char) }
            }
            index += 1
        }
        guard !quoted else { throw ImportError.invalid("The CSV ends inside a quoted field.") }
        if !field.isEmpty || !row.isEmpty || closedQuote { try finishRow() }
        return rows
    }
}
