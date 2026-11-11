import SwiftUI

enum ExperienceTier: String, CaseIterable, Identifiable {
    case one = "One", peak = "Peak", life = "Life"
    var id: String { rawValue }
}
struct ExperienceTierView: View {
    @AppStorage("local.experience.tier") private var selected = ExperienceTier.life.rawValue
    var body: some View {
        NPage(title: "Local edition") {
            NHeading(title: "Choose your local mode", subtitle: "All modes are free in this reconstruction")
            ForEach(ExperienceTier.allCases) { tier in
                Button { selected = tier.rawValue } label: {
                    NCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 7) {
                                Text(tier.rawValue).font(NFont.number(26))
                                Text(description(tier)).font(NFont.body(12)).foregroundStyle(NColor.muted)
                            }
                            Spacer()
                            Image(systemName: selected == tier.rawValue ? "checkmark.circle.fill" : "circle").font(.system(size: 25)).foregroundStyle(selected == tier.rawValue ? NColor.green : NColor.muted)
                        }.frame(minHeight: 78)
                    }
                }.buttonStyle(.plain).accessibilityLabel("Local \(tier.rawValue) mode, free").accessibilityAddTraits(selected == tier.rawValue ? .isSelected : [])
            }
            NCard {
                Text("This selects a local presentation preference. It does not buy, change or unlock a WHOOP membership. Available measurements still depend on your data, hardware and connected services. ECG, AFib classification, blood-pressure insights and private scoring algorithms have not been implemented.")
                    .font(NFont.body(13)).foregroundStyle(NColor.muted)
            }
        }
    }
    private func description(_ tier: ExperienceTier) -> String {
        switch tier {
        case .one: return "Sleep, Recovery, Strain and your locally recorded data."
        case .peak: return "The requested performance and longevity feature grouping."
        case .life: return "The full requested layout grouping; hardware-only measurements remain unavailable."
        }
    }
}
