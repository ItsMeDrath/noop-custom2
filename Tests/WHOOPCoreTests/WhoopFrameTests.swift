import Foundation
import XCTest
@testable import WHOOPCore

final class WhoopFrameTests: XCTestCase {
    // Synthetic fixtures generated with the extracted DEX CRC8/CRC16 lookup
    // tables and Python zlib.crc32, independently of Swift's bitwise CRC code.
    private let gen4 = Data(hex: "aa1800ff280278563412efcd48aa0000000000000000010765caa2a7")
    private let maverick = Data(hex: "aa7e18008142d6da280278563412efcd48aa0000000000000000010765caa2a7")
    private let payload = Data(hex: "280278563412efcd48aa00000000000000000107")
    private var fixtures: [(WhoopGeneration, Data)] { [(.gen4, gen4), (.maverick, maverick), (.goose, maverick)] }

    func testIndependentCRCCheckValues() {
        let check = Array("123456789".utf8)
        XCTAssertEqual(WhoopCRC.crc8(check), 0xf4)
        XCTAssertEqual(WhoopCRC.crc16(check), 0x4b37)
        XCTAssertEqual(WhoopCRC.crc32(check), 0xcbf4_3926)
        XCTAssertEqual(WhoopCRC.crc8([UInt8]()), 0)
        XCTAssertEqual(WhoopCRC.crc16([UInt8]()), 0xffff)
        XCTAssertEqual(WhoopCRC.crc32([UInt8]()), 0)
        XCTAssertEqual(WhoopCRC.crc8([UInt8(24), 0]), 0xff)
        XCTAssertEqual(WhoopCRC.crc16([UInt8](maverick.prefix(6))), 0xdad6)
        XCTAssertEqual(WhoopCRC.crc32(payload), 0xa7a2_ca65)
    }

    func testIndependentFixturesAndRecoveredFields() throws {
        for (generation, bytes) in fixtures {
            var decoder = WhoopFrameDecoder(generation: generation)
            let frames = decoder.append(bytes)
            XCTAssertEqual(frames.count, 1)
            let frame = try XCTUnwrap(frames.first)
            XCTAssertEqual(frame.generation, generation)
            XCTAssertEqual(frame.bytes, bytes)
            XCTAssertEqual(frame.payload, payload)
            XCTAssertEqual(frame.packetType, .realtimeData)
            XCTAssertEqual(frame.realtimeHeartRate, 72)
            let realtime = try XCTUnwrap(frame.realtimeData)
            XCTAssertEqual(realtime.revision, 2)
            XCTAssertEqual(realtime.timestampComponent32, 0x1234_5678)
            XCTAssertEqual(realtime.timestampComponent16, 0xcdef)
            XCTAssertEqual(realtime.heartRate, 72)
            XCTAssertEqual(realtime.isOffWrist, false)
            XCTAssertEqual(realtime.bodyLocationCode, 7)
            XCTAssertEqual(decoder.bufferedByteCount, 0)
            XCTAssertEqual(decoder.discardedByteCount, 0)
        }
    }

    func testEveryTwoFragmentBoundary() {
        for (generation, bytes) in fixtures {
            for split in 1..<bytes.count {
                var decoder = WhoopFrameDecoder(generation: generation)
                XCTAssertTrue(decoder.append(bytes.prefix(split)).isEmpty)
                XCTAssertEqual(decoder.append(bytes.dropFirst(split)).map(\.payload), [payload])
            }
        }
    }

    func testOneByteFragmentsAndConcatenatedFrames() {
        for (generation, bytes) in fixtures {
            var decoder = WhoopFrameDecoder(generation: generation)
            var frames: [WhoopFrame] = []
            for byte in bytes + bytes { frames += decoder.append(Data([byte])) }
            XCTAssertEqual(frames.map(\.payload), [payload, payload])
            XCTAssertEqual(decoder.append(bytes + bytes + bytes).count, 3)
        }
    }

