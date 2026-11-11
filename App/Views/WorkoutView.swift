import SwiftUI
import WHOOPCore

struct WorkoutView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var recorder: WorkoutRecorder
    @EnvironmentObject private var device: DeviceModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Running"
    @State private var resting = 55.0
    @State private var maximum = 190.0
    @State private var error: String?
    @State private var confirmDiscard = false
    var body: some View {
        SheetScaffold(title: "RECORD WORKOUT") {
            VStack(alignment: .leading, spacing: 23) {
                Text(recorder.isRecording ? recorder.name.uppercased() : "MAKE IT\nCOUNT.").font(WFont.number(37, bold: true))
                Label(device.connectedName ?? "No heart-rate source connected", systemImage: "sensor.tag.radiowaves.forward")
                    .font(WFont.body(15)).foregroundStyle(device.connectedName == nil ? WColor.yellow : WColor.green)
                if recorder.isRecording {
                    WCard {
                        Text("DURATION").font(WFont.label(10)).foregroundStyle(WColor.muted)
                        Text(clock(recorder.elapsedSeconds)).font(WFont.number(55, bold: true)).monospacedDigit()
                        HStack {
                            VStack(alignment: .leading) {
                                Text(decimalText(recorder.latestHeartRate, places: 0)).font(WFont.number(36, bold: true))
                                Text(recorder.heartRateIsFresh ? "LIVE BPM" : "LAST BPM").font(WFont.label(9)).foregroundStyle(WColor.muted)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(decimalText(recorder.localStrain)).font(WFont.number(36, bold: true)).foregroundStyle(WColor.blue)
                                Text("LOCAL STRAIN ESTIMATE").font(WFont.label(9)).foregroundStyle(WColor.muted)
                            }
                        }.padding(.top, 12)
                        Text("\(recorder.samples) recorded samples").font(WFont.body(13)).foregroundStyle(WColor.muted).padding(.top, 10)
                    }
                    Text(recorder.status).font(WFont.body(15)).foregroundStyle(WColor.muted)
                    Button(recorder.isPaused ? "RESUME" : "PAUSE") { recorder.togglePause() }.buttonStyle(WButton(filled: false))
                    Button("FINISH & SAVE") {
                        do { try recorder.save(to: store); dismiss() } catch { self.error = error.localizedDescription }
                    }.buttonStyle(WButton())
                    Button("Discard recording", role: .destructive) { confirmDiscard = true }.frame(maxWidth: .infinity)
                } else {
                    WCard {
                        TextField("Workout name", text: $name).font(WFont.number(24, bold: true)).textInputAutocapitalization(.words)
                        Divider().padding(.vertical, 15)
                        Stepper("Resting HR: \(Int(resting)) BPM", value: $resting, in: 30...110).font(WFont.body(15))
                        Stepper("Maximum HR: \(Int(maximum)) BPM", value: $maximum, in: 120...230).font(WFont.body(15)).padding(.top, 14)
                    }
                    Text("Use your known resting and maximum heart rates. The local strain estimate uses recorded heart rate and does not replace an official WHOOP daily score.")
                        .font(WFont.body(15)).foregroundStyle(WColor.muted)
                    Button("START RECORDING") {
                        do { try recorder.start(name: name, resting: resting, maximum: maximum) }
                        catch { self.error = error.localizedDescription }
                    }.buttonStyle(WButton()).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Text("Keep this app open while recording. Pauses and missing signal are not filled with invented readings. Recording is limited to 6 hours or 21,600 readings.")
                    .font(WFont.body(13)).foregroundStyle(WColor.muted)
            }
        }
        .alert("Recording needs attention", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        .confirmationDialog("Discard this recording?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { recorder.discard(); dismiss() }
        }
    }
    private func clock(_ seconds: Int) -> String { String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) }
}

struct ActivityLibraryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editing: ActivityRecord?
    @State private var deleting: ActivityRecord?
    var body: some View {
        SheetScaffold(title: "YOUR ACTIVITIES") {
            VStack(spacing: 14) {
                if store.activities.isEmpty {
                    EmptyCard(symbol: "figure.run", title: "Your next session starts here", detail: "Log or record an activity from the Menu.")
                }
                ForEach(store.activities.sorted { $0.start > $1.start }) { activity in
                    VStack(spacing: 8) {
                        Button { editing = activity } label: { ActivityRow(activity: activity) }.buttonStyle(.plain)
                        HStack {
                            Button("Edit") { editing = activity }; Spacer()
                            Button("Delete", role: .destructive) { deleting = activity }
                        }.font(WFont.body(13)).padding(.horizontal, 8)
                    }
                }
            }
        }
        .sheet(item: $editing) { ActivityEditView(activity: $0) }
        .confirmationDialog("Delete this activity?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete activity", role: .destructive) { if let deleting { store.deleteActivity(deleting.id) }; deleting = nil }
        }
    }
}

private struct ActivityEditView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let activity: ActivityRecord
    @State private var name: String
    @State private var minutes: Int
    init(activity: ActivityRecord) {
        self.activity = activity; _name = State(initialValue: activity.name)
        _minutes = State(initialValue: activity.durationMinutes)
    }
    var body: some View {
        SheetScaffold(title: "EDIT ACTIVITY") {
            VStack(alignment: .leading, spacing: 23) {
                TextField("Activity", text: $name).font(WFont.number(26, bold: true))
                Stepper("\(minutes) minutes", value: $minutes, in: 1...1440)
                Text("Changing the duration clears its strain value. Recorded heart-rate measurements remain in your day data.")
                    .font(WFont.body(14)).foregroundStyle(WColor.muted)
                Button("SAVE CHANGES") { store.updateActivity(activity.id, name: name, minutes: minutes); dismiss() }
                    .buttonStyle(WButton()).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
