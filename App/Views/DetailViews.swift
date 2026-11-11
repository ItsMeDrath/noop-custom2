import SwiftUI
import Charts
import WHOOPCore

struct MetricDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let metric: ScoreMetric
    var embedded = false
    @State private var showingInformation = false
    @State private var showingCoach = false
    private var day: DailySnapshot { store.selectedDay }
    private var previous: DailySnapshot? { precedingDay(in: store) }
    private var trend: [DailySnapshot] {
        Array(store.days.filter { $0.source == day.source && $0.date <= day.date && metric.value($0) != nil }.sorted { $0.date < $1.date }.suffix(7))
    }
    var body: some View {
        VStack(spacing: 0) {
            if !embedded { header }
            if embedded { content } else { ScrollView { content }.scrollIndicators(.hidden) }
        }.background { WhoopBackground() }
            .alert("About this score", isPresented: $showingInformation) {
                Button("Done", role: .cancel) { }
            } message: { Text(metric.description + " A comparison marker shows the previous recorded UTC day when available. Missing fields are not inferred from summary scores.") }
            .alert("WHOOP Coach", isPresented: $showingCoach) {
                Button("Done", role: .cancel) { }
            } message: { Text("WHOOP Coach is not connected in this edition. You can view your recorded measurements and activities here; personalized Coach responses are unavailable.") }
    }
    private var content: some View {
                VStack(spacing: 23) {
                    ScoreRing(metric: metric, day: day, large: true,
                              comparisonFraction: previous.flatMap { metric.value($0) == nil ? nil : metric.fraction($0) })
                        .padding(.top, 13).padding(.bottom, 5)
                    Text(day.source == .example ? "EXAMPLE DATA · NOT PERSONAL MEASUREMENTS" : "IMPORTED MEASUREMENTS")
                        .font(WFont.label(7)).tracking(0.9).foregroundStyle(WColor.muted)
                    WCard(padding: 16) { statistics }
                        .overlay(alignment: .top) {
                            StatisticsPointer().fill(WColor.card).frame(width: 18, height: 9).offset(y: -8)
                        }.padding(.top, 5)
                    DetailInsight(text: insight, actionTitle: "LEARN MORE WITH COACH") { showingCoach = true }
                    if metric == .strain {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Today’s Activities").font(WFont.number(24, bold: true))
                            ForEach(store.dayActivities) { activity in ReferenceActivityRow(activity: activity) }
                            if store.dayActivities.isEmpty {
                                Text("No activities recorded for this day.").font(WFont.body(14)).foregroundStyle(WColor.muted)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !trend.isEmpty { trendCard }
                    if !day.heartRates.isEmpty {
                        SectionHeading(title: "Heart rate")
                        WCard { HeartRateChart(samples: day.heartRates).frame(height: 160) }
                    }
                    Text(day.source == .example ? "These are illustrative measurements, not readings from your body." : "Unavailable measurements are shown as a dash. Supplied scores are preserved as recorded.")
                        .font(WFont.body(12)).foregroundStyle(WColor.muted).multilineTextAlignment(.center)
                }.padding(.horizontal, 17).padding(.bottom, 30).frame(maxWidth: 600).frame(maxWidth: .infinity)
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 25, weight: .light)).frame(width: 42, height: 44)
            }.accessibilityLabel("Back")
            Spacer()
            Text(DayCalendar.utc.isDateInToday(day.date) ? "TODAY" : utcDateText(day.date, style: .dateTime.month(.abbreviated).day()).uppercased())
                .font(WFont.label(12)).tracking(1.5)
            Spacer()
            Button { showingInformation = true } label: {
                Image(systemName: "info.circle").font(.system(size: 26, weight: .ultraLight))
                    .foregroundStyle(WColor.muted).frame(width: 42, height: 44)
            }.accessibilityLabel("About this score")
        }.foregroundStyle(.white).padding(.horizontal, 14).padding(.top, 5).padding(.bottom, 10)
    }

    @ViewBuilder private var statistics: some View {
        VStack(spacing: 0) {
            if metric == .recovery {
                ReferenceMetricRow(title: "Heart rate variability", value: decimalText(day.hrv, places: 0), symbol: "waveform.path.ecg", unit: "ms", difference: delta(day.hrv, previous?.hrv))
                Divider().overlay(WColor.line)
                ReferenceMetricRow(title: "Resting heart rate", value: decimalText(day.restingHeartRate, places: 0), symbol: "heart", difference: delta(day.restingHeartRate, previous?.restingHeartRate))
                Divider().overlay(WColor.line)
                ReferenceMetricRow(title: "Respiratory rate", value: decimalText(day.respiratoryRate), symbol: "lungs", difference: delta(day.respiratoryRate, previous?.respiratoryRate))
                Divider().overlay(WColor.line)
                ReferenceMetricRow(title: "Sleep performance", value: day.sleepPerformance.map { "\($0)%" } ?? "—", symbol: "moon")
            } else if metric == .sleep {
                ReferenceMetricRow(title: "Hours vs. needed", value: sleepRatio, symbol: "clock")
                Divider().overlay(WColor.line)
                ReferenceMetricRow(title: "Sleep consistency", value: "—", symbol: "bed.double")
                Divider().overlay(WColor.line)
                ReferenceMetricRow(title: "Sleep efficiency", value: "—", symbol: "bed.double")
                Divider().overlay(WColor.line)
                ReferenceMetricRow(title: "Sleep stress", value: "—", symbol: "gauge.with.dots.needle.33percent")
                HStack(spacing: 12) {
                    legend("Poor", color: WColor.yellow)
                    legend("Sufficient", color: WColor.muted)
                    legend("Optimal", color: .mint)
                }.padding(.top, 10).padding(.bottom, 3)
            } else {
                ReferenceMetricRow(title: "Heart rate zones 1–3", value: "—", symbol: "heart.text.square")
                Divider().overlay(WColor.line)
                ReferenceMetricRow(title: "Heart rate zones 4–5", value: "—", symbol: "heart.text.square")
                Divider().overlay(WColor.line)
                ReferenceMetricRow(title: "Strength training time", value: strengthMinutes.map { clockDuration($0) } ?? "—", symbol: "dumbbell")
                Divider().overlay(WColor.line)
                ReferenceMetricRow(title: "Average heart rate", value: decimalText(averageHeartRate, places: 0), symbol: "heart")
            }
        }
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Recent Days").font(WFont.number(22, bold: true))
            WCard {
                Chart {
                    ForEach(trend) { item in
                        if let value = metric.value(item) {
                            BarMark(x: .value("Day", item.date, unit: .day), y: .value(metric.title, value))
                                .foregroundStyle(metric.color.opacity(DayCalendar.utc.isDate(item.date, inSameDayAs: day.date) ? 1 : 0.4)).cornerRadius(3)
                        }
                    }
                }.frame(height: 145).chartYScale(domain: metric == .strain ? 0.0...21.0 : 0.0...100.0)
                    .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: utcDateFormat(.dateTime.weekday(.abbreviated))).foregroundStyle(WColor.muted) } }
                    .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in AxisGridLine().foregroundStyle(WColor.line); AxisValueLabel().foregroundStyle(WColor.muted) } }
            }
        }
    }
    private var insight: String {
        guard metric.value(day) != nil else { return "Your score will appear here when it is included in your recorded data. Heart-rate samples alone do not supply this score." }
        if metric == .strain, let strain = day.strain {
            if strain >= 14 && strain < 18 { return "Strain between 14 and 17.9 is considered strenuous, meaning your cardiovascular system has been working hard." }
            return "Your recorded Day Strain is \(decimalText(strain)) on a 0–21 scale. Review your activities and measurements to see the context of your day."
        }
        if metric == .sleep {
            guard day.sleepMinutes > 0, day.sleepNeededMinutes > 0 else { return "Your Sleep Performance score is shown as supplied. Sleep duration or sleep need is unavailable for this day." }
            return "You recorded \(durationText(day.sleepMinutes)) of sleep against \(durationText(day.sleepNeededMinutes)) of sleep need. Your Sleep Performance score is preserved as supplied."
        }
        return "View your recorded HRV, resting heart rate, respiratory rate and Sleep Performance alongside your Recovery score. Missing measurements are left blank."
    }
    private var sleepRatio: String {
        guard day.sleepMinutes > 0, day.sleepNeededMinutes > 0 else { return "—" }
        return "\(clockDuration(day.sleepMinutes)) / \(clockDuration(day.sleepNeededMinutes))"
    }
    private var strengthMinutes: Int? {
        let rows = store.dayActivities.filter { $0.name.localizedCaseInsensitiveContains("strength") }
        return rows.isEmpty ? nil : rows.reduce(0) { $0 + $1.durationMinutes }
    }
    private var averageHeartRate: Double? {
        guard !day.heartRates.isEmpty else { return nil }
        return day.heartRates.map(\.bpm).reduce(0, +) / Double(day.heartRates.count)
    }
    private func delta(_ value: Double?, _ previous: Double?) -> Double? {
        guard let value, let previous else { return nil }; return value - previous
    }
    private func clockDuration(_ minutes: Int) -> String { String(format: "%d:%02d", minutes / 60, minutes % 60) }
    private func legend(_ title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 11, height: 3)
            Text(title).font(WFont.body(10)).foregroundStyle(WColor.muted)
        }
    }
}

