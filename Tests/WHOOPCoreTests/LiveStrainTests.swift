import XCTest
@testable import WHOOPCore

final class LiveStrainTests: XCTestCase {
    private let epoch = 1_700_000_000.0

    private func sample(_ index: Int, bpm: Double = 150, step: Double = 1) -> HeartRateSample {
        .init(timestamp: Date(timeIntervalSince1970: epoch + Double(index) * step), bpm: bpm)
    }

    private func engine() throws -> LiveStrainEngine {
        try .init(restingHeartRate: 60, maximumHeartRate: 200)
    }

    private func perSecond(_ bpm: Double, maximum: Double = 200) throws -> Double {
        let q = try StrainCalculator.reserve(heartRate: bpm, restingHeartRate: 60, maximumHeartRate: max(maximum, bpm))
        return try StrainCalculator.weightedContribution(reserve: q, durationSeconds: 1) / 691_200
    }

    func testThirtySampleDelayAndPendingObservedDuration() throws {
        var value = try engine()
        for index in 0..<30 { try value.append(sample(index)) }
        XCTAssertEqual(value.sampleCount, 30)
        XCTAssertEqual(value.processedSampleCount, 0)
        XCTAssertEqual(value.rawStrain, 0)
        try value.append(sample(30))
        XCTAssertEqual(value.rawStrain, 0) // One smoothed point supplies no interval.
        try value.append(sample(31))
        XCTAssertEqual(value.processedSampleCount, 1)
        XCTAssertEqual(value.pendingSampleCount, 31)
        XCTAssertEqual(value.rawStrain, try perSecond(150), accuracy: 1e-15)
    }

    func testConstantSeriesCountsEachMatureIntervalExactlyOnce() throws {
        var value = try engine()
        for index in 0..<500 { try value.append(sample(index)) }
        XCTAssertEqual(value.processedSampleCount, 469)
        XCTAssertEqual(value.rawStrain, try perSecond(150) * 469, accuracy: 1e-13)
        XCTAssertEqual(value.scaledScore, try StrainCalculator.scaledScore(raw: value.rawStrain))
    }

    func testIntervalCapUsesRealElapsedTimeWithoutFillingGap() throws {
        var value = try engine()
        for index in 0..<40 { try value.append(sample(index, step: 4)) }
        XCTAssertEqual(value.rawStrain, try perSecond(150) * 9 * 3, accuracy: 1e-14)
    }

    func testBelowReserveCutoffIsZero() throws {
        var value = try engine()
        for index in 0..<100 { try value.append(sample(index, bpm: 90)) }
        XCTAssertEqual(value.processedSampleCount, 69)
        XCTAssertEqual(value.rawStrain, 0)
        XCTAssertEqual(value.scaledScore, 0)
    }

    func testObservedMaximumRaisesPointScoringMaximum() throws {
        var value = try engine()
        for index in 0..<40 { try value.append(sample(index, bpm: 220)) }
        XCTAssertEqual(value.rawStrain, try perSecond(220) * 9, accuracy: 1e-14)
    }

    /// Independent whole-array reference: no leftovers, streaming cursor or engine smoothing.
    private func batchReference(_ points: [HeartRateSample]) throws -> Double {
        guard points.count > 31 else { return 0 }
        var smoothed: [HeartRateSample] = []
        for index in 0..<(points.count - 30) {
            let window = points[max(0, index - 30)..<(index + 30)].map(\.bpm).sorted()
            let position = Double(window.count - 1) * 0.25
            let lower = Int(position)
            let rate = window[lower] + (position - Double(lower)) * (window[min(lower + 1, window.count - 1)] - window[lower])
            smoothed.append(.init(timestamp: points[index].timestamp, bpm: rate))
        }
        // Terminal equals the final point: the last duration is zero, not extrapolated.
        return try StrainCalculator.rawContribution(smoothedSamples: smoothed, restingHeartRate: 60,
            maximumHeartRate: 200,
            terminalTimestampMilliseconds: Int64((smoothed.last!.timestamp.timeIntervalSince1970 * 1000).rounded()))
    }

    func testStreamingMatchesIndependentBatchAcrossChunkSizes() throws {
        var elapsed = 0.0
        let points: [HeartRateSample] = (0..<400).map { index in
            elapsed += [0.5, 1.0, 2.0, 4.0][index % 4]
            return .init(timestamp: Date(timeIntervalSince1970: epoch + elapsed), bpm: Double(100 + (index * 17) % 90))
        }
        let expected = try batchReference(points)
        for size in [1, 2, 7, 29, 30, 31, 60, 400] {
            var value = try engine()
            for start in stride(from: 0, to: points.count, by: size) {
                for point in points[start..<min(start + size, points.count)] { try value.append(point) }
            }
            XCTAssertEqual(value.rawStrain, expected, accuracy: 1e-13, "chunk size \(size)")
            XCTAssertEqual(value.processedSampleCount, 369)
        }
    }

