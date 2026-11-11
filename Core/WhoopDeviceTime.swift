import Foundation

/// A canonical timestamp recovered from the Android `z32.a` implementation.
/// Seconds use the Unix epoch; subseconds count 1/32768-second ticks.
/// This value establishes conversion semantics, not whether a device clock is set.
public struct WhoopDeviceTime: Equatable, Sendable {
    public static let ticksPerSecond: UInt32 = 32_768

    public let seconds: UInt32
    public let ticks: UInt16

    /// Rejects noncanonical fractional components. Android's raw constructor
    /// accepts them, but its millisecond splitter emits only ticks below 32768.
    public init?(seconds: UInt32, ticks: UInt16) {
        guard UInt32(ticks) < Self.ticksPerSecond else { return nil }
        self.seconds = seconds
        self.ticks = ticks
    }

    /// Supports packet fields carried in a 32-bit slot without narrowing first.
    public init?(seconds: UInt32, ticks32: UInt32) {
        guard ticks32 < Self.ticksPerSecond else { return nil }
        self.init(seconds: seconds, ticks: UInt16(ticks32))
    }

    /// Mirrors `z32.a.n()`: double arithmetic followed by Java Math.round.
    /// Keep this operation order: floating-point rounding at the top of UInt32's
    /// range can differ from rounding the fractional component on its own.
    public var unixMilliseconds: Int64 {
        let milliseconds = Double(seconds) * 1000
            + Double(ticks) * 1000 / Double(Self.ticksPerSecond)
        return Int64(milliseconds.rounded(.toNearestOrAwayFromZero))
    }

    /// The same instant as Android's Joda DateTime(n()), rounded to milliseconds.
    /// Date represents an absolute instant; local time zones affect display only.
    public var date: Date {
        Date(timeIntervalSince1970: Double(unixMilliseconds) / 1000)
    }

    /// Apply the caller's actual import/session bounds before trusting the clock.
    /// No evidence establishes a universal zero sentinel or acceptable date range.
    public func validatedDate(in bounds: ClosedRange<Date>) -> Date? {
        let result = date
        return bounds.contains(result) ? result : nil
    }
}
