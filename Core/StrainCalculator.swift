import Foundation

public enum StrainError: Error, LocalizedError, Equatable {
    case invalidInput, invalidProfile, unorderedSamples, missingLookup
    public var errorDescription: String? {
        switch self {
        case .invalidInput: return "Strain inputs must contain finite heart rates and valid timestamps."
        case .invalidProfile: return "Maximum heart rate plus three must exceed resting heart rate."
        case .unorderedSamples: return "Strain samples must have unique, increasing timestamps."
        case .missingLookup: return "The recovered strain lookup table is unavailable or invalid."
        }
    }
}

/// A reference transcription of selected Android strain helpers, not a complete WHOOP scorer.
/// Sample times are interpreted as epoch milliseconds at this public API boundary.
public enum StrainCalculator {
    public struct LookupEntry: Equatable, Sendable {
        public let lowerThreshold: Double
        public let score: Double
    }

    private struct TableFile: Decodable { let rows: [[Double]] }
    private static let loadedTable: [LookupEntry]? = {
        guard let url = Bundle.module.url(forResource: "strain-lookup", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(TableFile.self, from: data), decoded.rows.count == 211 else { return nil }
        var values: [LookupEntry] = []
        for (index, row) in decoded.rows.enumerated() {
            guard row.count == 2, row.allSatisfy(\.isFinite), row[0] >= 0,
                  abs(row[1] - Double(index) / 10) < 1e-12,
                  values.last.map({ $0.lowerThreshold < row[0] }) ?? true else { return nil }
            values.append(.init(lowerThreshold: row[0], score: row[1]))
        }
        return values
    }()

    public static func lookupEntries() throws -> [LookupEntry] {
        guard let entries = loadedTable else { throw StrainError.missingLookup }
        return entries
    }

    /// Matches the recovered finite-input interval loop, including its negative-input final-row fallback.
    /// Normal callers supply nonnegative raw strain. NaN/infinity are rejected by this Swift boundary.
    public static func scaledScore(raw: Double) throws -> Double {
        guard raw.isFinite else { throw StrainError.invalidInput }
        let entries = try lookupEntries()
        for index in entries.indices {
            let next = min(index + 1, entries.count - 1)
            if index == next || (raw >= entries[index].lowerThreshold && raw < entries[next].lowerThreshold) {
                return entries[index].score
            }
        }
        return 0 // Unreachable for a valid, nonempty recovered table.
    }

    /// maximumHeartRate is M, before the recovered helper's +3 offset.
    public static func reserve(heartRate: Double, restingHeartRate: Double, maximumHeartRate: Double) throws -> Double {
        guard heartRate.isFinite, restingHeartRate.isFinite, maximumHeartRate.isFinite else { throw StrainError.invalidInput }
        guard maximumHeartRate + 3 > restingHeartRate else { throw StrainError.invalidProfile }
        let q = min(1, max(0, (heartRate - restingHeartRate) / (maximumHeartRate + 3 - restingHeartRate)))
        return q <= 0.3 ? 0 : q
    }

    /// Exact selected logistic helper; duration caps belong to the separate timescale helper.
    public static func weightedContribution(reserve: Double, durationSeconds: Double) throws -> Double {
        guard reserve.isFinite, durationSeconds.isFinite else { throw StrainError.invalidInput }
        return reserve <= 0 ? 0 : 16 / (exp((1 - reserve) / 0.15) + 1) * durationSeconds
    }

    /// Expects already-smoothed samples. This does not invent a missing physiological baseline,
    /// run the Android stateful smoothing pipeline, or compute a daily/server score.
    ///
    /// The terminal timestamp argument is the literal `j` of Android vd0.o.l:
    /// multi-sample `0` repeats the preceding duration; singleton `-1` gives one second.
    /// The shipped singleton expression mixes units; it is intentionally preserved below.
    public static func rawContribution(
        smoothedSamples: [HeartRateSample], restingHeartRate: Double,
        maximumHeartRate: Double, terminalTimestampMilliseconds: Int64 = 0
    ) throws -> Double {
        guard restingHeartRate.isFinite, maximumHeartRate.isFinite else { throw StrainError.invalidInput }
        guard !smoothedSamples.isEmpty else { return 0 }
        let times = try timestamps(smoothedSamples)
        let m = max(maximumHeartRate, smoothedSamples.map(\.bpm).max()!)
        guard m + 3 > restingHeartRate else { throw StrainError.invalidProfile }
        let scales = durations(times, terminal: terminalTimestampMilliseconds)
        var sum = 0.0
        for (sample, scale) in zip(smoothedSamples, scales) {
            let q = try reserve(heartRate: sample.bpm, restingHeartRate: restingHeartRate, maximumHeartRate: m)
            sum += try weightedContribution(reserve: q, durationSeconds: scale)
        }
        guard sum.isFinite else { throw StrainError.invalidInput }
        return min(1, max(0, sum / 691_200))
    }

    /// The recovered 0.25 quantile helper, exposed for independent inspection and reference tests.
    public static func quantile(_ values: [Double], fraction: Double = 0.25) throws -> Double {
        guard fraction.isFinite, values.allSatisfy(\.isFinite) else { throw StrainError.invalidInput }
        let sorted = values.sorted()
        guard let first = sorted.first else { return 0 }
        guard sorted.count > 1 else { return first }
        if fraction <= 0 { return first }
        if fraction >= 1 { return sorted.last! }
        let position = fraction * Double(sorted.count - 1)
        let lower = Int(position)
        return sorted[lower] + (position - Double(lower)) * (sorted[lower + 1] - sorted[lower])
    }

    /// Literal recovered timescale behavior. Kept public so integration can inspect its quirks.
    public static func durationScales(
        for smoothedSamples: [HeartRateSample], terminalTimestampMilliseconds: Int64 = 0
    ) throws -> [Double] {
        durations(try timestamps(smoothedSamples), terminal: terminalTimestampMilliseconds)
    }

    private static func timestamps(_ samples: [HeartRateSample]) throws -> [Int64] {
        var result: [Int64] = []
        for sample in samples {
            let raw = sample.timestamp.timeIntervalSince1970 * 1000
            guard sample.bpm.isFinite, raw.isFinite,
                  raw > Double(Int64.min) + 2048, raw < Double(Int64.max) - 2048 else { throw StrainError.invalidInput }
            let milliseconds = Int64(raw.rounded())
            guard result.last.map({ milliseconds > $0 }) ?? true else { throw StrainError.unorderedSamples }
            result.append(milliseconds)
        }
        return result
    }

    private static func durations(_ times: [Int64], terminal: Int64) -> [Double] {
        guard let last = times.last else { return [] }
        if times.count == 1 {
            // Java performs integer timestamp/1000 before subtracting the undivided j.
            return [terminal == -1 ? 1 : min(Double(terminal) - Double(last / 1000), 3)]
        }
        var scales = zip(times.dropFirst(), times).map { (Double($0.0) - Double($0.1)) / 1000 }
        scales.append(terminal == 0 ? scales.last! : (Double(terminal) - Double(last)) / 1000)
        return scales.map { min($0, 3) }
    }
}
