import WidgetKit
import SwiftUI
import ActivityKit
import WHOOPCore

@main
struct WorkoutLiveWidgets: WidgetBundle {
    var body: some Widget { WorkoutLiveWidget() }
}
struct WorkoutLiveWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveWorkoutAttributes.self) { context in
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(context.attributes.name, systemImage: "figure.run").font(.headline)
                    Spacer()
                    Text(context.isStale ? "WAITING FOR UPDATE" : context.state.isRecording ? context.state.isPaused ? "PAUSED" : "RECORDING" : "FINISHED").font(.caption2)
                }
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.isStale ? "—" : context.state.heartRate.map(String.init) ?? "—").font(.system(size: 32, weight: .bold))
                        Text(context.state.isRecording ? "LIVE BPM" : "LAST BPM").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        elapsed(context.state)
                        Text("ELAPSED").font(.caption2).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(context.isStale ? "—" : context.state.localStrain.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—").font(.system(size: 25, weight: .semibold)).foregroundStyle(.cyan)
                        Text("LOCAL STRAIN EST.").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }.padding(16).activityBackgroundTint(Color(red: 0.05, green: 0.07, blue: 0.09)).activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading) { Image(systemName: "heart.fill").foregroundStyle(.red); Text(context.isStale ? "—" : context.state.heartRate.map(String.init) ?? "—").font(.title2.bold()); Text("BPM").font(.caption2) }
                }
                DynamicIslandExpandedRegion(.trailing) { elapsed(context.state).font(.headline) }
                DynamicIslandExpandedRegion(.bottom) { Text(context.isStale ? "Waiting for fresh sensor data" : !context.state.isRecording ? "Workout finished" : context.state.isPaused ? "Workout paused" : context.attributes.name).font(.caption).foregroundStyle(.secondary) }
            } compactLeading: { Image(systemName: "figure.run").foregroundStyle(.cyan) }
              compactTrailing: { Text(context.isStale ? "—" : context.state.heartRate.map(String.init) ?? "—").font(.caption.monospacedDigit()) }
              minimal: { Image(systemName: "heart.fill").foregroundStyle(context.isStale ? .gray : .red) }
        }
    }
    @ViewBuilder private func elapsed(_ state: LiveWorkoutAttributes.ContentState) -> some View {
        if state.isRecording && !state.isPaused { Text(state.updatedAt.addingTimeInterval(-Double(state.elapsedSeconds)), style: .timer).monospacedDigit() }
        else { Text(String(format: "%02d:%02d", state.elapsedSeconds / 60, state.elapsedSeconds % 60)).monospacedDigit() }
    }
}
