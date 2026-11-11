import SwiftUI
import Charts
import WHOOPCore

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var tracker: DeviceModel
    let openMetric: (ScoreMetric) -> Void
    let openJournal: () -> Void
    let openActivity: () -> Void
    let openWorkout: () -> Void
    let openHealth: () -> Void
    let openStress: () -> Void
    let openActivities: () -> Void
    let openDevice: () -> Void
    let openHealthImport: () -> Void
    let openAccount: () -> Void
    private var day: DailySnapshot { store.selectedDay }

    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.profile.displayName.isEmpty ? "Your overview" : "Hi, \(store.profile.displayName)").font(WFont.number(28, bold: true))
                    Text("Make today count.").font(WFont.body(15)).foregroundStyle(WColor.muted)
                }
                Spacer()
                Button(action: openDevice) {
                    Image(systemName: "sensor.tag.radiowaves.forward").font(.system(size: 23, weight: .light)).foregroundStyle(tracker.connectedName == nil ? WColor.muted : WColor.green).frame(width: 48, height: 48)
                }.accessibilityLabel(tracker.connectedName == nil ? "Connect your tracker" : "Tracker connected, view device")
            }
            overview
            if !selectedDayExists(in: store) { setupCard }
            liveHeartRate
            if day.hrv != nil { dailyHighlight }
            HStack(spacing: 9) {
                MonitorShortcut(title: "HEALTH MONITOR", value: "VIEW METRICS", symbol: "heart.text.square", color: WColor.sleep, action: openHealth)
                MonitorShortcut(title: "NUTRITION", value: "LOG YOUR FOOD", symbol: "fork.knife", color: WColor.green, action: { store.tab = .nutrition })
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("My Day").font(WFont.number(22, bold: true))
                Button { openMetric(.recovery) } label: {
                    WCard(padding: 9) {
                        HStack(spacing: 9) {
                            Image(systemName: "w.circle").font(.system(size: 23, weight: .ultraLight)).foregroundStyle(WColor.muted)
                            Text("Your Daily Outlook").font(WFont.body(14))
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(WColor.muted)
                        }.frame(minHeight: 27)
                    }
                }.buttonStyle(.plain)
            }
            activities
            if day.sleepMinutes > 0 || day.sleepNeededMinutes > 0 { tonight }
            Button(action: openJournal) {
                WCard(padding: 13) {
                    HStack {
                        Text("MY JOURNAL").font(WFont.label(10)).tracking(0.7)
                        Spacer()
                        Image(systemName: "book.closed").font(.system(size: 12))
                        Text("FILL OUT").font(WFont.label(9)).tracking(0.7)
                        Image(systemName: "chevron.right").font(.system(size: 9))
                    }.foregroundStyle(.white)
                }
            }.buttonStyle(.plain)
            ReferenceDashboard()
            VStack(alignment: .leading, spacing: 10) {
                Text("Heart Rate").font(WFont.number(21, bold: true))
                WCard {
                    if day.heartRates.isEmpty {
                        MissingInline(symbol: "waveform.path.ecg", message: "No heart-rate samples for this day.")
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(decimalText(averageHeartRate, places: 0)).font(WFont.number(28, bold: true))
                            Text("BPM AVG").font(WFont.label(9)).foregroundStyle(WColor.muted)
                        }
                        HeartRateChart(samples: day.heartRates).frame(height: 145).padding(.top, 12)
                    }
                }
            }
        }
    }

    private var setupCard: some View {
        WCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Your day starts here").font(WFont.number(23, bold: true))
                Text("Connect your tracker to see live heart rate and record workouts. Import saved measurements to add sleep, Recovery and daily Strain to your overview.")
                    .font(WFont.body(15)).foregroundStyle(WColor.muted)
                Button(tracker.connectedName == nil ? "CONNECT MY TRACKER" : "VIEW MY TRACKER", action: openDevice).buttonStyle(WButton())
                HStack(spacing: 12) {
                    Button("APPLE HEALTH", action: openHealthImport).buttonStyle(WButton(filled: false))
                    Button("WHOOP ACCOUNT", action: openAccount).buttonStyle(WButton(filled: false))
                }
                Text("You can also import a data file in More → Your data.").font(WFont.body(12)).foregroundStyle(WColor.muted)
            }
        }
    }

    private var liveHeartRate: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            WCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text("LIVE HEART RATE").font(WFont.label(11)).tracking(0.8); Spacer(); Image(systemName: "heart.fill").foregroundStyle(WColor.blue) }
                    if let bpm = tracker.heartRate, let received = tracker.heartRateReceivedAt, (0...10).contains(timeline.date.timeIntervalSince(received)) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(bpm.formatted(.number.precision(.fractionLength(0)))).font(WFont.number(40, bold: true)).monospacedDigit()
                            Text("BPM").font(WFont.label(12)).foregroundStyle(WColor.muted)
                        }
                        Text(tracker.connectedName ?? "Connected sensor").font(WFont.body(13)).foregroundStyle(WColor.green)
                    } else {
                        Text(tracker.connectedName == nil ? "Connect a tracker to begin" : "Waiting for a heart-rate sample").font(WFont.body(17))
                        Button(tracker.connectedName == nil ? "FIND MY TRACKER" : "CHECK CONNECTION", action: openDevice)
                            .font(WFont.label(11)).foregroundStyle(WColor.blue).frame(minHeight: 44)
                    }
                }
            }
        }
    }

    private var overview: some View {
        VStack(spacing: 13) {
            WhoopWordmark().frame(width: 52, height: 9).padding(.top, 3).opacity(0.8)
            HStack(alignment: .top, spacing: 24) {
                ForEach(ScoreMetric.allCases) { metric in
                    Button { openMetric(metric) } label: {
                        VStack(spacing: 12) {
                            ScoreRing(metric: metric, day: day,
                                      comparisonFraction: precedingDay(in: store).flatMap { metric.value($0) == nil ? nil : metric.fraction($0) })
                                .frame(maxWidth: 99)
                            HStack(spacing: 3) {
                                Text(metric.title).font(WFont.label(10)).tracking(0.8)
                                Image(systemName: "chevron.right").font(.system(size: 7, weight: .bold))
                            }.foregroundStyle(.white)
                        }.frame(maxWidth: .infinity)
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 8)
            Text(!selectedDayExists(in: store) ? "NO DATA FOR THIS DAY" : day.source == .example ? "EXAMPLE DATA · NOT PERSONAL MEASUREMENTS" : "IMPORTED MEASUREMENTS")
                .font(WFont.label(7)).tracking(0.8).foregroundStyle(WColor.muted)
        }.padding(.bottom, 1)
    }

    private var dailyHighlight: some View {
        Button { openMetric(.recovery) } label: {
            WCard(padding: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Heart Rate Variability").font(WFont.number(19, bold: true))
                        Text(highlightText).font(WFont.body(13)).foregroundStyle(WColor.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    VStack(spacing: 4) {
                        Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 17, weight: .light))
                        Text(decimalText(day.hrv, places: 0)).font(WFont.number(15, bold: true))
                    }.foregroundStyle(WColor.sleep)
                }.frame(minHeight: 73, alignment: .top)
            }
        }.buttonStyle(.plain)
    }

    private var highlightText: String {
        guard let hrv = day.hrv else { return "Your HRV will appear here when a measurement is available. Tap to view your Recovery details." }
        if let previous = precedingDay(in: store)?.hrv, previous > 0 {
            let percent = (hrv - previous) / previous * 100
            if abs(percent) < 0.5 { return "Your HRV is \(decimalText(hrv, places: 0)) ms, similar to the previous recorded day. View your Recovery details for more context." }
            return "Your HRV is \(decimalText(abs(percent), places: 0))% \(percent > 0 ? "higher" : "lower") than the previous recorded day. View your Recovery details for more context."
        }
        return "Your recorded HRV is \(decimalText(hrv, places: 0)) ms. View your Recovery details alongside your resting heart rate."
    }

    private var activities: some View {
        VStack(spacing: 9) {
            HStack {
                Text("TODAY’S ACTIVITIES").font(WFont.label(10)).tracking(0.8)
                Spacer()
                Button("VIEW ALL", action: openActivities).font(WFont.label(8)).foregroundStyle(WColor.muted)
                    .accessibilityLabel("View all saved activities")
            }
            if day.sleepMinutes > 0 {
                Button { openMetric(.sleep) } label: {
                    WCard(padding: 8) {
                        HStack(spacing: 11) {
                            HStack(spacing: 5) {
                                Image(systemName: "moon.fill").font(.system(size: 15))
                                Text(clockDuration(day.sleepMinutes)).font(WFont.number(16, bold: true))
                            }.frame(width: 79, height: 39).background(WColor.sleep, in: RoundedRectangle(cornerRadius: 4))
                            Text("SLEEP").font(WFont.label(11)).tracking(0.8)
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(WColor.muted)
                        }
                    }
                }.buttonStyle(.plain)
            }
            ForEach(store.dayActivities) { activity in ReferenceActivityRow(activity: activity) }
            if day.sleepMinutes == 0 && store.dayActivities.isEmpty {
                Text("No activities recorded for this day.").font(WFont.body(13)).foregroundStyle(WColor.muted).padding(.vertical, 7)
            }
            HStack(spacing: 9) {
                compactAction("+  ADD ACTIVITY", action: openActivity)
                compactAction("▶  START ACTIVITY", action: openWorkout)
            }
        }
    }

    private var tonight: some View {
        Button { openMetric(.sleep) } label: {
            WCard {
                VStack(alignment: .leading, spacing: 15) {
                    HStack {
                        Text("TONIGHT’S SLEEP").font(WFont.label(10)).tracking(0.7)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(WColor.muted)
                    }
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(day.sleepNeededMinutes > 0 ? clockDuration(day.sleepNeededMinutes) : "—").font(WFont.number(28, bold: true)).foregroundStyle(WColor.sleep)
                            Text("SLEEP NEEDED").font(WFont.label(8)).foregroundStyle(WColor.muted)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(day.sleepMinutes > 0 ? clockDuration(day.sleepMinutes) : "—").font(WFont.number(28, bold: true))
                            Text("RECORDED SLEEP").font(WFont.label(8)).foregroundStyle(WColor.muted)
                        }
                    }
                }
            }
        }.buttonStyle(.plain)
    }

    private func compactAction(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(WFont.label(9)).tracking(0.4).frame(maxWidth: .infinity).padding(.vertical, 11)
                .background(WColor.elevated.opacity(0.8), in: RoundedRectangle(cornerRadius: 5))
        }.buttonStyle(.plain)
    }
    private func clockDuration(_ minutes: Int) -> String { String(format: "%d:%02d", minutes / 60, minutes % 60) }
    private var averageHeartRate: Double? {
        guard !day.heartRates.isEmpty else { return nil }
        return day.heartRates.map(\.bpm).reduce(0, +) / Double(day.heartRates.count)
    }
}

