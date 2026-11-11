import SwiftUI
import WHOOPCore

// Palette and geometry follow the user's supplied visual references.
enum WColor {
    static let background = Color(red: 0.065, green: 0.080, blue: 0.089)
    static let backgroundTop = Color(red: 0.149, green: 0.192, blue: 0.212)
    static let card = Color(red: 0.137, green: 0.169, blue: 0.188)
    static let elevated = Color(red: 0.192, green: 0.231, blue: 0.251)
    static let muted = Color(red: 0.60, green: 0.64, blue: 0.67)
    static let line = Color.white.opacity(0.085)
    static let green = Color(red: 0.12, green: 0.88, blue: 0.0)
    static let blue = Color(red: 0.0, green: 0.62, blue: 0.91)
    static let sleep = Color(red: 0.51, green: 0.68, blue: 0.75)
    static let purple = Color(red: 0.62, green: 0.53, blue: 0.98)
    static let yellow = Color(red: 0.94, green: 0.78, blue: 0.26)
}

enum WFont {
    static func body(_ size: CGFloat = 16) -> Font { .custom("ProximaNova-Regular", size: size, relativeTo: .body) }
    static func number(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "DINPro-Bold" : "DINPro-Medium", size: size, relativeTo: .title)
    }
    static func label(_ size: CGFloat = 12) -> Font { .custom("DINPro-Bold", size: size, relativeTo: .caption).weight(.bold) }
}

struct WCard<Content: View>: View {
    private let content: Content
    private let padding: CGFloat
    private let surface: Color?
    private let radius: CGFloat
    init(padding: CGFloat = 14, surface: Color? = nil, cornerRadius: CGFloat = 10, @ViewBuilder content: () -> Content) {
        self.padding = padding; self.surface = surface; self.radius = cornerRadius; self.content = content()
    }
    var body: some View {
        content.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [surface ?? WColor.card, surface ?? WColor.card.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(WColor.line, lineWidth: 0.7))
    }
}

struct SectionHeading: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased()).font(WFont.label(14)).tracking(1.1).foregroundStyle(.white)
            if let subtitle { Text(subtitle).font(WFont.body(14)).foregroundStyle(WColor.muted) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SourceBadge: View {
    let source: DataSource
    var isEmpty = false
    private var label: String { isEmpty ? "NO DAY DATA" : (source == .example ? "EXAMPLE DAY" : "IMPORTED DATA") }
    private var symbol: String { isEmpty ? "calendar.badge.exclamationmark" : (source == .example ? "sparkles" : "arrow.down.doc") }
    private var color: Color { isEmpty ? WColor.muted : (source == .example ? WColor.yellow : WColor.blue) }
    var body: some View {
        Label(label, systemImage: symbol)
            .font(WFont.label(10)).tracking(0.8).foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(color.opacity(0.09), in: Capsule())
            .accessibilityLabel(isEmpty ? "No saved measurements for this day" : (source == .example ? "Example data, not your measurements" : "Imported measurements"))
    }
}

struct EmptyCard: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        WCard {
            VStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 28, weight: .light)).foregroundStyle(WColor.muted)
                Text(title).font(WFont.number(22, bold: true)).foregroundStyle(.white)
                Text(detail).font(WFont.body(15)).foregroundStyle(WColor.muted).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity).padding(.vertical, 18)
        }
    }
}

