import SwiftUI

struct PulseReferenceMonitor: View {
    let title: String
    let badge: String
    let value: String
    let detail: String
    let tint: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            PulseCard {
                VStack(alignment: .leading, spacing: 15) {
                    HStack {
                        Text(title).font(PulseFont.label(11)).tracking(0.8)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .light)).foregroundStyle(PulseColor.muted)
                    }
                    HStack(spacing: 7) {
                        Text(badge).font(PulseFont.number(13)).foregroundStyle(tint).frame(width: 23, height: 23).background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 4))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(value).font(PulseFont.label(11)).tracking(0.8).foregroundStyle(tint)
                            Text(detail).font(PulseFont.body(10.5)).foregroundStyle(PulseColor.muted)
                        }
                    }
                }.frame(height: 57, alignment: .center)
            }
        }.buttonStyle(PulsePressStyle()).accessibilityElement(children: .combine)
    }
}
struct PulseReferenceActivityRow: View {
    let activity: PulseHomeActivity
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                Image(systemName: activity.symbol).font(.system(size: activity.isSleep ? 18 : 20, weight: .light))
                Text(activity.metric).font(PulseFont.number(17)).monospacedDigit()
            }.frame(width: 86, height: 36).background(activity.isSleep ? PulseColor.sleep : PulseColor.load, in: RoundedRectangle(cornerRadius: 7))
            Text(activity.title).font(PulseFont.label(10.5)).tracking(1)
            Spacer(minLength: 1)
            VStack(alignment: .trailing, spacing: 4) {
                Text(activity.start); Text(activity.end)
            }.font(PulseFont.compact(10)).foregroundStyle(PulseColor.muted)
            Rectangle().fill(activity.isSleep ? PulseColor.sleep : PulseColor.load).frame(width: 1.5, height: 25).overlay(alignment: .top) { Circle().fill(.white).frame(width: 2, height: 2) }.overlay(alignment: .bottom) { Circle().fill(.white).frame(width: 2, height: 2) }
        }.padding(7).frame(minHeight: 51).background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .combine)
    }
}
struct PulseReferenceMetric: View {
    let metric: PulseHomeStatistic
    private var tint: Color { metric.tone == "good" ? PulseColor.mint : metric.tone == "caution" ? PulseColor.yellow : PulseColor.muted }
    var body: some View {
        PulseCard(padding: 10) {
            HStack(spacing: 9) {
                Image(systemName: metric.symbol).font(.system(size: 19, weight: .light)).foregroundStyle(PulseColor.muted).frame(width: 18)
                Text(metric.title).font(PulseFont.label(10)).tracking(0.7)
                Spacer(minLength: 2)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(metric.value).font(PulseFont.number(20)).monospacedDigit()
                    Text(metric.baseline).font(PulseFont.compact(10)).foregroundStyle(PulseColor.muted)
                }
                Image(systemName: metric.direction < 0 ? "arrowtriangle.down.fill" : "arrowtriangle.up.fill").font(.system(size: 6)).foregroundStyle(tint)
            }.frame(minHeight: 27)
        }.accessibilityElement(children: .combine)
    }
}
struct PulsePlanArtwork: View {
    var body: some View {
        ZStack {
            orb("moon.stars.fill", size: 43).offset(x: 10, y: -21)
            orb("heart.fill", size: 28).offset(x: -26, y: -2)
            orb("figure.strengthtraining.traditional", size: 33).offset(x: -8, y: 26)
            orb("shoeprints.fill", size: 25).offset(x: 29, y: 29)
        }.frame(width: 85, height: 98)
    }
    private func orb(_ symbol: String, size: CGFloat) -> some View {
        ZStack {
            Circle().stroke(.white.opacity(0.08), lineWidth: 2)
            Circle().trim(from: 0.12, to: 0.9).stroke(PulseColor.mint, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, dash: [13, 4])).rotationEffect(.degrees(-90))
            Image(systemName: symbol).font(.system(size: size * 0.40, weight: .light)).foregroundStyle(PulseColor.muted)
        }.frame(width: size, height: size)
    }
}
struct PulseDiscoverCard: View {
    let title: String
    let detail: String
    let cta: String
    let symbol: String
    let tone: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            PulseCard(padding: 18) {
                HStack(alignment: .center, spacing: 18) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9).fill(LinearGradient(colors: [tone.opacity(0.6), Color.black], startPoint: .topLeading, endPoint: .bottomTrailing))
                        Image(systemName: symbol).font(.system(size: 29, weight: .light)).foregroundStyle(tone)
                    }.frame(width: 66, height: 66)
                    VStack(alignment: .leading, spacing: 9) {
                        Text(title).font(PulseFont.body(13.5).weight(.semibold))
                        Text(detail).font(PulseFont.body(12)).foregroundStyle(PulseColor.muted).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) { Text(cta).font(PulseFont.label(10)).tracking(1); Image(systemName: "arrow.right").font(.system(size: 18, weight: .light)) }.foregroundStyle(PulseColor.sleep)
                    }
                }.frame(minHeight: 78)
            }
        }.buttonStyle(PulsePressStyle())
    }
}
struct PulseQuickMenu: View {
    let action: (PulseHomePanel) -> Void
    var body: some View {
        VStack(spacing: 0) {
            row("CREATE WHOOP LIVE", "camera", .live)
            row("COMPLETE YOUR JOURNAL", "square.and.pencil", .journal)
            row("STRENGTH TRAINER", "figure.strengthtraining.traditional", .strength)
            row("ADD ACTIVITY", "plus", .activity)
            row("START ACTIVITY", "stopwatch", .session)
        }.padding(.horizontal, 20).padding(.vertical, 8).frame(width: 255)
            .background(LinearGradient(colors: [Color(red: 0.16, green: 0.17, blue: 0.28), Color(red: 0.14, green: 0.16, blue: 0.21)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 19))
            .overlay(RoundedRectangle(cornerRadius: 19).stroke(.white.opacity(0.07), lineWidth: 0.6))
    }
    private func row(_ title: String, _ symbol: String, _ panel: PulseHomePanel) -> some View {
        Button { action(panel) } label: {
            HStack(spacing: 13) {
                Image(systemName: symbol).font(.system(size: 20, weight: .light)).foregroundStyle(PulseColor.muted).frame(width: 20)
                Text(title).font(PulseFont.label(10)).tracking(0.9)
                Spacer(minLength: 0)
            }.frame(height: 51).contentShape(Rectangle())
        }.buttonStyle(PulsePressStyle())
    }
}
