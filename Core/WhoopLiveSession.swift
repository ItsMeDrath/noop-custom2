import Foundation

public enum WhoopLiveFailure: Equatable, Sendable {
    case rejected, unsupported, timedOut, transport
}

public enum WhoopLiveState: Equatable, Sendable {
    case idle, waitingForHello, waitingForStream, streaming
    case failed(WhoopLiveFailure)
}

public enum WhoopLiveSessionError: Error { case alreadyActive }

/// Local experimental request policy, not the complete Android initialization state machine.
/// Only a matching successful Hello acknowledgement permits the stream-enable request.
public struct WhoopLiveSession: Sendable {
    public let generation: WhoopGeneration
    public private(set) var state: WhoopLiveState = .idle
    private var nextSequence: UInt8 = 0
    private var expectedSequence: UInt8 = 0
    private var expectedOpcode: UInt8 = 0

    public init(generation: WhoopGeneration) { self.generation = generation }
    public var isWaiting: Bool { state == .waitingForHello || state == .waitingForStream }
    public var canBegin: Bool {
        if case .failed = state { return true }
        return state == .idle
    }

    public mutating func begin() throws -> Data {
        guard canBegin else { throw WhoopLiveSessionError.alreadyActive }
        let sequence = allocateSequence()
        let bytes = try WhoopCommands.frame(.hello, generation: generation, sequence: sequence)
        expectedSequence = sequence
        expectedOpcode = generation == .gen4 ? 0x23 : 0x91
        state = .waitingForHello
        return bytes
    }

    /// Returns the next request only once. Pending, unrelated, stale and duplicate
    /// replies never advance the session. Raw Hello metadata is intentionally not validated.
    public mutating func receive(_ frame: WhoopFrame) throws -> Data? {
        guard isWaiting, frame.generation == generation,
              let response = WhoopCommandResponse(frame: frame),
              response.sequence == expectedSequence, response.opcode == expectedOpcode else { return nil }
        switch response.result {
        case .pending: return nil
        case .failure: state = .failed(.rejected); return nil
        case .unsupported: state = .failed(.unsupported); return nil
        case .success:
            if state == .waitingForHello {
                let sequence = allocateSequence()
                let bytes = try WhoopCommands.frame(.realtimeHeartRate(true), generation: generation, sequence: sequence)
                expectedSequence = sequence; expectedOpcode = 0x03
                state = .waitingForStream
                return bytes
            }
            state = .streaming
            return nil
        }
    }
    public mutating func expire() { if isWaiting { state = .failed(.timedOut) } }
    public mutating func transportFailed() { if isWaiting { state = .failed(.transport) } }

    private mutating func allocateSequence() -> UInt8 {
        let value = nextSequence
        nextSequence &+= 1
        return value
    }
}