    func testNoiseHeaderCRCAndPayloadCRCResynchronize() {
        for (generation, bytes) in fixtures {
            var badHeader = bytes
            badHeader[generation == .gen4 ? 3 : 6] ^= 0x40
            var badPayload = bytes
            badPayload[generation == .gen4 ? 8 : 12] ^= 0x01
            var decoder = WhoopFrameDecoder(generation: generation)
            let noise = Data([0, 0x55, 0xaa, 0, 0x55])
            let frames = decoder.append(noise + badHeader + badPayload + bytes)
            XCTAssertEqual(frames.map(\.payload), [payload])
            XCTAssertEqual(decoder.discardedByteCount, noise.count + badHeader.count + badPayload.count)
            XCTAssertGreaterThanOrEqual(decoder.malformedFrameCount, 2)
        }
    }

    func testCRCValidUnalignedAndEmptyLengthRejected() {
        for (generation, bytes) in fixtures {
            for length: UInt16 in [0, 4, 5, 65535] {
                var bad = [UInt8](bytes.prefix(generation == .gen4 ? 4 : 8))
                let offset = generation == .gen4 ? 1 : 2
                bad[offset] = UInt8(truncatingIfNeeded: length)
                bad[offset + 1] = UInt8(truncatingIfNeeded: length >> 8)
                updateHeader(&bad, generation: generation)
                var decoder = WhoopFrameDecoder(generation: generation)
                XCTAssertEqual(decoder.append(Data(bad) + bytes).map(\.payload), [payload])
                XCTAssertGreaterThan(decoder.malformedFrameCount, 0)
            }
        }
    }

    func testCRCDoesNotIncludeHeaderButHeaderHasIndependentIntegrity() {
        var changed = [UInt8](maverick)
        changed[1] ^= 0x10
        changed[4] ^= 0x40
        updateHeader(&changed, generation: .maverick)
        var decoder = WhoopFrameDecoder(generation: .maverick)
        XCTAssertEqual(decoder.append(Data(changed)).first?.payload, payload)
    }

    func testPartialFrameRetainedAndLaterCompletion() {
        var decoder = WhoopFrameDecoder(generation: .gen4)
        XCTAssertTrue(decoder.append(gen4.prefix(gen4.count - 1)).isEmpty)
        XCTAssertEqual(decoder.bufferedByteCount, gen4.count - 1)
        XCTAssertTrue(decoder.append(Data()).isEmpty)
        XCTAssertEqual(decoder.append(gen4.suffix(1)).count, 1)
    }

    func testUnknownPacketTypePreservedWithoutRealtimeInterpretation() throws {
        let bytes = Data(hex: "aa0800a8990102033d28f14b")
        var decoder = WhoopFrameDecoder(generation: .gen4)
        let frame = try XCTUnwrap(decoder.append(bytes).first)
        XCTAssertEqual(frame.packetTypeCode, 0x99)
        XCTAssertNil(frame.packetType)
        XCTAssertNil(frame.realtimeData)
        XCTAssertNil(frame.realtimeHeartRate)
    }

    func testShortRealtimeAndEarlierRevisionRemainGuarded() throws {
        var decoder = WhoopFrameDecoder(generation: .gen4)
        let short = try XCTUnwrap(decoder.append(Data(hex: "aa0800a828020000a38c4647")).first)
        XCTAssertNil(short.realtimeData)
        let earlier = try XCTUnwrap(decoder.append(Data(hex: "aa100057280178563412efcd5b000000c794ed5b")).first)
        XCTAssertEqual(earlier.realtimeData?.revision, 1)
        XCTAssertEqual(earlier.realtimeHeartRate, 91)
        XCTAssertNil(earlier.realtimeData?.isOffWrist)
        XCTAssertNil(earlier.realtimeData?.bodyLocationCode)
        var shortRevision2 = [UInt8](earlier.bytes)
        shortRevision2[5] = 2
        updateTrailer(&shortRevision2, headerSize: 4)
        let revision2 = try XCTUnwrap(decoder.append(Data(shortRevision2)).first)
        XCTAssertEqual(revision2.realtimeHeartRate, 91)
        XCTAssertNil(revision2.realtimeData?.isOffWrist)
        XCTAssertNil(revision2.realtimeData?.bodyLocationCode)
    }

