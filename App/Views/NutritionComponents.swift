import SwiftUI
import Charts
import WHOOPCore

enum NColor {
    static let background = Color(red: 11/255, green: 13/255, blue: 16/255)
    static let card = Color(red: 20/255, green: 24/255, blue: 29/255)
    static let cyan = Color(red: 0.18, green: 0.82, blue: 0.94)
    static let green = Color(red: 0.42, green: 0.90, blue: 0.49)
    static let yellow = Color(red: 0.98, green: 0.79, blue: 0.32)
    static let red = Color(red: 0.99, green: 0.37, blue: 0.37)
    static let muted = Color(red: 0.57, green: 0.62, blue: 0.68)
    static func status(_ value: String, fallback: Color = cyan) -> Color {
        switch value { case "target": return green; case "close": return yellow; case "over": return red; default: return fallback }
    }
}
enum NFont {
    static func body(_ size: CGFloat = 15) -> Font { .custom("Inter-Regular", size: size, relativeTo: .body) }
    static func number(_ size: CGFloat = 26) -> Font { body(size).weight(.bold) }
    static func label(_ size: CGFloat = 10) -> Font { body(size).weight(.semibold) }
}
func nText(_ value: Double?, digits: Int = 0) -> String {
    guard let value, value.isFinite else { return "—" }
    return value.formatted(.number.precision(.fractionLength(digits)))
}
struct NCard<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View { WCard(padding: 16, surface: NColor.card, cornerRadius: 16) { content } }
}
struct NNote: View {
    var body: some View { Text("Estimates may be inaccurate. Not medical advice.").font(NFont.body(11)).foregroundStyle(NColor.muted).multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 8) }
}
struct NHeading: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(NFont.number(24))
            if let subtitle { Text(subtitle).font(NFont.body(13)).foregroundStyle(NColor.muted) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct NButton: ButtonStyle {
    var secondary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(NFont.label(12)).frame(maxWidth: .infinity, minHeight: 46)
            .foregroundStyle(secondary ? Color.white : NColor.background)
            .background(secondary ? NColor.card : NColor.cyan, in: RoundedRectangle(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}
struct NEmpty: View {
    let title: String
    let detail: String
    var symbol = "fork.knife"
    var body: some View {
        NCard {
            VStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 26, weight: .light)).foregroundStyle(NColor.cyan)
                Text(title).font(NFont.number(18))
                Text(detail).font(NFont.body(13)).foregroundStyle(NColor.muted).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity).padding(.vertical, 18)
        }
    }
}
struct NError: View {
    let message: String
    var body: some View { NCard { Label(message, systemImage: "exclamationmark.circle").font(NFont.body(13)).foregroundStyle(NColor.yellow).fixedSize(horizontal: false, vertical: true) }.accessibilityLabel("Nutrition error. " + message) }
}
struct NSkeleton: View {
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) { ForEach(0..<3) { _ in Circle().stroke(Color.white.opacity(0.10), lineWidth: 9).frame(height: 94) } }
            ForEach(0..<3) { _ in RoundedRectangle(cornerRadius: 16).fill(NColor.card).frame(height: 90) }
        }.redacted(reason: .placeholder).accessibilityLabel("Loading nutrition data")
    }
}
struct NLoadingCard: View {
    var body: some View {
        NCard {
            VStack(alignment: .leading, spacing: 12) {
                RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.08)).frame(width: 130, height: 14)
                RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.05)).frame(height: 12)
                RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.05)).frame(height: 12)
            }.padding(.vertical, 5)
        }.redacted(reason: .placeholder).accessibilityLabel("Loading nutrition result")
    }
}
struct NPage<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    private let content: Content
    init(title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) { content; NNote() }.padding(18).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }.background(NColor.background).scrollIndicators(.hidden)
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.font(NFont.label(12)).frame(minWidth: 44, minHeight: 44) } }
                .toolbarBackground(NColor.background, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
        }.font(NFont.body()).tint(NColor.cyan).preferredColorScheme(.dark)
    }
}
struct NDial: View {
    let title: String
    let unit: String
    let dial: NutritionCalculation.Dial
    let tint: Color
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fill = 0.0
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.08), lineWidth: 9)
                    Circle().trim(from: 0, to: fill).stroke(tint, style: StrokeStyle(lineWidth: 9, lineCap: .round)).rotationEffect(.degrees(-90))
                    VStack(spacing: 3) {
                        Text(nText(dial.value)).font(NFont.number(23)).minimumScaleFactor(0.45).lineLimit(1)
                            .contentTransition(.numericText()).animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: dial.value)
                        Text(unit).font(NFont.label(8)).foregroundStyle(NColor.muted)
                    }.padding(10)
                }.aspectRatio(1, contentMode: .fit)
                Text(title.uppercased()).font(NFont.label(9)).tracking(0.7).foregroundStyle(NColor.muted).lineLimit(1).minimumScaleFactor(0.65)
                Text(dial.status == "over" ? "OVER TARGET" : dial.status == "target" ? "ON TARGET" : dial.status == "close" ? "CLOSE" : "LOGGING")
                    .font(NFont.label(7)).tracking(0.4).foregroundStyle(NColor.status(dial.status, fallback: NColor.muted))
            }.frame(maxWidth: .infinity, minHeight: 130)
        }.buttonStyle(.plain).accessibilityLabel("\(title), \(nText(dial.value)) \(unit), \(dial.status). Open breakdown.")
            .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.8)) { fill = dial.fraction } }
            .onChange(of: dial.fraction) { _, value in withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.5)) { fill = value } }
    }
}
struct NStat: View {
    let label: String
    let value: Double?
    var unit = "kcal"
    var digits = 0
    var body: some View {
        NCard {
            VStack(alignment: .leading, spacing: 9) {
                Text(label.uppercased()).font(NFont.label(9)).tracking(0.8).foregroundStyle(NColor.muted)
                Text(nText(value, digits: digits)).font(NFont.number(25)).minimumScaleFactor(0.6).lineLimit(1)
                Text(unit).font(NFont.body(11)).foregroundStyle(NColor.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
struct NMacroBar: View {
    let title: String
    let dial: NutritionCalculation.Dial
    let color: Color
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(title).font(NFont.label(12))
                Spacer()
                Text("\(nText(dial.value)) / \(nText(dial.target)) g").font(NFont.body(12)).foregroundStyle(NColor.muted)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.06))
                    Capsule().fill(color).frame(width: geometry.size.width * dial.fraction)
                }
            }.frame(height: 6)
        }.accessibilityElement(children: .ignore).accessibilityLabel("\(title), \(nText(dial.value)) of \(nText(dial.target)) grams")
    }
}
enum NutritionChartKind: Equatable { case calories, deficit, protein }
struct NDayChart: View {
    let points: [NutritionCalculation.DayPoint]
    let kind: NutritionChartKind
    var goal: Double? = nil
    private func value(_ point: NutritionCalculation.DayPoint) -> Double? {
        switch kind { case .calories: return point.eaten; case .deficit: return point.balance; case .protein: return point.protein }
    }
    private var label: String { kind == .protein ? "Protein (grams)" : kind == .deficit ? "Completed-day energy balance (kcal)" : "Logged intake (kcal)" }
    var body: some View {
        if !points.contains(where: { value($0) != nil }) {
            NEmpty(title: "No trend yet", detail: kind == .deficit ? "Mark fully logged days complete to include their estimated balance." : "Log food on a day to start this chart.", symbol: "chart.xyaxis.line")
        } else {
            NCard {
                Chart {
                    ForEach(points) { point in
                        if let number = value(point), let date = NutritionDay.date(point.day) {
                            BarMark(x: .value("Day", date, unit: .day), y: .value(label, number))
                                .foregroundStyle(kind == .deficit && number < 0 ? NColor.red : NColor.cyan).cornerRadius(3)
                        }
                    }
                    if let goal { RuleMark(y: .value("Current goal", goal)).foregroundStyle(NColor.yellow).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4])) }
                    if kind == .deficit { RuleMark(y: .value("Balance", 0)).foregroundStyle(NColor.muted.opacity(0.5)) }
                }.frame(height: 190)
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { _ in AxisValueLabel(format: utcDateFormat(.dateTime.month(.abbreviated).day())).foregroundStyle(NColor.muted) } }
                    .chartYAxis { AxisMarks(position: .trailing) { _ in AxisGridLine().foregroundStyle(Color.white.opacity(0.06)); AxisValueLabel().foregroundStyle(NColor.muted) } }
                    .accessibilityElement(children: .ignore).accessibilityLabel("\(label) across \(points.count) days. Missing dates have no bar.")
            }
        }
    }
}
struct NNumberField: View {
    let title: String
    @Binding var value: Double
    var body: some View {
        HStack {
            Text(title).font(NFont.body(13))
            Spacer()
            TextField(title, value: $value, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                .font(NFont.body(15)).frame(maxWidth: 120, minHeight: 44).accessibilityLabel(title)
        }
    }
}