struct MiniMetric: View {
    let title: String
    let value: String
    let unit: String
    let symbol: String
    let color: Color
    var body: some View {
        WCard {
            HStack {
                Text(title).font(WFont.label(9)).tracking(1).foregroundStyle(WColor.muted)
                Spacer(); Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(color)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(WFont.number(28, bold: true)).lineLimit(1).minimumScaleFactor(0.6)
                Text(unit).font(WFont.body(11)).foregroundStyle(WColor.muted)
            }.padding(.top, 8)
        }
    }
}

struct MissingInline: View {
    let symbol: String
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 25, weight: .light))
            Text(message).font(WFont.body(14)).multilineTextAlignment(.center)
        }.foregroundStyle(WColor.muted).frame(maxWidth: .infinity).padding(.vertical, 22)
    }
}

struct ActivityRow: View {
    let activity: ActivityRecord
    var body: some View {
        WCard {
            HStack(spacing: 13) {
                Image(systemName: "figure.strengthtraining.traditional").font(.system(size: 25, weight: .light))
                    .foregroundStyle(WColor.blue).frame(width: 35)
                VStack(alignment: .leading, spacing: 4) {
                    Text(activity.name).font(WFont.number(19, bold: true))
                    Text("\(utcDateText(activity.start, style: .dateTime.month(.abbreviated).day())) · \(durationText(activity.durationMinutes))")
                        .font(WFont.body(13)).foregroundStyle(WColor.muted)
                }
                Spacer()
                if let score = activity.strain {
                    VStack(spacing: 3) {
                        Text(decimalText(score)).font(WFont.number(24, bold: true)).foregroundStyle(WColor.blue)
                        Text(activity.strainIsEstimate == true ? "LOCAL EST." : "STRAIN").font(WFont.label(8)).foregroundStyle(WColor.muted)
                    }
                } else { Text("LOGGED").font(WFont.label(9)).foregroundStyle(WColor.muted) }
            }
        }
    }
}