    func testOffWristAndZeroAreKeptRawAndExcludedFromLiveHeartRate() throws {
        for offset in [4 + 18, 4 + 8] {
            var bytes = [UInt8](gen4)
            bytes[offset] = 0
            updateTrailer(&bytes, headerSize: 4)
            var decoder = WhoopFrameDecoder(generation: .gen4)
            let frame = try XCTUnwrap(decoder.append(Data(bytes)).first)
            XCTAssertNotNil(frame.realtimeData)
            XCTAssertNil(frame.realtimeHeartRate)
            if offset == 22 { XCTAssertEqual(frame.realtimeData?.isOffWrist, true) }
            else { XCTAssertEqual(frame.realtimeData?.heartRate, 0) }
        }
    }

    func testNotificationDataWithNonzeroStartIndex() {
        let backing = Data([1, 2, 3]) + gen4
        let slice = backing.dropFirst(3)
        XCTAssertEqual(slice.startIndex, 3)
        var decoder = WhoopFrameDecoder(generation: .gen4)
        XCTAssertEqual(decoder.append(slice).map(\.payload), [payload])
    }

    func testBoundedLargeNoiseAndManyFrames() {
        var decoder = WhoopFrameDecoder(generation: .gen4)
        let noise = Data(repeating: 0xaa, count: WhoopFrameDecoder.maximumBufferedBytes * 4)
        XCTAssertEqual(decoder.append(noise + gen4).map(\.payload), [payload])
        XCTAssertEqual(decoder.discardedByteCount, noise.count)
        XCTAssertLessThanOrEqual(decoder.bufferedByteCount, WhoopFrameDecoder.maximumBufferedBytes)
        let many = Data(Array(repeating: [UInt8](gen4), count: 3000).flatMap { $0 })
        XCTAssertEqual(decoder.append(many).count, 3000)
        XCTAssertEqual(decoder.bufferedByteCount, 0)
    }

    func testMaximumLengthCandidateCompletesThenRecovers() {
        // Largest four-byte-aligned GEN_4 frame allowed by its 16-bit length.
        var maximum = [UInt8](repeating: 0, count: 65536)
        maximum[0] = 0xaa; maximum[1] = 0xfc; maximum[2] = 0xff
        updateHeader(&maximum, generation: .gen4)
        var decoder = WhoopFrameDecoder(generation: .gen4)
        XCTAssertTrue(decoder.append(Data(maximum.prefix(65535))).isEmpty)
        XCTAssertEqual(decoder.bufferedByteCount, 65535)
        XCTAssertEqual(decoder.append(Data(maximum.suffix(1)) + gen4).map(\.payload), [payload])
        XCTAssertEqual(decoder.bufferedByteCount, 0)
    }

    func testEmbeddedSOFDoesNotSplitAnIncompleteGoodFrame() {
        var decoder = WhoopFrameDecoder(generation: .gen4)
        // The fixture intentionally contains 0xaa inside its payload.
        XCTAssertTrue(decoder.append(gen4.prefix(15)).isEmpty)
        XCTAssertEqual(decoder.append(gen4.dropFirst(15)).count, 1)
    }

    private func updateHeader(_ bytes: inout [UInt8], generation: WhoopGeneration) {
        if generation == .gen4 { bytes[3] = WhoopCRC.crc8(bytes[1..<3]) }
        else {
            let crc = WhoopCRC.crc16(bytes[0..<6])
            bytes[6] = UInt8(truncatingIfNeeded: crc)
            bytes[7] = UInt8(truncatingIfNeeded: crc >> 8)
        }
    }

    private func updateTrailer(_ bytes: inout [UInt8], headerSize: Int) {
        let crc = WhoopCRC.crc32(bytes[headerSize..<(bytes.count - 4)])
        for offset in 0..<4 { bytes[bytes.count - 4 + offset] = UInt8(truncatingIfNeeded: crc >> (offset * 8)) }
    }
}

private extension Data {
    init(hex: String) {
        let characters = Array(hex)
        self.init(stride(from: 0, to: characters.count, by: 2).map {
            UInt8(String(characters[$0...($0 + 1)]), radix: 16)!
        })
    }
}
