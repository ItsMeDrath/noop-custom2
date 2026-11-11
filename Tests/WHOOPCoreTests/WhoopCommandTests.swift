import Foundation
import XCTest
@testable import WHOOPCore

final class WhoopCommandTests: XCTestCase {
    // Synthetic full-frame fixtures calculated outside Swift with Python and
    // zlib.crc32. These are static encoding checks, not captured device packets.
    func testHelloGoldenFramesAndDecode() throws {
        let vectors: [(WhoopGeneration, String, [UInt8])] = [
            (.gen4, "aa0800a8230123009ac2a82c", [0x23, 1, 0x23, 0]),
            (.maverick, "aa0108000001e67123019101363e5c8d", [0x23, 1, 0x91, 1]),
            (.goose, "aa0108000001e67123019101363e5c8d", [0x23, 1, 0x91, 1])
        ]
        for (generation, hex, payload) in vectors {
            let encoded = try WhoopCommands.frame(.hello, generation: generation, sequence: 1)
            XCTAssertEqual(encoded, bytes(hex))
            var decoder = WhoopFrameDecoder(generation: generation)
            let decoded = try XCTUnwrap(decoder.append(encoded).first)
            XCTAssertEqual(decoded.payload, Data(payload))
            XCTAssertEqual(decoded.packetType, .command)
            XCTAssertNil(WhoopCommandResponse(frame: decoded))
        }
    }

    func testEnableDisableGoldenFramesAndExplicitSequences() throws {
        for generation in WhoopGeneration.allCases {
            let prefix = generation == .gen4 ? "aa0800a8" : "aa0108000001e671"
            let enabled = try WhoopCommands.frame(.realtimeHeartRate(true), generation: generation, sequence: 2)
            let disabled = try WhoopCommands.frame(.realtimeHeartRate(false), generation: generation, sequence: 255)
            XCTAssertEqual(enabled, bytes(prefix + "23020301f7686dcc"))
            XCTAssertEqual(disabled, bytes(prefix + "23ff0300e2b87606"))
            var decoder = WhoopFrameDecoder(generation: generation)
            XCTAssertEqual(decoder.append(enabled + disabled).map(\.payload), [Data([0x23, 2, 3, 1]), Data([0x23, 255, 3, 0])])
            let zero = try WhoopCommands.frame(.hello, generation: generation, sequence: 0)
            XCTAssertEqual(decoder.append(zero).first?.payload[1], 0)
        }
    }

    func testResponseUsesOriginatingSequenceAndKnownResults() throws {
        let vectors: [(String, UInt8, UInt8, WhoopCommandResult)] = [
            ("aa0c00fc24aa910101000000d6b423a8", 0x91, 1, .success),
            ("aa0c00fc24aa030202000000a0d698ad", 3, 2, .pending),
            ("aa0c00fc24aa0302000000002b1e9107", 3, 2, .failure),
            ("aa0c00fc24aa030203000000c5b12415", 3, 2, .unsupported)
        ]
        for (hex, opcode, sequence, result) in vectors {
            var decoder = WhoopFrameDecoder(generation: .gen4)
            let frame = try XCTUnwrap(decoder.append(bytes(hex)).first)
            let response = try XCTUnwrap(WhoopCommandResponse(frame: frame))
            XCTAssertEqual(response.opcode, opcode)
            XCTAssertEqual(response.sequence, sequence) // Response packet sequence is 0xaa.
            XCTAssertEqual(response.result, result)
        }
        XCTAssertEqual(WhoopCommandResult(rawValue: 0), .failure)
        XCTAssertEqual(WhoopCommandResult(rawValue: 3), .unsupported)
    }

    func testTruncatedAndUnknownResultResponsesAreRejected() throws {
        for hex in ["aa0800a824aa91010eb4a6c5", "aa0c00fc24aa9101ff00000042d59ace"] {
            var decoder = WhoopFrameDecoder(generation: .gen4)
            let frame = try XCTUnwrap(decoder.append(bytes(hex)).first)
            XCTAssertNil(WhoopCommandResponse(frame: frame))
        }
    }

    private func bytes(_ hex: String) -> Data {
        let characters = Array(hex)
        return Data(stride(from: 0, to: characters.count, by: 2).map {
            UInt8(String(characters[$0...($0 + 1)]), radix: 16)!
        })
    }
}
