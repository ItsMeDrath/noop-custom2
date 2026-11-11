import SwiftUI

/// Provisional values are documented, with their provenance, in design/tokens/home.json.
enum PulseColor {
    static func recoveryScore(_ value: Double?) -> Color {
        guard let value else { return muted }
        return value <= 33 ? Color(pulseHex: 0xFF002E) : value <= 66 ? recoveryYellow : readiness
    }
    static let background = Color(pulseHex: 0x101517)
    static let top = Color(pulseHex: 0x263239)
    static let card = Color(pulseHex: 0x2B3135)
    static let elevated = Color(pulseHex: 0x41484C)
    static let text = Color(pulseHex: 0xF4F6F7)
    static let muted = Color(pulseHex: 0x9FA9AF)
    static let sleep = Color(pulseHex: 0x7CA5BB)
    static let readiness = Color(pulseHex: 0x13DF31)
    static let load = Color(pulseHex: 0x009FE7)
    static let mint = Color(pulseHex: 0x00DCA4)
    static let recoveryYellow = Color(pulseHex: 0xFFE000)
    static let yellow = Color(pulseHex: 0xFFAA15)
}
private extension Color {
    init(pulseHex: UInt32) {
        self.init(red: Double((pulseHex >> 16) & 255) / 255,
                  green: Double((pulseHex >> 8) & 255) / 255, blue: Double(pulseHex & 255) / 255)
    }
}
enum PulseFont {
    static func body(_ size: CGFloat = 13) -> Font { .custom("ProximaNova-Regular", size: size, relativeTo: .body) }
    static func label(_ size: CGFloat = 9) -> Font { .custom("DINPro-Bold", size: size, relativeTo: .caption) }
    static func number(_ size: CGFloat = 31) -> Font { .custom("DINPro-Bold", size: size, relativeTo: .title) }
    static func compact(_ size: CGFloat) -> Font { .custom("DINPro-Medium", size: size, relativeTo: .body) }
    static let section = body(20).weight(.semibold)
}
struct PulseCard<Content: View>: View {
    private let content: Content
    var padding: CGFloat
    init(padding: CGFloat = 14, @ViewBuilder content: () -> Content) {
        self.padding = padding; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(PulseColor.card.opacity(0.92), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(.white.opacity(0.015), lineWidth: 0.3))
    }
}
struct PulseRing: View {
    let value: String
    let fraction: Double
    let previous: Double?
    let tint: Color
    let label: String
    var action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress = 0.0
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    Circle().inset(by: 3).stroke(.white.opacity(0.10), lineWidth: 5.8)
                    Circle().inset(by: 3).trim(from: 0, to: progress)
                        .stroke(tint, style: StrokeStyle(lineWidth: 5.8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    if let previous {
                        Circle().inset(by: 3).trim(from: max(0, previous - 0.002), to: min(1, previous + 0.002))
                            .stroke(.white.opacity(0.75), lineWidth: 5.8).rotationEffect(.degrees(-90))
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(value.hasSuffix("%") ? String(value.dropLast()) : value).font(PulseFont.number(26))
                            .contentTransition(.numericText(value: Double(value.replacingOccurrences(of: "%", with: "")) ?? 0))
                        if value.hasSuffix("%") { Text("%").font(PulseFont.number(17)) }
                    }.tracking(-0.8).monospacedDigit().minimumScaleFactor(0.7).padding(9)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.7), value: value)
                }.aspectRatio(1, contentMode: .fit).frame(maxWidth: 81)
                HStack(spacing: 3) {
                    Text(label).font(PulseFont.label(10)).tracking(0.8)
                    Image(systemName: "chevron.right").font(.system(size: 6, weight: .bold))
                }
            }.frame(maxWidth: .infinity).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(PulseColor.text)
            .accessibilityLabel("\(label), \(value). View today's context")
            .onAppear { animate() }.onChange(of: fraction) { _, _ in animate() }
    }
    private func animate() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.7)) { progress = min(1, max(0, fraction)) }
    }
}
struct PulseDayStrip: View {
    @Binding var index: Int
    let days: [PulseHomeDay]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            Capsule().fill(.white.opacity(0.045)).frame(width: 126, height: 28)
            Capsule().fill(.white.opacity(0.09)).frame(width: 75, height: 28)
            Button { select(index - 1) } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44).contentShape(Rectangle())
            }.offset(x: -45).disabled(index == 0).opacity(index == 0 ? 0.3 : 1)
                .accessibilityLabel("Previous sample day")
            Menu {
                ForEach(Array(days.enumerated()), id: \.element.id) { item in
                    Button(item.element.date == "TODAY" ? "NOVEMBER 9" : item.element.date) { select(item.offset) }
                }
            } label: {
                Text(days[index].date).font(PulseFont.label(10.5)).tracking(0.9)
                    .fixedSize().frame(width: 44, height: 44).contentShape(Rectangle())
            }.accessibilityLabel("Select sample day, \(days[index].date)")
            Button { select(index + 1) } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44).contentShape(Rectangle())
            }.offset(x: 45).disabled(index == days.count - 1).opacity(index == days.count - 1 ? 0.3 : 1)
                .accessibilityLabel("Next sample day")
        }.font(.system(size: 11, weight: .bold)).frame(width: 126, height: 44)
            .buttonStyle(PulsePressStyle()).foregroundStyle(PulseColor.text)
    }
    private func select(_ proposed: Int) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) { index = min(days.count - 1, max(0, proposed)) }
    }
}
struct PulseTabBar: View {
    var coachAction: () -> Void = { }
    var moreAction: () -> Void = { }
    private let tabs = [("house", "Home"), ("heart", "Health"), ("person.3", "Community"), ("line.3.horizontal", "More")]
    var body: some View {
        HStack(spacing: 11) {
            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { item in
                    Button { if item.offset == 3 { moreAction() } } label: {
                        VStack(spacing: 5) {
                            Group {
                                if item.offset == 0 {
                                    PulseHomeTabShape().stroke(style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round)).frame(width: 22, height: 22)
                                } else {
                                    Image(systemName: item.element.0).font(.system(size: 21, weight: .light))
                                        .overlay { if item.offset == 1 { Image(systemName: "waveform.path.ecg").font(.system(size: 9, weight: .light)) } }
                                }
                            }.frame(height: 22)
                            Text(item.element.1).font(PulseFont.body(8.5).weight(item.offset == 0 ? .semibold : .regular))
                        }.frame(maxWidth: .infinity, minHeight: 58).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(item.offset != 0 && item.offset != 3)
                        .foregroundStyle(item.offset == 0 ? PulseColor.text : PulseColor.muted)
                        .accessibilityLabel(item.element.1).accessibilityAddTraits(item.offset == 0 ? .isSelected : [])
                }
            }.padding(.horizontal, 8).background(PulseColor.top.opacity(0.88), in: Capsule())
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.10), lineWidth: 0.7))
            Button(action: coachAction) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22).fill(LinearGradient(colors: [Color(pulseHex: 0x2D2946), PulseColor.top], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Circle().stroke(LinearGradient(colors: [.purple, PulseColor.load], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.1).frame(width: 29, height: 29)
                    WhoopMonogram().frame(width: 18, height: 15)
                }.frame(width: 58, height: 58).overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.08), lineWidth: 0.7))
            }.buttonStyle(.plain).accessibilityLabel("Open WHOOP Coach sample conversation")
        }
    }
}
struct PulseIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 22, weight: .light)).frame(width: 44, height: 44) }
            .buttonStyle(.plain).accessibilityLabel(label)
    }
}
struct PulseMonitor: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            PulseCard(padding: 10) {
                HStack(spacing: 7) {
                    Image(systemName: symbol).font(.system(size: 17, weight: .light)).foregroundStyle(tint)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title).font(PulseFont.label(8)).tracking(0.6)
                        HStack(spacing: 4) { Circle().fill(tint).frame(width: 4, height: 4); Text(subtitle).font(PulseFont.label(7)).foregroundStyle(tint) }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(PulseColor.muted)
                }.frame(minHeight: 38)
            }
        }.buttonStyle(.plain).accessibilityElement(children: .combine)
    }
}
struct PulseMetricLine: View {
    let metric: PulseHomeStatistic
    var body: some View {
        PulseCard(padding: 11) {
            HStack {
                Text(metric.title.uppercased()).font(PulseFont.label(8)).tracking(0.6)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(metric.value).font(PulseFont.number(23)).monospacedDigit()
                        Text(metric.unit).font(PulseFont.body(8)).foregroundStyle(PulseColor.muted)
                    }
                    Text(metric.baseline).font(PulseFont.body(8)).foregroundStyle(PulseColor.muted)
                }
                Image(systemName: metric.direction > 0 ? "arrowtriangle.up.fill" : metric.direction < 0 ? "arrowtriangle.down.fill" : "circle.fill")
                    .font(.system(size: 5)).foregroundStyle(PulseColor.muted).frame(width: 8)
            }.frame(minHeight: 34)
        }.accessibilityElement(children: .combine)
    }
}
struct PulseSparkline: View {
    let values: [Double]
    var body: some View {
        GeometryReader { geometry in
            let minimum = (values.min() ?? 0) - 5
            let spread = max(1, (values.max() ?? 1) - minimum + 5)
            Path { path in
                for (index, value) in values.enumerated() {
                    let point = CGPoint(x: CGFloat(index) / CGFloat(max(1, values.count - 1)) * geometry.size.width,
                                        y: geometry.size.height * CGFloat(1 - (value - minimum) / spread))
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }.stroke(PulseColor.load, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }.accessibilityLabel("Illustrative daily pulse trace, in beats per minute")
    }
}

struct PulsePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// House outline with the rising activity line used by the supplied Home reference.
struct PulseHomeTabShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        return Path { path in
            path.move(to: CGPoint(x: 2, y: 12)); path.addLine(to: CGPoint(x: 12, y: 2)); path.addLine(to: CGPoint(x: 22, y: 12))
            path.move(to: CGPoint(x: 5, y: 10)); path.addLine(to: CGPoint(x: 5, y: 22)); path.addLine(to: CGPoint(x: 19, y: 22)); path.addLine(to: CGPoint(x: 19, y: 10))
            path.move(to: CGPoint(x: 8, y: 17)); path.addLine(to: CGPoint(x: 11, y: 14)); path.addLine(to: CGPoint(x: 14, y: 16)); path.addLine(to: CGPoint(x: 17, y: 12))
        }.applying(CGAffineTransform(scaleX: scale, y: scale))
    }
}
