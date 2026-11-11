import Foundation

public enum CameraOverlayMode: String, CaseIterable, Sendable {
    case live, overview, strain, recovery, sleep
}
public enum CameraOverlayTone: String, Sendable { case cyan, green, yellow, red, neutral }
public struct CameraOverlayMetric: Equatable, Sendable {
    public let value: String
    public let label: String
    public let fraction: Double?
    public let tone: CameraOverlayTone
    public let available: Bool
}

/// Presentation of saved day values and explicitly timestamped received HR.
/// No WHOOP scores, calories or heart-rate samples are calculated here.
public enum CameraOverlayData {
    public static func metrics(mode: CameraOverlayMode, day: DailySnapshot,
                               liveHeartRate: Double?, sampleDate: Date?, now: Date = Date(),
                               elapsedSeconds: Int = 0) -> [CameraOverlayMetric] {
        let strain = metric(day.strain, label: "DAY STRAIN", maximum: 21, tone: .cyan, digits: 1)
        let recoveryValue = day.recovery.flatMap { (0...100).contains($0) ? Double($0) : nil }
        let recovery = metric(recoveryValue, label: "RECOVERY", maximum: 100,
                              tone: (recoveryValue ?? 0) <= 33 ? .red : (recoveryValue ?? 0) <= 66 ? .yellow : .green,
                              suffix: "%")
        let minutes = day.sleepMinutes
        let sleep = CameraOverlayMetric(value: minutes > 0 && minutes <= 1_440 ? "\(minutes / 60):\(String(format: "%02d", minutes % 60))" : "Sync",
                                        label: "HOURS\nOF SLEEP", fraction: nil, tone: .neutral,
                                        available: minutes > 0 && minutes <= 1_440)
        switch mode {
        case .overview: return [strain, recovery, sleep]
        case .strain: return [strain]
        case .recovery: return [recovery]
        case .sleep: return [sleep]
        case .live:
            let fresh = sampleDate.map { (0...10).contains(now.timeIntervalSince($0)) } ?? false
            let rate = liveHeartRate.flatMap { $0.isFinite && (1...300).contains($0) && fresh ? $0 : nil }
            let heartRate = metric(rate, label: "BPM", maximum: 300, tone: .neutral, missing: "Connect")
            let energy = metric(day.energyKcal > 0 ? day.energyKcal : nil, label: "DAY CALORIES", maximum: 100_000, tone: .neutral)
            let seconds = min(21_600, max(0, elapsedSeconds))
            let timer = CameraOverlayMetric(value: "\(seconds / 60):\(String(format: "%02d", seconds % 60))",
                                            label: "TIMER", fraction: nil, tone: .neutral, available: true)
            return [heartRate, strain, energy, timer]
        }
    }
    private static func metric(_ number: Double?, label: String, maximum: Double, tone: CameraOverlayTone,
                               digits: Int = 0, suffix: String = "", missing: String = "Sync") -> CameraOverlayMetric {
        guard let number, number.isFinite, (0...maximum).contains(number) else {
            return .init(value: missing, label: label, fraction: nil, tone: .neutral, available: false)
        }
        let value = String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), digits, number) + suffix
        return .init(value: value, label: label, fraction: min(1, max(0, number / maximum)), tone: tone, available: true)
    }
}