private struct StatisticsPointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(); path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)); path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY)); path.closeSubpath()
        return path
    }
}

struct DetailValueRow: View {
    let title: String
    let value: String
    var color: Color = .white
    var body: some View {
        HStack {
            Text(title).font(WFont.body(15)).foregroundStyle(WColor.muted)
            Spacer(); Text(value).font(WFont.number(27, bold: true)).foregroundStyle(color)
        }
    }
}

struct JournalEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var caffeine = false
    @State private var alcohol = false
    @State private var lateMeal = false
    @State private var note = ""
    @State private var confirmDelete = false
    var body: some View {
        SheetScaffold(title: "DAILY JOURNAL") {
            VStack(alignment: .leading, spacing: 22) {
                Text(utcDateText(store.selectedDate, style: Date.FormatStyle(date: .complete, time: .omitted))).font(WFont.body(14)).foregroundStyle(WColor.muted)
                Text("WHAT SHAPED\nYOUR DAY?").font(WFont.number(35, bold: true))
                Text("Build a record of your habits. Your answers stay on this iPhone.").font(WFont.body(16)).foregroundStyle(WColor.muted)
                WCard {
                    Toggle("Consumed caffeine", isOn: $caffeine).padding(.vertical, 8)
                    Divider().padding(.vertical, 10)
                    Toggle("Consumed alcohol", isOn: $alcohol).padding(.vertical, 8)
                    Divider().padding(.vertical, 10)
                    Toggle("Ate close to bedtime", isOn: $lateMeal).padding(.vertical, 8)
                }.tint(WColor.green)
                SectionHeading(title: "Anything else?")
                TextEditor(text: $note).font(WFont.body(16)).scrollContentBackground(.hidden)
                    .frame(minHeight: 140).padding(12).background(WColor.card, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityLabel("Journal notes")
                    .onChange(of: note) { _, value in if value.count > LocalBackupCodec.maximumNoteCharacters { note = String(value.prefix(LocalBackupCodec.maximumNoteCharacters)) } }
                Text("\(note.count)/\(LocalBackupCodec.maximumNoteCharacters) characters").font(WFont.body(12)).foregroundStyle(WColor.muted)
                Button("SAVE JOURNAL") {
                    store.saveJournal(JournalEntry(date: store.selectedDate, caffeine: caffeine, alcohol: alcohol, lateMeal: lateMeal, note: note))
                    dismiss()
                }.buttonStyle(WButton())
                Button("Delete this journal entry", role: .destructive) { confirmDelete = true }.frame(maxWidth: .infinity)
            }
        }.confirmationDialog("Delete this day's journal entry?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete entry", role: .destructive) { store.deleteJournal(); dismiss() }
        }.onAppear {
            let entry = store.currentJournal
            caffeine = entry.caffeine; alcohol = entry.alcohol; lateMeal = entry.lateMeal; note = entry.note
        }
    }
}

