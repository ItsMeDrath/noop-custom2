import Foundation

/// Only the recovered Hello and reversible realtime-HR subscription requests.
public enum WhoopCommand: Equatable, Sendable {
    case hello
    case realtimeHeartRate(Bool)
}

public enum WhoopCommands {
    /// Builds the verified, four-byte command payload and its generation-specific
    /// frame. The caller owns sequence assignment and response matching.
    /// This is an experimental request encoder, not Android initialization parity.
    public static func frame(_ command: WhoopCommand, generation: WhoopGeneration, sequence: UInt8) throws -> Data {
        let payload: [UInt8]
        switch command {
        case .hello:
            payload = generation == .gen4 ? [0x23, sequence, 0x23, 0] : [0x23, sequence, 0x91, 1]
        case .realtimeHeartRate(let enabled):
            payload = [0x23, sequence, 0x03, enabled ? 1 : 0]
        }
        // Every supported request is already aligned. No general padding path is
        // inferred from the source builder's suspicious unaligned self-copy branch.
        var bytes: [UInt8]
        if generation == .gen4 {
            bytes = [0xaa, 8, 0]
            bytes.append(WhoopCRC.crc8(bytes[1..<3]))
        } else {
            bytes = [0xaa, 1, 8, 0, 0, 1]
            let crc = WhoopCRC.crc16(bytes)
            bytes += [UInt8(truncatingIfNeeded: crc), UInt8(truncatingIfNeeded: crc >> 8)]
        }
        bytes += payload
        let crc = WhoopCRC.crc32(payload)
        bytes += (0..<4).map { UInt8(truncatingIfNeeded: crc >> ($0 * 8)) }
        return Data(bytes)
    }
}

public enum WhoopCommandResult: UInt8, Sendable {
    case failure = 0
    case success = 1
    case pending = 2
    case unsupported = 3
}

/// A validated frame's reply envelope; this does not validate a Hello metadata body.
public struct WhoopCommandResponse: Equatable, Sendable {
    public let opcode: UInt8
    /// Originating command sequence, not the response packet's own sequence.
    public let sequence: UInt8
    public let result: WhoopCommandResult

    public init?(frame: WhoopFrame) {
        let payload = [UInt8](frame.payload)
        guard payload.count >= 5, payload[0] == WhoopPacketType.commandResponse.rawValue,
              let result = WhoopCommandResult(rawValue: payload[4]) else { return nil }
        opcode = payload[2]
        sequence = payload[3]
        self.result = result
    }
}
