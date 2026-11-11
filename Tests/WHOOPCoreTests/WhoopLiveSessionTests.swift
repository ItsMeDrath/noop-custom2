import Foundation
import XCTest
@testable import WHOOPCore

final class WhoopLiveSessionTests: XCTestCase {
    func testHelloSuccessMustMatchBeforeStreamAndNoDuplicateWrites() throws {
        for generation in WhoopGeneration.allCases {
            var session = WhoopLiveSession(generation: generation)
            let hello = try decoded(session.begin(), generation)
            XCTAssertEqual(hello.payload[1], 0)
            XCTAssertEqual(session.state, .waitingForHello)
            XCTAssertThrowsError(try session.begin())
            let opcode: UInt8 = generation == .gen4 ? 0x23 : 0x91
            XCTAssertNil(try session.receive(reply(opcode, 99, .success, generation)))
            XCTAssertNil(try session.receive(reply(0x03, 0, .success, generation)))
            XCTAssertNil(try session.receive(reply(opcode, 0, .pending, generation)))
            XCTAssertEqual(session.state, .waitingForHello)
            let ack = try reply(opcode, 0, .success, generation)
            let enable = try XCTUnwrap(session.receive(ack))
            XCTAssertEqual(try decoded(enable, generation).payload, Data([0x23, 1, 3, 1]))
            XCTAssertEqual(session.state, .waitingForStream)
            XCTAssertNil(try session.receive(ack))
            XCTAssertNil(try session.receive(reply(3, 1, .pending, generation)))
            XCTAssertEqual(session.state, .waitingForStream)
            XCTAssertNil(try session.receive(reply(3, 1, .success, generation)))
            XCTAssertEqual(session.state, .streaming)
            XCTAssertNil(try session.receive(reply(3, 1, .success, generation)))
            session.expire(); session.transportFailed()
            XCTAssertEqual(session.state, .streaming)
            XCTAssertFalse(session.canBegin)
        }
    }
    func testFailuresAbortAndRetryDoesNotReuseStaleSequence() throws {
        for result in [WhoopCommandResult.failure, .unsupported] {
            var session = WhoopLiveSession(generation: .gen4)
            _ = try session.begin()
            _ = try session.receive(reply(0x23, 0, result, .gen4))
            XCTAssertEqual(session.state, .failed(result == .failure ? .rejected : .unsupported))
            XCTAssertTrue(session.canBegin)
            let retry = try decoded(session.begin(), .gen4)
            XCTAssertEqual(retry.payload[1], 1)
            XCTAssertNil(try session.receive(reply(0x23, 0, .success, .gen4)))
            XCTAssertEqual(session.state, .waitingForHello)
        }
    }
    func testTimeoutTransportAndBoundedSequenceWrap() throws {
        var session = WhoopLiveSession(generation: .gen4)
        session.expire(); XCTAssertEqual(session.state, .idle)
        for index in 0..<260 {
            let request = try decoded(session.begin(), .gen4)
            XCTAssertEqual(request.payload[1], UInt8(index % 256))
            if index.isMultiple(of: 2) { session.expire(); XCTAssertEqual(session.state, .failed(.timedOut)) }
            else { session.transportFailed(); XCTAssertEqual(session.state, .failed(.transport)) }
        }
    }
    func testOtherFrameKindsAndGenerationCannotAdvance() throws {
        var session = WhoopLiveSession(generation: .gen4)
        let request = try session.begin()
        XCTAssertNil(try session.receive(decoded(request, .gen4)))
        XCTAssertNil(try session.receive(reply(0x23, 0, .success, .maverick)))
        XCTAssertEqual(session.state, .waitingForHello)
    }
    private func decoded(_ data: Data, _ generation: WhoopGeneration) throws -> WhoopFrame {
        var decoder = WhoopFrameDecoder(generation: generation)
        return try XCTUnwrap(decoder.append(data).first)
    }
    private func reply(_ opcode: UInt8, _ sequence: UInt8, _ result: WhoopCommandResult, _ generation: WhoopGeneration) throws -> WhoopFrame {
        // Reply framing is synthetic; CRC correctness has independent golden tests.
        let payload: [UInt8] = [0x24, 0xaa, opcode, sequence, result.rawValue, 0, 0, 0]
        var bytes: [UInt8]
        if generation == .gen4 {
            bytes = [0xaa, 12, 0]; bytes.append(WhoopCRC.crc8(bytes[1..<3]))
        } else {
            bytes = [0xaa, 1, 12, 0, 0, 1]
            let crc = WhoopCRC.crc16(bytes)
            bytes += [UInt8(truncatingIfNeeded: crc), UInt8(truncatingIfNeeded: crc >> 8)]
        }
        bytes += payload
        let crc = WhoopCRC.crc32(payload)
        bytes += (0..<4).map { UInt8(truncatingIfNeeded: crc >> ($0 * 8)) }
        return try decoded(Data(bytes), generation)
    }
}
