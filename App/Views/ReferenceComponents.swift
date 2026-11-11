import SwiftUI
import WHOOPCore

/// View-only comparisons use the previous UTC day of the same provenance.
@MainActor
func precedingDay(in store: AppStore) -> DailySnapshot? {
    guard let date = DayCalendar.utc.date(byAdding: .day, value: -1, to: store.selectedDay.date) else { return nil }
    return store.days.first { $0.source == store.selectedDay.source && DayCalendar.utc.isDate($0.date, inSameDayAs: date) }
}

struct ReferenceMetricRow: View {
    let title: String
    let value: String
    var symbol: String = ""
    var unit: String = ""
    var previous: String? = nil
    var difference: Double? = nil
    var compact = false
    var body: some View {
        HStack(spacing: 10) {
            if !symbol.isEmpty {
                Image(systemName: symbol).font(.system(size: compact ? 15 : 18, weight: .light))
                    .foregroundStyle(WColor.muted).frame(width: compact ? 20 : 24)
            }
            Text(title.uppercased()).font(WFont.label(compact ? 10 : 11)).tracking(0.7)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 5)
            VStack(alignment: .trailing, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value).font(WFont.number(compact ? 22 : 25, bold: true))
                    if !unit.isEmpty && value != "—" { Text(unit).font(WFont.body(10)).foregroundStyle(WColor.muted) }
                }
                if let previous { Text(previous).font(WFont.number(10)).foregroundStyle(WColor.muted) }
            }
            if let difference, difference.isFinite, difference != 0 {
                Image(systemName: difference > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .font(.system(size: 6)).foregroundStyle(WColor.muted)
                    .accessibilityLabel(difference > 0 ? "Increased from previous day" : "Decreased from previous day")
            }
        }.padding(.vertical, compact ? 1 : 13)
            .accessibilityElement(children: .combine)
    }
}

struct MonitorShortcut: View {
    let title: String
    let value: String
    let symbol: String
    let color: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            WCard(padding: 12) {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: symbol).font(.system(size: 16, weight: .light)).foregroundStyle(color)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(title).font(WFont.label(9)).tracking(0.5)
                        Text(value).font(WFont.label(9)).foregroundStyle(color)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(WColor.muted)
                }.frame(minHeight: 34, alignment: .center)
            }
        }.buttonStyle(.plain)
    }
}

struct ReferenceActivityRow: View {
    let activity: ActivityRecord
    var body: some View {
        WCard(padding: 8) {
            HStack(spacing: 11) {
                HStack(spacing: 5) {
                    Image(systemName: "figure.run").font(.system(size: 17, weight: .light))
                    Text(activity.strain.map { decimalText($0) } ?? "—").font(WFont.number(17, bold: true))
                }.frame(width: 79, height: 39).background(WColor.blue.opacity(0.8), in: RoundedRectangle(cornerRadius: 4))
                VStack(alignment: .leading, spacing: 3) {
                    Text(activity.name.uppercased()).font(WFont.label(11)).lineLimit(1)
                    if activity.strainIsEstimate == true { Text("LOCAL STRAIN ESTIMATE").font(WFont.label(7)).foregroundStyle(WColor.muted) }
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(utcDateText(activity.start, style: .dateTime.hour().minute())).font(WFont.number(10))
                    Text(durationText(activity.durationMinutes)).font(WFont.number(10)).foregroundStyle(WColor.muted)
                }
            }
        }
    }
}

enum DashboardItem: Int, CaseIterable, Identifiable {
    case hrv, restingHeartRate, steps, zonesLow, zonesHigh, vo2, calories, stress
    var id: Int { rawValue }
    var bit: Int { 1 << rawValue }
    var title: String {
        switch self {
        case .hrv: return "Heart rate variability"
        case .restingHeartRate: return "Resting heart rate"
        case .steps: return "Steps"
        case .zonesLow: return "HR zones 1–3 (weekly)"
        case .zonesHigh: return "HR zones 4–5 (weekly)"
        case .vo2: return "VO₂ max"
        case .calories: return "Calories"
        case .stress: return "Stress monitor"
        }
    }
    func value(in day: DailySnapshot) -> String {
        switch self {
        case .hrv: return decimalText(day.hrv, places: 0)
        case .restingHeartRate: return decimalText(day.restingHeartRate, places: 0)
        case .steps: return day.steps > 0 ? day.steps.formatted() : "—"
        case .calories: return day.energyKcal > 0 ? Int(day.energyKcal).formatted() : "—"
        case .zonesLow, .zonesHigh, .vo2, .stress: return "—"
        }
    }
}

