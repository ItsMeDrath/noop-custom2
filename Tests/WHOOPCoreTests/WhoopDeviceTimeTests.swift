import Foundation
import XCTest
@testable import WHOOPCore

final class WhoopDeviceTimeTests: XCTestCase {
    func testUnixEpochAndKnownUTCInstant() throws {
        XCTAssertEqual(try XCTUnwrap(WhoopDeviceTime(seconds: 0, ticks: 0)).date,
                       Date(timeIntervalSince1970: 0))
        // Independently specified UTC fixture: 2000-01-01T00:00:00.500Z.
        let value = try XCTUnwrap(WhoopDeviceTime(seconds: 946_684_800, ticks: 16_384))
        XCTAssertEqual(value.unixMilliseconds, 946_684_800_500)
        XCTAssertEqual(ISO8601DateFormatter().string(from: value.date), "2000-01-01T00:00:00Z")
        XCTAssertEqual(value.date.timeIntervalSince1970, 946_684_800.5)
    }

    func testMillisecondRoundingAndSecondCarry() throws {
        // 16 ticks = 0.48828125ms, 17 = 0.518798828125ms;
        // 2048 ticks = exactly 62.5ms, with ties rounded toward positive infinity.
        let fixtures: [(UInt16, Int64)] = [(1, 0), (16, 0), (17, 1), (2048, 63), (16_384, 500), (32_767, 1000)]
        for (ticks, milliseconds) in fixtures {
            let value = try XCTUnwrap(WhoopDeviceTime(seconds: 0, ticks: ticks))
            XCTAssertEqual(value.unixMilliseconds, milliseconds, "ticks=\(ticks)")
        }
    }

    func testUnsignedSecondsAndAndroidDoubleOperationOrder() throws {
        let after2038 = try XCTUnwrap(WhoopDeviceTime(seconds: 0x8000_0000, ticks: 0))
        XCTAssertEqual(after2038.unixMilliseconds, 2_147_483_648_000)
        let upper = try XCTUnwrap(WhoopDeviceTime(seconds: .max, ticks: 32_767))
        XCTAssertEqual(upper.unixMilliseconds, 4_294_967_296_000)
        // At this magnitude the double ULP is 1/2048ms. 3883 ticks are
        // 118.499755859375ms, rounded to 118.5 when added to whole milliseconds.
        let boundary = try XCTUnwrap(WhoopDeviceTime(seconds: .max, ticks: 3883))
        XCTAssertEqual(boundary.unixMilliseconds, 4_294_967_295_119)
    }

    func testRejectsNoncanonicalTicksBeforeNarrowing() {
        XCTAssertNil(WhoopDeviceTime(seconds: 1, ticks: 32_768))
        XCTAssertNil(WhoopDeviceTime(seconds: 1, ticks: .max))
        XCTAssertNil(WhoopDeviceTime(seconds: 1, ticks32: 65_536))
        XCTAssertNil(WhoopDeviceTime(seconds: 1, ticks32: .max))
        XCTAssertEqual(WhoopDeviceTime(seconds: 1, ticks32: 16_384),
                       WhoopDeviceTime(seconds: 1, ticks: 16_384))
    }

    func testCallerBoundsRejectUnsetOrOutOfSessionClock() throws {
        let start = Date(timeIntervalSince1970: 946_684_800)
        let end = start.addingTimeInterval(60)
        let value = try XCTUnwrap(WhoopDeviceTime(seconds: 946_684_800, ticks: 0))
        XCTAssertEqual(value.validatedDate(in: start...end), start)
        XCTAssertNil(value.validatedDate(in: end...end.addingTimeInterval(60)))
        XCTAssertNil(try XCTUnwrap(WhoopDeviceTime(seconds: 0, ticks: 0)).validatedDate(in: start...end))
    }
}
