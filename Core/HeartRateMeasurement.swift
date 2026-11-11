import Foundation

/// Standard Bluetooth SIG Heart Rate Measurement (0x2A37), not WHOOP custom packets.
public enum HeartRateMeasurement {
    public static func decode(_ data: Data) -> Double? {
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else { return nil }
        let value: UInt16
        if bytes[0] & 1 == 1 {
            guard bytes.count >= 3 else { return nil }
            value = UInt16(bytes[1]) | (UInt16(bytes[2]) << 8)
        } else { value = UInt16(bytes[1]) }
        guard value > 0, value <= 300 else { return nil }
        return Double(value)
    }
}
