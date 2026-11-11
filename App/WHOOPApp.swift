import SwiftUI

@main
@MainActor
struct WHOOPApp: App {
    @StateObject private var tracker = DeviceModel()
    @StateObject private var store = AppStore()
    @StateObject private var account = AccountModel()
    @StateObject private var recorder = WorkoutRecorder()
    @StateObject private var liveActivity = LiveActivityDriver()
    var body: some Scene {
        WindowGroup {
            PulseHomeView().environmentObject(tracker).environmentObject(store).environmentObject(account)
                .environmentObject(recorder).environmentObject(liveActivity)
                .task { recorder.bind(tracker); liveActivity.bind(recorder) }
                .preferredColorScheme(.dark)
        }
    }
}