struct ReferenceDashboard: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("whoop.dashboard.visibleRows") private var mask = 255
    @State private var customizing = false
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("My Dashboard").font(WFont.number(21, bold: true))
                Spacer()
                Button { customizing = true } label: {
                    Text("CUSTOMIZE ✦").font(WFont.label(8)).tracking(0.6).foregroundStyle(.black)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color(red: 0.85, green: 0.66, blue: 0.80), in: Capsule())
                }
            }
            ForEach(DashboardItem.allCases.filter { mask & $0.bit != 0 }) { item in
                WCard(padding: 12) {
                    ReferenceMetricRow(title: item.title, value: item.value(in: store.selectedDay),
                                       previous: precedingDay(in: store).map { item.value(in: $0) }, compact: true)
                }
            }
            if mask == 0 {
                Button("CHOOSE YOUR METRICS") { customizing = true }.buttonStyle(WButton(filled: false))
            }
        }
        .sheet(isPresented: $customizing) {
            SheetScaffold(title: "MY DASHBOARD") {
                VStack(spacing: 14) {
                    Text("Choose the measurements you want to see. Unavailable measurements stay blank.")
                        .font(WFont.body(15)).foregroundStyle(WColor.muted)
                    WCard {
                        ForEach(DashboardItem.allCases) { item in
                            Toggle(item.title, isOn: Binding(get: { mask & item.bit != 0 }, set: { enabled in
                                if enabled { mask |= item.bit } else { mask &= ~item.bit }
                            })).font(WFont.body(15)).padding(.vertical, 8)
                        }
                    }.tint(WColor.green)
                }
            }.preferredColorScheme(.dark)
        }
    }
}

struct DetailInsight: View {
    let text: String
    var actionTitle = "ABOUT THIS SCORE"
    let action: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text).font(WFont.body(16)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            Button(action: action) {
                HStack(spacing: 7) {
                    Text(actionTitle).font(WFont.label(10)).tracking(0.7)
                    Image(systemName: "arrow.right").font(.system(size: 18, weight: .light))
                }.foregroundStyle(WColor.purple)
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(WColor.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(LinearGradient(colors: [WColor.purple.opacity(0.7), WColor.blue.opacity(0.7)], startPoint: .leading, endPoint: .trailing), lineWidth: 1))
    }
}

struct HealthAgeCard: View {
    var body: some View {
        WCard {
            VStack(spacing: 9) {
                Text("HEALTH").font(WFont.label(10)).tracking(1.4)
                ZStack {
                    Circle().fill(RadialGradient(colors: [Color.clear, Color.teal.opacity(0.10), Color.teal.opacity(0.70), Color.clear], center: .center, startRadius: 18, endRadius: 108))
                    Circle().stroke(Color.teal.opacity(0.35), lineWidth: 0.7).padding(13)
                    Canvas { context, size in
                        for index in 0..<90 {
                            let angle = Double(index) * 2.399963
                            let radius = Double(65 + (index * 19) % 34)
                            let point = CGPoint(x: Double(size.width) / 2 + cos(angle) * radius,
                                                y: Double(size.height) / 2 + sin(angle) * radius)
                            let diameter = CGFloat(index % 3 == 0 ? 2.5 : 1)
                            context.fill(Path(ellipseIn: CGRect(x: point.x, y: point.y, width: diameter, height: diameter)), with: .color(.mint.opacity(index % 4 == 0 ? 0.9 : 0.4)))
                        }
                    }
                    VStack(spacing: 4) {
                        Text("—").font(WFont.number(48, bold: true))
                        Text("WHOOP AGE").font(WFont.label(11)).tracking(0.8)
                        Text("Not available").font(WFont.body(12)).foregroundStyle(WColor.muted)
                    }
                }.frame(width: 220, height: 220)
                Text("An age score is not included in your current data.")
                    .font(WFont.body(12)).foregroundStyle(WColor.muted).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity).padding(.vertical, 6)
        }.accessibilityElement(children: .combine)
    }
}

struct StressMonitorView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        SheetScaffold(title: "STRESS MONITOR") {
            VStack(spacing: 24) {
                Text("TODAY").font(WFont.label(10)).tracking(1.2)
                ZStack {
                    Circle().trim(from: 0, to: 0.75)
                        .stroke(AngularGradient(colors: [WColor.sleep, Color.teal, WColor.yellow], center: .center, startAngle: .degrees(135), endAngle: .degrees(405)), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(135))
                    VStack(spacing: 8) {
                        Text("—").font(WFont.number(57, bold: true))
                        Text("NO STRESS DATA").font(WFont.label(10)).tracking(0.8).foregroundStyle(WColor.muted)
                    }
                }.frame(width: 224, height: 224)
                Text("A stress score is not supplied by your current data. Heart-rate samples alone are not a WHOOP stress measurement.")
                    .font(WFont.body(15)).foregroundStyle(WColor.muted).multilineTextAlignment(.center)
                if !store.selectedDay.heartRates.isEmpty {
                    SectionHeading(title: "Heart rate", subtitle: "Your recorded heart rate, not a stress score")
                    WCard { HeartRateChart(samples: store.selectedDay.heartRates).frame(height: 180) }
                }
            }
        }
    }
}