struct WButton: ButtonStyle {
    var filled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(WFont.label(13)).tracking(0.9)
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .foregroundStyle(filled ? Color.black : Color.white)
            .background(filled ? Color.white : WColor.elevated, in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

func durationText(_ minutes: Int) -> String {
    let value = max(0, minutes)
    return "\(value / 60)h \(value % 60)m"
}

func decimalText(_ value: Double?, places: Int = 1) -> String {
    guard let value, value.isFinite else { return "—" }
    return value.formatted(.number.precision(.fractionLength(places)))
}

enum ScoreMetric: String, CaseIterable, Identifiable {
    case sleep, recovery, strain
    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
    var color: Color {
        switch self { case .sleep: return WColor.sleep; case .recovery: return WColor.green; case .strain: return WColor.blue }
    }
    var symbol: String {
        switch self { case .sleep: return "moon.fill"; case .recovery: return "heart.fill"; case .strain: return "waveform.path.ecg" }
    }
    func value(_ day: DailySnapshot) -> Double? {
        switch self {
        case .sleep: return day.sleepPerformance.map(Double.init)
        case .recovery: return day.recovery.map(Double.init)
        case .strain: return day.strain
        }
    }
    func text(_ day: DailySnapshot) -> String {
        guard let value = value(day) else { return "—" }
        return self == .strain ? decimalText(value) : "\(Int(value))%"
    }
    func fraction(_ day: DailySnapshot) -> Double {
        min(max((value(day) ?? 0) / (self == .strain ? 21 : 100), 0), 1)
    }
    var description: String {
        switch self {
        case .sleep: return "Sleep performance compares sleep achieved with sleep needed. This view displays the score supplied in your day data."
        case .recovery: return "Recovery brings your readiness into focus. This view displays the supplied score alongside resting heart rate and heart rate variability."
        case .strain: return "Strain is shown on a 0–21 scale. A recorded day score is distinct from the reference calculation available for imported heart-rate data."
        }
    }
}

struct ScoreRing: View {
    let metric: ScoreMetric
    let day: DailySnapshot
    var large = false
    var comparisonFraction: Double? = nil
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.10), lineWidth: large ? 16 : 5)
            Circle().trim(from: 0, to: metric.fraction(day))
                .stroke(metric == .recovery ? PulseColor.recoveryScore(day.recovery.map(Double.init)) : metric.color, style: StrokeStyle(lineWidth: large ? 16 : 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let fraction = comparisonFraction, (0...1).contains(fraction) {
                Circle().trim(from: max(0, fraction - 0.0025), to: min(1, fraction + 0.0025))
                    .stroke(Color.white.opacity(0.8), lineWidth: large ? 16 : 5)
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: large ? 8 : 0) {
                if large { WhoopWordmark().frame(width: 94, height: 17).opacity(0.46).padding(.bottom, 2) }
                if large {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(number).font(WFont.number(74, bold: true))
                        if metric != .strain && metric.value(day) != nil { Text("%").font(WFont.number(37, bold: true)) }
                    }.foregroundStyle(.white).minimumScaleFactor(0.55).lineLimit(1)
                    Text(metric == .sleep ? "SLEEP\nPERFORMANCE" : metric == .strain ? "DAY STRAIN" : "RECOVERY")
                        .font(WFont.label(12)).tracking(1.2).multilineTextAlignment(.center)
                } else {
                    Text(metric.value(day) == nil ? "NO DATA" : metric.text(day)).font(WFont.number(metric.value(day) == nil ? 12 : 25, bold: true))
                        .foregroundStyle(.white).minimumScaleFactor(0.6).lineLimit(1)
                }
            }.padding(10)
        }
        .frame(width: large ? 270 : nil, height: large ? 270 : nil)
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.title), \(metric.text(day))\(day.source == .example ? ", example data" : "")")
    }
    private var number: String {
        guard let value = metric.value(day) else { return "—" }
        return metric == .strain ? decimalText(value) : String(Int(value))
    }
}

struct WhoopBackground: View {
    var body: some View {
        LinearGradient(colors: [WColor.backgroundTop, WColor.background, WColor.background],
                       startPoint: .top, endPoint: .bottom).ignoresSafeArea()
    }
}

func utcDateFormat(_ style: Date.FormatStyle) -> Date.FormatStyle {
    var format = style
    format.calendar = DayCalendar.utc
    format.timeZone = TimeZone(secondsFromGMT: 0)!
    return format
}

func utcDateText(_ date: Date, style: Date.FormatStyle) -> String {
    date.formatted(utcDateFormat(style))
}

@MainActor
func selectedDayExists(in store: AppStore) -> Bool {
    store.days.contains { DayCalendar.utc.isDate($0.date, inSameDayAs: store.selectedDate) }
}
