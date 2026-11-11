#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation

public struct LiveWorkoutAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public var heartRate: Int?
        public var localStrain: Double?
        public var elapsedSeconds: Int
        public var updatedAt: Date
        public var isPaused: Bool
        public var isRecording: Bool
        public init(heartRate: Int?, localStrain: Double?, elapsedSeconds: Int, updatedAt: Date, isPaused: Bool, isRecording: Bool) {
            self.heartRate = heartRate; self.localStrain = localStrain; self.elapsedSeconds = elapsedSeconds
            self.updatedAt = updatedAt; self.isPaused = isPaused; self.isRecording = isRecording
        }
    }
    public var name: String
    public init(name: String) { self.name = name }
}
#endif
