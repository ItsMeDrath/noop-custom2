import Foundation

/// Passive, lossless view of an integrity-checked historical packet (type 0x2f).
/// Only the common header and revision-specific metrics flag are mapped here.
/// The physiological body remains opaque until its schema is independently recovered.
public struct WhoopHistoryRecord: Equatable, Sendable {
    public let generation: WhoopGeneration
    public let rawFrame: Data
    public let rawPayload: Data
    public let rawRevision: UInt8
    public let packetCounter: UInt32?
    public let timestampComponent32: UInt32?
    public let timestampComponent16: UInt16?
    public let metricsFlag: UInt8?

    /// No historical heart-rate offset has been established by the inspected decoder.
    public var heartRate: UInt8? { nil }
    public var deviceTime: WhoopDeviceTime? {
        guard let seconds = timestampComponent32, let ticks = timestampComponent16 else { return nil }
        return WhoopDeviceTime(seconds: seconds, ticks: ticks)
    }
    public var hasCommonHeader: Bool { timestampComponent32 != nil }
    public var isSelectedMetricsRevision: Bool { [9, 12, 18, 24].contains(rawRevision) }

    public init?(frame: WhoopFrame) {
        guard frame.packetType == .historicalData else { return nil }
        let bytes = [UInt8](frame.payload)
        guard bytes.count >= 2 else { return nil }
        generation = frame.generation
        rawFrame = frame.bytes
        rawPayload = frame.payload
        rawRevision = bytes[1]
        // im0.b.Q checks the entire 13-byte common header before timestamp reads.
        // Unknown revisions are retained without projecting a known revision's layout.
        if [9, 12, 18, 24].contains(rawRevision), bytes.count >= 13 {
            packetCounter = Self.read32(bytes, 3)
            timestampComponent32 = Self.read32(bytes, 7)
            timestampComponent16 = UInt16(bytes[11]) | UInt16(bytes[12]) << 8
        } else {
            packetCounter = nil; timestampComponent32 = nil; timestampComponent16 = nil
        }
        let flagOffset: Int?
        switch rawRevision {
        case 9, 12, 24: flagOffset = 17
        case 18: flagOffset = 14
        default: flagOffset = nil
        }
        if timestampComponent32 != nil, let offset = flagOffset, bytes.count > offset {
            metricsFlag = bytes[offset]
        } else { metricsFlag = nil }
    }

    private static func read32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 |
            UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }
}
