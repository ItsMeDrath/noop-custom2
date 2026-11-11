import Foundation
import XCTest
@testable import WHOOPCore

final class WhoopHistoryTests: XCTestCase {
    private struct Fixtures: Decodable {
        let fixtures: [Fixture]
        struct Fixture: Decodable {
            let name: String
            let generation: WhoopGeneration
            let revision: UInt8
            let payloadHex: String
            let frameHex: String
        }
    }
    private func fixtures() throws -> [Fixtures.Fixture] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/WhoopHistoryFixtures.json")
        return try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url)).fixtures
    }
    private func record(_ fixture: Fixtures.Fixture) throws -> WhoopHistoryRecord {
        var decoder = WhoopFrameDecoder(generation: fixture.generation)
        let frame = try XCTUnwrap(decoder.append(Data(historyHex: fixture.frameHex)).first, fixture.name)
        return try XCTUnwrap(WhoopHistoryRecord(frame: frame), fixture.name)
    }

    func testIndependentFramesPreserveRawAndDecodeOnlyKnownHeader() throws {
        for fixture in try fixtures().filter({ !$0.name.hasPrefix("short") }) {
            let value = try record(fixture)
            XCTAssertEqual(value.rawFrame, Data(historyHex: fixture.frameHex))
            XCTAssertEqual(value.rawPayload, Data(historyHex: fixture.payloadHex))
            XCTAssertEqual(value.rawRevision, fixture.revision)
            XCTAssertEqual(value.generation, fixture.generation)
            XCTAssertNil(value.heartRate)
            if fixture.revision == 99 {
                XCTAssertFalse(value.hasCommonHeader)
                XCTAssertNil(value.packetCounter)
                XCTAssertNil(value.deviceTime)
                XCTAssertNil(value.metricsFlag)
            } else {
                XCTAssertTrue(value.isSelectedMetricsRevision)
                XCTAssertTrue(value.hasCommonHeader)
                XCTAssertEqual(value.packetCounter, 0x8765_4321)
                XCTAssertEqual(value.timestampComponent32, 1_700_000_000)
                XCTAssertEqual(value.timestampComponent16, 16384)
                XCTAssertEqual(value.deviceTime?.unixMilliseconds, 1_700_000_000_500)
                XCTAssertEqual(value.metricsFlag, fixture.revision == 18 ? 127 : 2)
            }
        }
    }

    func testTruncatedCommonHeaderAndRevisionFlagRemainOpaqueAndLossless() throws {
        for fixture in try fixtures().filter({ $0.name.hasPrefix("short") }) {
            let value = try record(fixture)
            let count = Data(historyHex: fixture.payloadHex).count
            XCTAssertEqual(value.rawPayload.count, count)
            XCTAssertEqual(value.hasCommonHeader, count >= 13)
            XCTAssertEqual(value.packetCounter, count >= 13 ? 0 : nil)
            let flagPresent = fixture.revision == 18 ? count >= 15 : count >= 18
            XCTAssertEqual(value.metricsFlag, flagPresent ? 0 : nil)
            XCTAssertNil(value.heartRate)
        }
    }

    func testRealtimeFrameIsNotHistorical() throws {
        var decoder = WhoopFrameDecoder(generation: .gen4)
        let frame = try XCTUnwrap(decoder.append(Data(historyHex: "aa0800a828020000a38c4647")).first)
        XCTAssertNil(WhoopHistoryRecord(frame: frame))
    }

    func testNoncanonicalTimeIsRetainedAndNotConverted() throws {
        let fixture = try XCTUnwrap(fixtures().first)
        var bytes = [UInt8](Data(historyHex: fixture.frameHex))
        // History fraction is at payload +11, whereas realtime's fraction is +6.
        bytes[4 + 11] = 0xff; bytes[4 + 12] = 0xff
        let crc = WhoopCRC.crc32(bytes[4..<(bytes.count - 4)])
        for i in 0..<4 { bytes[bytes.count - 4 + i] = UInt8(truncatingIfNeeded: crc >> (i * 8)) }
        var decoder = WhoopFrameDecoder(generation: .gen4)
        let frame = try XCTUnwrap(decoder.append(Data(bytes)).first)
        let value = try XCTUnwrap(WhoopHistoryRecord(frame: frame))
        XCTAssertEqual(value.timestampComponent16, 65535)
        XCTAssertNil(value.deviceTime)
        XCTAssertEqual(value.rawFrame, Data(bytes))
    }
}

private extension Data {
    init(historyHex: String) {
        let bytes = Array(historyHex)
        self.init(stride(from: 0, to: bytes.count, by: 2).map {
            UInt8(String(bytes[$0...($0 + 1)]), radix: 16)!
        })
    }
}
