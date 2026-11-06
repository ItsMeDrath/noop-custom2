import WidgetKit
import SwiftUI
import ActivityKit
import StrandDesign

/// WHOOP-inspired live heart-rate surface for the Lock Screen and Dynamic Island.
/// Values remain sourced from NOOP's real ActivityKit session state.
struct NOOPLiveActivity: Widget {
    private static let canvas = Color(hex: "#121518")
    private static let card = Color(hex: "#25292C")
    private static let muted = Color(hex: "#9AA4AC")
    private static let blue = Color(hex: "#4090E0")
    private static let green = Color(hex: "#03E095")
    private static let red = Color(hex: "#E0463C")

    static func shownBpm(_ context: ActivityViewContext<NOOPActivityAttributes>) -> Int? {
        context.isStale ? nil : context.state.bpm
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NOOPActivityAttributes.self) { context in
            lockScreen(context)
                .activityBackgroundTint(Self.canvas)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("LIVE HEART RATE")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .tracking(1.1)
                            .foregroundStyle(Self.muted)
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(Self.shownBpm(context).map(String.init) ?? "–")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                            Text("BPM")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Self.muted)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 8) {
                        islandStat("RECOVERY", context.state.recovery.map { "\($0)%" }, tint: Self.green)
                        islandStat("STRAIN", context.state.effort.map(String.init), tint: Self.blue)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 6) {
                        Circle().fill(context.isStale ? Self.muted : Self.red).frame(width: 6, height: 6)
                        Text(context.attributes.title.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(Self.muted)
                        Spacer()
                        Text(context.isStale ? "WAITING FOR DATA" : "LIVE")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(context.isStale ? Self.muted : Self.green)
                    }
                }
            } compactLeading: {
                Image(systemName: "heart.fill").foregroundStyle(Self.red)
            } compactTrailing: {
                Text(Self.shownBpm(context).map(String.init) ?? "–")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            } minimal: {
                Image(systemName: "heart.fill").foregroundStyle(Self.red)
            }
            .keylineTint(Self.blue)
        }
    }

    private func lockScreen(_ context: ActivityViewContext<NOOPActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                Circle()
                    .fill(context.isStale ? Self.muted : Self.red)
                    .frame(width: 7, height: 7)
                Text("LIVE HEART RATE")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(.white)
                Spacer()
                Text(context.isStale ? "NO SIGNAL" : "LIVE")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.9)
                    .foregroundStyle(context.isStale ? Self.muted : Self.green)
            }

            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Self.red)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(Self.shownBpm(context).map(String.init) ?? "–")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text("BPM")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Self.muted)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(context.attributes.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Self.muted)
                    Text("WHOOP STYLE · NOOP")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(Self.muted.opacity(0.8))
                }
            }

            Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)

            HStack(spacing: 0) {
                bannerStat(label: "RECOVERY", value: context.state.recovery.map { "\($0)%" }, tint: Self.green)
                Spacer()
                bannerStat(label: "STRAIN", value: context.state.effort.map(String.init), tint: Self.blue)
                Spacer()
                bannerStat(label: "SENSOR", value: context.state.bonded ? "CONNECTED" : "OFFLINE",
                           tint: context.state.bonded ? Self.green : Self.muted)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Self.canvas)
    }

    @ViewBuilder
    private func bannerStat(label: String, value: String?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Self.muted)
            Text(value ?? "—")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
    }

    @ViewBuilder
    private func islandStat(_ label: String, _ value: String?, tint: Color) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(Self.muted)
            Text(value ?? "—")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
    }
}
