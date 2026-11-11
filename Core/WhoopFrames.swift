import Foundation

/// Select from device identity; MAVERICK and GOOSE cannot be distinguished by UUID.
public enum WhoopGeneration: String, Codable, CaseIterable, Sendable {
    case gen4
    case maverick
    case goose

    fileprivate var headerSize: Int { self == .gen4 ? 4 : 8 }
    fileprivate var lengthOffset: Int { self == .gen4 ? 1 : 2 }
}

public enum WhoopPacketType: UInt8, Sendable {
    case command = 0x23, commandResponse = 0x24
    case puffinCommand = 0x25, puffinCommandResponse = 0x26
    case realtimeData = 0x28, realtimeRawData = 0x2b, historicalData = 0x2f
    case event = 0x30, metadata = 0x31, consoleLogs = 0x32
    case realtimeIMUDataStream = 0x33, historicalIMUDataStream = 0x34
    case relativePuffinEvents = 0x35, puffinEventsFromStrap = 0x36
    case relativeBatteryPackConsoleLogs = 0x37, puffinMetadata = 0x38
}

/// Selected fields recovered from hf0.j. Timestamp units and epoch are unknown.
public struct WhoopRealtimeData: Equatable, Sendable {
    public let revision: UInt8
    public let timestampComponent32: UInt32
    public let timestampComponent16: UInt16
    public let heartRate: UInt8
    public let isOffWrist: Bool?
    public let bodyLocationCode: UInt8?

    fileprivate init?(payload: Data) {
        let bytes = [UInt8](payload)
        guard bytes.count >= 9, bytes[0] == WhoopPacketType.realtimeData.rawValue else { return nil }
        revision = bytes[1]
        timestampComponent32 = littleEndian32(bytes, at: 2)
        timestampComponent16 = littleEndian16(bytes, at: 6)
        heartRate = bytes[8]
        // The Android constructor reads these unconditionally, but only its revision-2
        // description assigns their meanings. Keep other revisions uninterpreted.
        isOffWrist = revision == 2 && bytes.count >= 20 ? bytes[18] == 0 : nil
        bodyLocationCode = revision == 2 && bytes.count >= 20 ? bytes[19] : nil
    }
}

/// Created only after the complete frame passes length, alignment and CRC checks.
public struct WhoopFrame: Equatable, Sendable {
    public let generation: WhoopGeneration
    public let bytes: Data
    public let payload: Data
    public var packetTypeCode: UInt8 { payload[payload.startIndex] }
    public var packetType: WhoopPacketType? { WhoopPacketType(rawValue: packetTypeCode) }
    public var realtimeData: WhoopRealtimeData? { WhoopRealtimeData(payload: payload) }
    public var realtimeHeartRate: Double? {
        guard let value = realtimeData, value.heartRate > 0, value.isOffWrist != true else { return nil }
        return Double(value.heartRate)
    }

    fileprivate init(generation: WhoopGeneration, bytes: ArraySlice<UInt8>) {
        self.generation = generation
        self.bytes = Data(bytes)
        payload = Data(bytes.dropFirst(generation.headerSize).dropLast(4))
    }
}

/// CRC definitions recovered statically; these detect corruption, not authentication.
public enum WhoopCRC {
    public static func crc8<C: Collection>(_ bytes: C) -> UInt8 where C.Element == UInt8 {
        var crc: UInt8 = 0
        for byte in bytes {
            crc ^= byte
            for _ in 0..<8 { crc = crc & 0x80 == 0 ? crc &<< 1 : (crc &<< 1) ^ 0x07 }
        }
        return crc
    }

    public static func crc16<C: Collection>(_ bytes: C) -> UInt16 where C.Element == UInt8 {
        var crc: UInt16 = 0xffff
        for byte in bytes {
            crc ^= UInt16(byte)
            for _ in 0..<8 { crc = crc & 1 == 0 ? crc >> 1 : (crc >> 1) ^ 0xa001 }
        }
        return crc
    }

    public static func crc32<C: Collection>(_ bytes: C) -> UInt32 where C.Element == UInt8 {
        var crc: UInt32 = 0xffff_ffff
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 0 ? crc >> 1 : (crc >> 1) ^ 0xedb8_8320 }
        }
        return crc ^ 0xffff_ffff
    }
}

/// Passive stream decoder. Use a separate instance per device/characteristic stream.
/// Arbitrary notification boundaries are accepted. Retained input is bounded by the
/// 16-bit length field plus the largest supported header, rounded up to four bytes.
public struct WhoopFrameDecoder: Sendable {
    public static let maximumBufferedBytes = 65_544
    public let generation: WhoopGeneration
    public private(set) var discardedByteCount = 0
    public private(set) var malformedFrameCount = 0
    public var bufferedByteCount: Int { buffer.count }
    private var buffer: [UInt8] = []

    public init(generation: WhoopGeneration) { self.generation = generation }

    public mutating func append(_ data: Data) -> [WhoopFrame] {
        var frames: [WhoopFrame] = []
        var index = data.startIndex
        while index < data.endIndex {
            let count = min(Self.maximumBufferedBytes - buffer.count, data.distance(from: index, to: data.endIndex))
            let end = data.index(index, offsetBy: count)
            buffer.append(contentsOf: data[index..<end])
            index = end
            decodeAvailable(into: &frames)
        }
        return frames
    }

    private mutating func decodeAvailable(into frames: inout [WhoopFrame]) {
        var cursor = 0
        let headerSize = generation.headerSize
        while cursor < buffer.count {
            guard let start = buffer[cursor...].firstIndex(of: 0xaa) else {
                discardedByteCount += buffer.count - cursor
                cursor = buffer.count
                break
            }
            discardedByteCount += start - cursor
            cursor = start
            guard buffer.count - cursor >= headerSize else { break }
            let length = Int(littleEndian16(buffer, at: cursor + generation.lengthOffset))
            let totalSize = headerSize + length
            let validHeader: Bool
            if generation == .gen4 {
                validHeader = WhoopCRC.crc8(buffer[(cursor + 1)..<(cursor + 3)]) == buffer[cursor + 3]
            } else {
                validHeader = WhoopCRC.crc16(buffer[cursor..<(cursor + 6)]) == littleEndian16(buffer, at: cursor + 6)
            }
            // At least one payload byte is required for packet dispatch. Include the
            // trailer in the encoded length; alignment applies to the full frame.
            guard validHeader, length > 4, totalSize % 4 == 0,
                  totalSize <= Self.maximumBufferedBytes else {
                malformedFrameCount += 1
                discardedByteCount += 1
                cursor += 1
                continue
            }
            guard buffer.count - cursor >= totalSize else { break }
            let end = cursor + totalSize
            let payload = buffer[(cursor + headerSize)..<(end - 4)]
            guard WhoopCRC.crc32(payload) == littleEndian32(buffer, at: end - 4) else {
                // Advance one byte to find a good frame following a damaged length
                // or nested inside a corrupt candidate; never emit failed payloads.
                malformedFrameCount += 1
                discardedByteCount += 1
                cursor += 1
                continue
            }
            frames.append(WhoopFrame(generation: generation, bytes: buffer[cursor..<end]))
            cursor = end
        }
        if cursor > 0 { buffer.removeFirst(cursor) }
    }
}

private func littleEndian16(_ bytes: [UInt8], at index: Int) -> UInt16 {
    UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8
}

private func littleEndian32(_ bytes: [UInt8], at index: Int) -> UInt32 {
    UInt32(bytes[index]) | UInt32(bytes[index + 1]) << 8 |
    UInt32(bytes[index + 2]) << 16 | UInt32(bytes[index + 3]) << 24
}
