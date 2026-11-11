import Foundation

public enum LiveStrainError: Error, LocalizedError, Equatable {
    case invalidProfile, invalidSample, unorderedTimestamp, gapTooLarge

    public var errorDescription: String? {
        switch self {
        case .invalidProfile: return "Enter finite resting and maximum heart rates between 0 and 300, with maximum greater than resting."
        case .invalidSample: return "Heart rate must be finite, greater than zero and at most 300, with a valid nonnegative timestamp."
        case .unorderedTimestamp: return "Live samples must have unique, increasing millisecond timestamps."
        case .gapTooLarge: return "The heart rate stream has a gap of 30 seconds or more. Start a new local estimate."
        }
    }
}

/// A local streaming estimate using recovered Android smoothing and strain helpers.
/// This deliberately avoids Android's repeated last-used point and inconsistent singleton
/// duration. It is not numerically equivalent to the Android controller or server scores.
/// Dates are rounded to epoch milliseconds; 30 future samples are required for smoothing.
public struct LiveStrainEngine: Sendable {
    public let restingHeartRate: Double
    public let maximumHeartRate: Double
    public private(set) var rawStrain = 0.0
    public private(set) var scaledScore = 0.0
    public private(set) var sampleCount = 0
    /// Number of smoothed points whose following observed interval has been counted once.
    public private(set) var processedSampleCount = 0
    /// Accepted points not yet billed, including the pending smoothed interval endpoint.
    public var pendingSampleCount: Int { sampleCount - processedSampleCount }
    /// Retained source context, bounded by 60 after every append (61 transiently).
    public var bufferedSampleCount: Int { buffer.count }

    private var buffer: [LiveStrainPoint] = []
    private var bufferStartIndex = 0
    private var nextSmoothingIndex = 0
    private var pending: LiveStrainPoint?
    private var lastTimestamp: Int64?

    public init(restingHeartRate: Double, maximumHeartRate: Double) throws {
        guard restingHeartRate.isFinite, maximumHeartRate.isFinite,
              restingHeartRate > 0, maximumHeartRate > restingHeartRate,
              maximumHeartRate <= 300 else { throw LiveStrainError.invalidProfile }
        _ = try StrainCalculator.lookupEntries()
        self.restingHeartRate = restingHeartRate
        self.maximumHeartRate = maximumHeartRate
    }

    /// A rejected point leaves the engine unchanged. No missing samples or durations are
    /// synthesized. A gap >= 30,000 ms requires the caller to start a separate estimate.
    public mutating func append(_ sample: HeartRateSample) throws {
        let point = try LiveStrainPoint(sample)
        if let previous = lastTimestamp {
            guard point.milliseconds > previous else { throw LiveStrainError.unorderedTimestamp }
            // Both timestamps are nonnegative, so subtraction cannot overflow Int64.
            guard point.milliseconds - previous < 30_000 else { throw LiveStrainError.gapTooLarge }
        }

        // Validate all fallible work before committing state, including the pending interval.
        var extended = buffer
        extended.append(point)
        var newSmoothed: LiveStrainPoint?
        var contribution = 0.0
        if nextSmoothingIndex < sampleCount + 1 - 30 {
            let lower = max(0, nextSmoothingIndex - 30) - bufferStartIndex
            let upper = nextSmoothingIndex + 30 - bufferStartIndex // Exclusive, as shipped.
            let center = extended[nextSmoothingIndex - bufferStartIndex]
            let rate = try Self.recoveredSmoothedHeartRate(in: Array(extended[lower..<upper]))
            let smoothed = LiveStrainPoint(milliseconds: center.milliseconds, bpm: rate)
            if let pending {
                let seconds = min(Double(smoothed.milliseconds - pending.milliseconds) / 1000, 3)
                let reserve = try StrainCalculator.reserve(
                    heartRate: pending.bpm, restingHeartRate: restingHeartRate,
                    maximumHeartRate: max(maximumHeartRate, pending.bpm))
                contribution = try StrainCalculator.weightedContribution(reserve: reserve, durationSeconds: seconds) / 691_200
            }
            newSmoothed = smoothed
        }
        let updatedRaw = rawStrain + min(1, max(0, contribution))
        let updatedScore = try StrainCalculator.scaledScore(raw: updatedRaw)

        buffer = extended
        lastTimestamp = point.milliseconds
        sampleCount += 1
        if let newSmoothed {
            if pending != nil { processedSampleCount += 1 }
            pending = newSmoothed
            nextSmoothingIndex += 1
        }
        rawStrain = updatedRaw
        scaledScore = updatedScore

        // Retain precisely the left context needed by the next unprocessed center.
        let retainFrom = max(0, nextSmoothingIndex - 30)
        let discard = retainFrom - bufferStartIndex
        if discard > 0 {
            buffer.removeFirst(discard)
            bufferStartIndex = retainFrom
        }
    }

    /// Literal gap selection from vd0.o.n, including its surprising >=30 prefix bound.
    /// The public stream rejects such gaps; keeping this separate makes that source rule
    /// inspectable without silently substituting a different trim rule.
    static func recoveredSmoothedHeartRate(in window: [LiveStrainPoint]) throws -> Double {
        var selected = window[...]
        var largestGap: Int64 = 0
        var gapIndex = 0
        for index in 0..<max(0, window.count - 1) {
            let gap = window[index + 1].milliseconds - window[index].milliseconds
            if gap > largestGap { largestGap = gap; gapIndex = index }
        }
        if largestGap >= 30_000 {
            selected = gapIndex >= 30 ? window.prefix(gapIndex) : window.dropFirst(gapIndex + 1)
        }
        return try StrainCalculator.quantile(selected.map(\.bpm))
    }
}

struct LiveStrainPoint: Sendable {
    let milliseconds: Int64
    let bpm: Double

    init(milliseconds: Int64, bpm: Double) { self.milliseconds = milliseconds; self.bpm = bpm }

    init(_ sample: HeartRateSample) throws {
        let time = sample.timestamp.timeIntervalSince1970 * 1000
        guard sample.bpm.isFinite, sample.bpm > 0, sample.bpm <= 300,
              time.isFinite, time >= 0, time < Double(Int64.max) - 2048 else {
            throw LiveStrainError.invalidSample
        }
        milliseconds = Int64(time.rounded())
        bpm = sample.bpm
    }
}
