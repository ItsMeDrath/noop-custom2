import Foundation

/// Presentation-only fixtures. Never merged into the user's saved health data.
struct PulseHomeData: Decodable {
    let initials: String
    let firstName: String
    let streak: Int
    let coachGreeting: String
    let coachReply: String
    let battery: Int
    let days: [PulseHomeDay]
    static func load() throws -> PulseHomeData {
        guard let url = Bundle.main.url(forResource: "pulse-home-mock", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let value = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard value.days.count == 7, Set(value.days.map(\.id)).count == 7,
              value.days.allSatisfy({ (0...100).contains($0.sleep) && (0...100).contains($0.readiness) && (0...21).contains($0.load) }) else {
            throw CocoaError(.coderReadCorrupt)
        }
        return value
    }
}
struct PulseHomeDay: Decodable, Identifiable {
    let id: String
    let weekday: String
    let dayNumber: Int
    let healthStatus: String
    let healthDetail: String
    let stressValue: Double
    let stressUpdated: String
    let stressValues: [Double]
    let activities: [PulseHomeActivity]
    let date: String
    let sleep: Int
    let readiness: Int
    let load: Double
    let previousSleep: Int
    let previousReadiness: Int
    let previousLoad: Double
    let insightTitle: String
    let insightBody: String
    let hrv: Int
    let tension: String
    let focus: String
    let sleepDuration: String
    let sleepStart: String
    let wakeTime: String
    let sleepNeed: String
    let bedtime: String
    let plannedWake: String
    let planDaysRemaining: Int
    let planPercent: Int
    let planTitle: String
    let statistics: [PulseHomeStatistic]
    let heartRates: [Double]
}
struct PulseHomeStatistic: Decodable, Identifiable {
    let id: String
    let title: String
    let value: String
    let unit: String
    let baseline: String
    let symbol: String
    let tone: String
    let direction: Int
}

struct PulseHomeActivity: Decodable, Identifiable {
    let id: String
    let title: String
    let metric: String
    let start: String
    let end: String
    let symbol: String
    let isSleep: Bool
}