struct ActivityEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var activity = "Running"
    @State private var customName = ""
    @State private var minutes = 30
    private let types = ["Running", "Strength training", "Cycling", "Walking", "Swimming", "Yoga", "Other"]
    private var name: String { activity == "Other" ? customName.trimmingCharacters(in: .whitespacesAndNewlines) : activity }
    var body: some View {
        SheetScaffold(title: "LOG ACTIVITY") {
            VStack(alignment: .leading, spacing: 24) {
                Text("MAKE YOUR\nMOVEMENT COUNT.").font(WFont.number(35, bold: true))
                Text(utcDateText(store.selectedDate, style: Date.FormatStyle(date: .complete, time: .omitted))).font(WFont.body(15)).foregroundStyle(WColor.muted)
                WCard {
                    HStack {
                        Text("Activity").font(WFont.body(16)); Spacer()
                        Picker("Activity", selection: $activity) { ForEach(types, id: \.self) { Text($0).tag($0) } }.tint(WColor.blue)
                    }
                    if activity == "Other" {
                        Divider().padding(.vertical, 10)
                        TextField("Activity name", text: $customName).textInputAutocapitalization(.words).font(WFont.body(16))
                    }
                    Divider().padding(.vertical, 14)
                    Stepper(value: $minutes, in: 1...600, step: 1) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Duration").font(WFont.body(15)).foregroundStyle(WColor.muted)
                            Text(durationText(minutes)).font(WFont.number(27, bold: true))
                        }
                    }.tint(.white)
                }
                Text("This records an activity and its duration. It does not add an estimated strain or calorie score.")
                    .font(WFont.body(14)).foregroundStyle(WColor.muted)
                Button("SAVE ACTIVITY") { store.logActivity(name: name, minutes: minutes); dismiss() }
                    .buttonStyle(WButton()).disabled(name.isEmpty)
            }
        }
    }
}

