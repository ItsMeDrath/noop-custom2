import Foundation
import XCTest
@testable import WHOOPCore

final class SleepIntervalTests: XCTestCase {
    private func interval(_ start: Double, _ end: Double) -> DateInterval {
        DateInterval(start: Date(timeIntervalSince1970: start), end: Date(timeIntervalSince1970: end))
    }

    func testOverlappingStagesAndDuplicateSourcesCountOnce() {
        let episodes = [interval(120, 420), interval(0, 240), interval(0, 240), interval(180, 300)]
        XCTAssertEqual(SleepIntervals.seconds(episodes, within: interval(0, 600)), 420)
    }

    func testDisjointEpisodesPreserveAwakeGap() {
        XCTAssertEqual(SleepIntervals.minutes([interval(0, 120), interval(180, 300)], within: interval(0, 600)), 4)
    }

    func testCrossMidnightSleepClipsToEachUTCDay() {
        let date = DayCalendar.start(of: Date(timeIntervalSince1970: 1_793_491_200))
        let next = date.addingTimeInterval(86_400)
        let sleep = DateInterval(start: next.addingTimeInterval(-3_600), end: next.addingTimeInterval(7_200))
        XCTAssertEqual(SleepIntervals.minutes([sleep], within: DateInterval(start: date, end: next)), 60)
        XCTAssertEqual(SleepIntervals.minutes([sleep], within: DateInterval(start: next, duration: 86_400)), 120)
    }

    func testTouchingBoundariesEmptyRangesAndOutsideIntervals() {
        XCTAssertEqual(SleepIntervals.seconds([interval(0, 60), interval(60, 120)], within: interval(0, 120)), 120)
        XCTAssertEqual(SleepIntervals.seconds([interval(0, 60), interval(120, 180)], within: interval(60, 120)), 0)
        XCTAssertEqual(SleepIntervals.seconds([interval(0, 120)], within: interval(60, 60)), 0)
        XCTAssertEqual(SleepIntervals.seconds([], within: interval(0, 120)), 0)
    }

    func testRoundingOccursAfterUnionAndRangeIsMaximum() {
        XCTAssertEqual(SleepIntervals.minutes([interval(0, 35), interval(40, 75)], within: interval(0, 100)), 1)
        XCTAssertEqual(SleepIntervals.seconds([interval(-1_000, 1_000)], within: interval(0, 100)), 100)
    }
}