struct HealthView: View {
    @EnvironmentObject private var store: AppStore
    let openMetric: (ScoreMetric) -> Void
    let importData: () -> Void
    let openHealthImport: () -> Void
    private var day: DailySnapshot { store.selectedDay }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 0) {
                ForEach(ScoreMetric.allCases) { metric in
                    Button { openMetric(metric) } label: {
                        HStack(spacing: 5) {
                            Circle().trim(from: 0, to: metric.fraction(day)).stroke(metric.color, lineWidth: 2).rotationEffect(.degrees(-90)).frame(width: 16, height: 16)
                            Text(metric.title).font(WFont.label(9)).tracking(0.5)
                        }.frame(maxWidth: .infinity)
                    }.buttonStyle(.plain)
                }
            }.padding(.vertical, 5)
            SourceBadge(source: day.source, isEmpty: !selectedDayExists(in: store))
            HealthAgeCard()
            SectionHeading(title: "Health monitor", subtitle: "Measurements recorded for this day")
            WCard {
                VStack(alignment: .leading, spacing: 7) {
                    Text("HEART RATE").font(WFont.label(9)).tracking(0.6)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(decimalText(day.heartRates.last?.bpm, places: 0)).font(WFont.number(35, bold: true)).foregroundStyle(WColor.blue)
                        Text("BPM · LAST SAMPLE").font(WFont.label(8)).foregroundStyle(WColor.muted)
                    }
                    if !day.heartRates.isEmpty { HeartRateChart(samples: day.heartRates).frame(height: 95) }
                    else { Text("No heart-rate samples available").font(WFont.body(13)).foregroundStyle(WColor.muted) }
                }
            }
            HStack(spacing: 10) {
                healthTile("RESPIRATORY RATE", value: decimalText(day.respiratoryRate), unit: "rpm", symbol: "lungs", available: day.respiratoryRate != nil)
                healthTile("BLOOD OXYGEN", value: "—", unit: "%", symbol: "drop", available: false)
            }
            HStack(spacing: 10) {
                healthTile("RHR", value: decimalText(day.restingHeartRate, places: 0), unit: "bpm", symbol: "heart", available: day.restingHeartRate != nil)
                healthTile("HRV", value: decimalText(day.hrv, places: 0), unit: "ms", symbol: "waveform.path.ecg", available: day.hrv != nil)
            }
            HStack(spacing: 10) {
                healthTile("SKIN TEMP", value: "—", unit: "°C", symbol: "thermometer.medium", available: false)
                healthTile("SLEEP", value: day.sleepMinutes > 0 ? durationText(day.sleepMinutes) : "—", unit: "", symbol: "moon", available: day.sleepMinutes > 0)
            }
            Button("IMPORT FROM APPLE HEALTH", action: openHealthImport).buttonStyle(WButton())
            Button("IMPORT DAY DATA FILE", action: importData).buttonStyle(WButton(filled: false))
        }
    }
    private func healthTile(_ title: String, value: String, unit: String, symbol: String, available: Bool) -> some View {
        WCard(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: symbol).font(WFont.label(8)).foregroundStyle(WColor.muted).lineLimit(1).minimumScaleFactor(0.6)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value).font(WFont.number(27, bold: true)).lineLimit(1).minimumScaleFactor(0.6)
                    Text(value == "—" ? "" : unit).font(WFont.body(11)).foregroundStyle(WColor.muted)
                }
                Text(available ? "RECORDED" : "NOT AVAILABLE").font(WFont.label(7)).tracking(0.6)
                    .foregroundStyle(available ? WColor.sleep : WColor.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct HealthMetricRow: View {
    let title: String
    let value: String
    let unit: String
    let symbol: String
    let color: Color
    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 22)
            Text(title).font(WFont.body(15))
            Spacer(minLength: 6)
            Text(value).font(WFont.number(23, bold: true))
            Text(value == "—" ? "" : unit).font(WFont.body(11)).foregroundStyle(WColor.muted).frame(minWidth: 20, alignment: .leading)
        }.padding(.vertical, 14).accessibilityElement(children: .combine)
    }
}