struct DeviceSheetView: View {
    @EnvironmentObject private var device: DeviceModel
    var body: some View {
        SheetScaffold(title: "DEVICE CONNECTION") {
            VStack(spacing: 22) {
                Image(systemName: "sensor.tag.radiowaves.forward").font(.system(size: 58, weight: .ultraLight)).foregroundStyle(WColor.blue).padding(.vertical, 16)
                SectionHeading(title: device.connectedName ?? "Connect a device", subtitle: device.status)
                if let name = device.connectedName {
                    WCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(name).font(WFont.number(23, bold: true))
                                Text("CONNECTED").font(WFont.label(10)).tracking(0.8).foregroundStyle(WColor.green)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(decimalText(device.heartRate, places: 0)).font(WFont.number(39, bold: true))
                                Text("LIVE BPM").font(WFont.label(9)).foregroundStyle(WColor.muted)
                            }
                        }
                    }
                    if device.canStartCustomStream || device.startingCustomStream {
                        Button(device.startingCustomStream ? "STARTING LIVE HEART RATE…" : "START DEVICE HEART RATE") {
                            device.startCustomStream()
                        }.buttonStyle(WButton()).disabled(device.startingCustomStream)
                        Text("This optional request uses a recovered device protocol and still needs physical-strap testing. It does not sync history or validate the full device initialization sequence.")
                            .font(WFont.body(13)).foregroundStyle(WColor.muted)
                    }
                    Button("DISCONNECT") { device.disconnect() }.buttonStyle(WButton(filled: false))
                } else {
                    Button(device.isScanning ? "STOP SEARCHING" : "SEARCH FOR DEVICES") {
                        if device.isScanning { device.stop() } else { device.scan() }
                    }.buttonStyle(WButton())
                }
                if device.isScanning { ProgressView().tint(WColor.blue).accessibilityLabel("Searching nearby Bluetooth devices") }
                if !device.devices.isEmpty {
                    SectionHeading(title: "Nearby devices")
                    ForEach(device.devices) { item in
                        Button { device.connect(item) } label: {
                            WCard {
                                HStack(spacing: 12) {
                                    Image(systemName: "sensor.tag.radiowaves.forward").foregroundStyle(WColor.blue)
                                    Text(item.name).font(WFont.body(16))
                                    Spacer(); Text("\(item.rssi) dBm").font(WFont.body(11)).foregroundStyle(WColor.muted)
                                    Image(systemName: "chevron.right").font(.system(size: 10))
                                }
                            }
                        }.buttonStyle(.plain).disabled(device.connectedName != nil)
                    }
                } else if !device.isScanning && device.connectedName == nil {
                    EmptyCard(symbol: "dot.radiowaves.left.and.right", title: "Find your heart-rate source", detail: "Keep your device nearby and turn on heart-rate broadcasting, if available.")
                }
                if let history = device.lastHistoryRecord {
                    WCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("HISTORICAL NOTIFICATIONS").font(WFont.label(11)).tracking(0.8)
                            Text("\(device.historicalFrames) received · revision \(history.rawRevision)")
                                .font(WFont.body(14)).foregroundStyle(WColor.muted)
                            if let counter = history.packetCounter { Text("Packet counter \(counter)").font(WFont.body(13)) }
                            if let time = history.deviceTime,
                               let date = time.validatedDate(in: Date(timeIntervalSince1970: 946_684_800)...Date().addingTimeInterval(86_400)) {
                                Text("Device time: \(utcDateText(date, style: .dateTime.year().month().day().hour().minute().second())) UTC")
                                    .font(WFont.body(13))
                            }
                            Text("Only the common packet header is decoded. No historical heart rate is inferred, and no transfer acknowledgement or erase command is sent.")
                                .font(WFont.body(13)).foregroundStyle(WColor.muted)
                            ShareLink(item: history.rawFrame.base64EncodedString()) {
                                Label("Share latest raw frame text", systemImage: "square.and.arrow.up")
                            }.font(WFont.body(14))
                        }
                    }
                }
                WCard {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("ABOUT THIS CONNECTION").font(WFont.label(11)).tracking(0.8)
                        Text("Live heart rate can use standard Bluetooth broadcasts or validated WHOOP notifications when the device streams them. A connection does not sync history or generate daily Recovery and sleep scores.")
                            .font(WFont.body(14)).foregroundStyle(WColor.muted)
                    }
                }
            }
        }
    }
}
