import Foundation
import Combine
import ActivityKit
import WHOOPCore

@MainActor
final class LiveActivityDriver: ObservableObject {
    @Published var enabled: Bool = UserDefaults.standard.bool(forKey: "live.workout.activities") {
        didSet { UserDefaults.standard.set(enabled, forKey: "live.workout.activities"); update() }
    }
    @Published private(set) var status = "Live Activities are off."
    private var activity: Activity<LiveWorkoutAttributes>?
    private weak var recorder: WorkoutRecorder?
    private var changes: AnyCancellable?
    private var ending: AnyCancellable?
    private var requesting = false
    private var updating = false
    func bind(_ recorder: WorkoutRecorder) {
        guard self.recorder == nil else { return }
        self.recorder = recorder
        changes = recorder.objectWillChange.throttle(for: .seconds(5), scheduler: RunLoop.main, latest: true).sink { [weak self] _ in Task { @MainActor in self?.update() } }
        ending = recorder.$isRecording.removeDuplicates().sink { [weak self] _ in Task { @MainActor in self?.update() } }
        update()
    }
    private func update() {
        guard let recorder else { return }
        let fresh = !recorder.isPaused && (recorder.latestSampleDate.map { (0...10).contains(Date().timeIntervalSince($0)) } ?? false)
        let state = LiveWorkoutAttributes.ContentState(heartRate: fresh ? recorder.latestHeartRate.map { Int($0.rounded()) } : nil,
            localStrain: recorder.localStrain, elapsedSeconds: recorder.elapsedSeconds, updatedAt: Date(),
            isPaused: recorder.isPaused, isRecording: recorder.isRecording)
        let content = ActivityContent(state: state, staleDate: recorder.latestSampleDate?.addingTimeInterval(10) ?? Date().addingTimeInterval(15))
        if !enabled || !recorder.isRecording {
            let existing = Activity<LiveWorkoutAttributes>.activities
            self.activity = nil
            var final = state; final.isRecording = false; final.isPaused = true
            let policy: ActivityUIDismissalPolicy = enabled ? .after(Date().addingTimeInterval(300)) : .immediate
            Task { for item in existing { await item.end(ActivityContent(state: final, staleDate: nil), dismissalPolicy: policy) } }
            status = enabled ? "Start a workout to show it on your Lock Screen." : "Live Activities are off."
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { status = "Allow Live Activities in this app’s iPhone settings."; return }
        if let activity {
            guard !updating else { return }; updating = true
            Task { await activity.update(content); updating = false }
        } else {
            guard !requesting else { return }; requesting = true
            defer { requesting = false }
            do { activity = try Activity.request(attributes: LiveWorkoutAttributes(name: recorder.name), content: content, pushType: nil); status = "Workout shown on your Lock Screen. Stale readings are hidden." }
            catch { status = "The Live Activity could not start. Keep the app open and check Live Activities in Settings." }
        }
    }
}