struct HeartRateChart: View {
    let samples: [HeartRateSample]
    private var lower: Double { max(0, (samples.lazy.map(\.bpm).min() ?? 40) - 10) }
    private var upper: Double { max(lower + 20, (samples.lazy.map(\.bpm).max() ?? 100) + 10) }
    // Bounded rendering only: original samples and full-data statistics are untouched.
    // Keep each contiguous bucket's minimum and maximum in chronological order.
    private var plottedSamples: [HeartRateSample] {
        guard samples.count > 800 else { return samples }
        let bucketSize = max(1, Int(ceil(Double(samples.count) / 399.0)))
        var display: [HeartRateSample] = [samples[0]]
        display.reserveCapacity(800)
        for start in stride(from: 0, to: samples.count, by: bucketSize) {
            let end = min(start + bucketSize, samples.count)
            var minimum = start
            var maximum = start
            for index in start..<end {
                if samples[index].bpm < samples[minimum].bpm { minimum = index }
                if samples[index].bpm > samples[maximum].bpm { maximum = index }
            }
            for index in [minimum, maximum].sorted() {
                if display.last?.timestamp != samples[index].timestamp { display.append(samples[index]) }
            }
        }
        if display.last?.timestamp != samples.last?.timestamp, let last = samples.last { display.append(last) }
        return display
    }
    var body: some View {
        let display = plottedSamples
        Chart {
            ForEach(Array(display.enumerated()), id: \.offset) { item in
                AreaMark(x: .value("Time", item.element.timestamp), yStart: .value("Baseline", lower), yEnd: .value("Heart rate", item.element.bpm))
                    .foregroundStyle(LinearGradient(colors: [WColor.blue.opacity(0.22), WColor.blue.opacity(0.015)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Time", item.element.timestamp), y: .value("BPM", item.element.bpm))
                    .foregroundStyle(WColor.blue).lineStyle(StrokeStyle(lineWidth: 1.5))
                if samples.count == 1 {
                    PointMark(x: .value("Time", item.element.timestamp), y: .value("BPM", item.element.bpm)).foregroundStyle(WColor.blue)
                }
            }
        }
        .chartYScale(domain: lower...upper)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: utcDateFormat(.dateTime.hour())).foregroundStyle(WColor.muted)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(WColor.line)
                AxisValueLabel().foregroundStyle(WColor.muted)
            }
        }
        .accessibilityLabel("Heart rate overview from \(samples.count) samples")
    }
}