    func testDuplicateAndOutOfOrderRejectionDoesNotChangeScoreOrPending() throws {
        var value = try engine()
        for index in 0..<50 { try value.append(sample(index)) }
        let raw = value.rawStrain
        let buffered = value.bufferedSampleCount
        for point in [sample(49), sample(48), sample(49, bpm: 180),
                      .init(timestamp: sample(49).timestamp.addingTimeInterval(0.0004), bpm: 150)] {
            XCTAssertThrowsError(try value.append(point)) { XCTAssertEqual($0 as? LiveStrainError, .unorderedTimestamp) }
            XCTAssertEqual(value.rawStrain, raw)
            XCTAssertEqual(value.sampleCount, 50)
            XCTAssertEqual(value.bufferedSampleCount, buffered)
        }
        try value.append(sample(50))
        XCTAssertEqual(value.rawStrain - raw, try perSecond(150), accuracy: 1e-14)
    }

    func testThirtySecondGapIsRejectedWithoutExtrapolating() throws {
        var value = try engine()
        for index in 0..<40 { try value.append(sample(index)) }
        let raw = value.rawStrain
        for index in [69, 70, 100_000] {
            XCTAssertThrowsError(try value.append(sample(index))) { XCTAssertEqual($0 as? LiveStrainError, .gapTooLarge) }
            XCTAssertEqual(value.sampleCount, 40)
            XCTAssertEqual(value.rawStrain, raw)
        }
        try value.append(sample(40))
        XCTAssertEqual(value.processedSampleCount, 10)
    }

    func testInvalidProfilesAndNonfiniteSamplesAreRejected() throws {
        for (rest, maximum) in [(Double.nan, 200.0), (60, .infinity), (0, 200), (200, 200), (60, 301)] {
            XCTAssertThrowsError(try LiveStrainEngine(restingHeartRate: rest, maximumHeartRate: maximum))
        }
        var value = try engine()
        for bpm in [Double.nan, .infinity, -.infinity, 0, -1, 301] {
            XCTAssertThrowsError(try value.append(sample(0, bpm: bpm)))
        }
        for time in [Double.nan, .infinity, -.infinity, -1, Double(Int64.max)] {
            XCTAssertThrowsError(try value.append(.init(timestamp: Date(timeIntervalSince1970: time), bpm: 150)))
        }
        XCTAssertEqual(value.sampleCount, 0)
        XCTAssertEqual(value.rawStrain, 0)
    }

    func testRetainedWindowIsBoundedOverLongStream() throws {
        var value = try engine()
        for index in 0..<10_000 {
            try value.append(sample(index))
            XCTAssertLessThanOrEqual(value.bufferedSampleCount, 60)
            XCTAssertLessThanOrEqual(value.pendingSampleCount, 31)
        }
        XCTAssertEqual(value.processedSampleCount, 9_969)
    }

    func testRecoveredGapTrimPreservesLiteralAsymmetricBounds() throws {
        func window(gapIndex: Int, gap: Int64) -> [LiveStrainPoint] {
            (0..<60).map { index in
                .init(milliseconds: Int64(index) * 1000 + (index > gapIndex ? gap - 1000 : 0), bpm: Double(100 + index))
            }
        }
        XCTAssertEqual(try LiveStrainEngine.recoveredSmoothedHeartRate(in: window(gapIndex: 29, gap: 29_999)), 114.75)
        // Gap at 29 skips indices 0...29; gap at 30 keeps 0..<30 (also drops 30).
        XCTAssertEqual(try LiveStrainEngine.recoveredSmoothedHeartRate(in: window(gapIndex: 29, gap: 30_000)), 137.25)
        XCTAssertEqual(try LiveStrainEngine.recoveredSmoothedHeartRate(in: window(gapIndex: 30, gap: 30_000)), 107.25)
    }

    func testLiteralSingletonHelperRemainsUnchangedAndIsNotUsedToInventLiveDuration() throws {
        let point = sample(0)
        let milliseconds = Int64((point.timestamp.timeIntervalSince1970 * 1000).rounded())
        XCTAssertEqual(try StrainCalculator.durationScales(for: [point], terminalTimestampMilliseconds: milliseconds), [3])
        var value = try engine()
        for index in 0..<31 { try value.append(sample(index)) }
        XCTAssertEqual(value.rawStrain, 0)
        XCTAssertEqual(value.processedSampleCount, 0)
    }
}
