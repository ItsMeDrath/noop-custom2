import Foundation

/// Duration of the union of asleep intervals, clipped to a half-open day/range.
/// Callers must exclude awake and in-bed records before passing intervals here.
public enum SleepIntervals {
    public static func seconds(_ intervals: [DateInterval], within range: DateInterval) -> TimeInterval {
        guard range.start < range.end else { return 0 }
        let clipped = intervals.compactMap { interval -> DateInterval? in
            let start = max(interval.start, range.start)
            let end = min(interval.end, range.end)
            guard start < end else { return nil }
            return DateInterval(start: start, end: end)
        }.sorted { $0.start < $1.start }
        guard var current = clipped.first else { return 0 }
        var total: TimeInterval = 0
        for interval in clipped.dropFirst() {
            if interval.start <= current.end {
                current = DateInterval(start: current.start, end: max(current.end, interval.end))
            } else {
                total += current.duration
                current = interval
            }
        }
        return total + current.duration
    }

    /// Round down once after unioning intervals; never round each stage separately.
    public static func minutes(_ intervals: [DateInterval], within range: DateInterval) -> Int {
        Int((seconds(intervals, within: range) / 60).rounded(.down))
    }
}
