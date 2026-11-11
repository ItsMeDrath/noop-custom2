import Foundation

public enum ExampleData {
    /// Fixed illustrative values, anchored to the requested UTC day. No randomness or live score claims.
    public static func days(endingOn date: Date = Date()) -> [DailySnapshot] {
        let recoveries = [68, 76, 54, 83, 72, 61, 86]
        let strains = [11.4, 14.2, 8.1, 15.8, 12.6, 9.7, 13.2]
        let sleepScores = [82, 91, 74, 95, 87, 79, 92]
        let sleep = [424, 456, 392, 470, 438, 411, 462]
        let end = DayCalendar.start(of: date)
        return (0..<7).map { index in
            let day = DayCalendar.utc.date(byAdding: .day, value: index - 6, to: end)!
            let samples = (0..<96).map { step -> HeartRateSample in
                let hour = Double(step) / 4
                let asleep = hour < 7 || hour > 23
                let workout = hour >= 17 && hour < 18
                let baseline = asleep ? 52.0 : workout ? 134.0 : 70.0
                let wave = sin(Double(step + index * 3) * 0.7) * (workout ? 17 : 5)
                return .init(timestamp: day.addingTimeInterval(Double(step) * 900), bpm: (baseline + wave).rounded())
            }
            return .init(date: day, recovery: recoveries[index], strain: strains[index],
                         sleepPerformance: sleepScores[index], sleepMinutes: sleep[index], sleepNeededMinutes: 500,
                         restingHeartRate: Double(49 + index % 4), hrv: Double(68 + (index * 7) % 26),
                         respiratoryRate: 14.1 + Double(index % 3) / 10,
                         steps: 7120 + index * 431, energyKcal: Double(2080 + index * 59),
                         heartRates: samples, source: .example)
        }
    }
}
