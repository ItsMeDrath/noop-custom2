import SwiftUI

/// Scales and plots fixture values only; no physiological score is calculated here.
struct PulseWeekChart: View {
    let days: [PulseHomeDay]
    let selected: Int
    private func recoveryColor(_ value: Int) -> Color {
        value <= 33 ? Color(red: 1, green: 0, blue: 0.18) : value <= 66 ? PulseColor.recoveryYellow : PulseColor.readiness
    }
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width, top: CGFloat = 15, bottom: CGFloat = 192
            let left: CGFloat = 33, right = width - 34
            let plotHeight = bottom - top
            let step = (right - left) / CGFloat(max(1, days.count - 1))
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.10))
                    .frame(width: 30, height: 218).position(x: left + CGFloat(selected) * step, y: 112)
                ForEach(0..<4) { line in
                    let y = top + CGFloat(line) * plotHeight / 3
                    Path { p in p.move(to: CGPoint(x: left - 15, y: y)); p.addLine(to: CGPoint(x: right + 15, y: y)) }.stroke(.white.opacity(0.06), lineWidth: 0.7)
                    Text("\(21 - line * 7)").font(PulseFont.body(9).weight(.semibold)).foregroundStyle(PulseColor.load).position(x: 8, y: y)
                    Text(["100%", "66%", "33%", "0%"][line]).font(PulseFont.body(9).weight(.semibold)).foregroundStyle(line == 0 ? PulseColor.readiness : line == 1 ? PulseColor.recoveryYellow : .red).position(x: width - 7, y: y)
                }
                linePath(days.map { Double($0.readiness) / 100 }, left: left, top: top, step: step, height: plotHeight).stroke(.white.opacity(0.29), lineWidth: 1.6)
                linePath(days.map { $0.load / 21 }, left: left, top: top, step: step, height: plotHeight).stroke(PulseColor.load.opacity(0.55), lineWidth: 1.6)
                ForEach(Array(days.enumerated()), id: \.element.id) { item in
                    let x = left + CGFloat(item.offset) * step
                    let strainY = bottom - CGFloat(item.element.load / 21) * plotHeight
                    let recoveryY = bottom - CGFloat(item.element.readiness) / 100 * plotHeight
                    Circle().fill(PulseColor.card).overlay(Circle().stroke(PulseColor.load, lineWidth: 1.8)).frame(width: 8, height: 8).position(x: x, y: strainY)
                    Circle().fill(PulseColor.card).overlay(Circle().stroke(recoveryColor(item.element.readiness), lineWidth: 1.8)).frame(width: 8, height: 8).position(x: x, y: recoveryY)
                    Text(item.element.load.formatted(.number.precision(.fractionLength(1)))).font(PulseFont.number(11)).foregroundStyle(PulseColor.load)
                        .position(x: x, y: strainY + (item.offset == 3 ? 15 : -13))
                    if item.offset != 4 {
                        Text("\(item.element.readiness)%").font(PulseFont.number(11)).foregroundStyle(recoveryColor(item.element.readiness))
                            .position(x: x, y: recoveryY + ([0, 2, 6].contains(item.offset) ? 14 : -14))
                    }
                    Text("\(item.element.weekday)\n\(item.element.dayNumber)").font(PulseFont.body(9)).multilineTextAlignment(.center).lineSpacing(4)
                        .foregroundStyle(item.offset == selected ? PulseColor.text : PulseColor.muted).position(x: x, y: 213)
                }
            }
        }.frame(height: 223).accessibilityElement(children: .ignore)
            .accessibilityLabel("Illustrative seven-day Strain and Recovery chart. Selected day Strain \(days[selected].load), Recovery \(days[selected].readiness) percent.")
    }
    private func linePath(_ values: [Double], left: CGFloat, top: CGFloat, step: CGFloat, height: CGFloat) -> Path {
        Path { path in
            for (index, value) in values.enumerated() {
                let point = CGPoint(x: left + CGFloat(index) * step, y: top + (1 - CGFloat(value)) * height)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
    }
}
struct PulseStressChart: View {
    let values: [Double]
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width, left: CGFloat = 25, right = width - 2
            let top: CGFloat = 19, bottom: CGFloat = 162
            ZStack(alignment: .topLeading) {
                ForEach(0..<4) { row in
                    let y = top + CGFloat(row) * (bottom - top) / 3
                    Path { p in p.move(to: CGPoint(x: left, y: y)); p.addLine(to: CGPoint(x: right, y: y)) }.stroke(.white.opacity(0.11), lineWidth: 0.7)
                    Text(Double(3 - row).formatted(.number.precision(.fractionLength(1)))).font(PulseFont.body(8)).foregroundStyle(PulseColor.muted).position(x: 9, y: y)
                }
                ForEach([0.37, 0.70], id: \.self) { fraction in
                    Path { p in let x = left + (right - left) * fraction; p.move(to: CGPoint(x: x, y: top)); p.addLine(to: CGPoint(x: x, y: bottom)) }.stroke(.white.opacity(0.11), lineWidth: 0.7)
                }
                ForEach([0.05, 0.86], id: \.self) { fraction in
                    let x = left + (right - left) * fraction
                    Rectangle().fill(PulseColor.load.opacity(0.10)).frame(width: 10, height: bottom - top).position(x: x, y: (top + bottom) / 2)
                    Rectangle().fill(PulseColor.load).frame(width: 10, height: 2).position(x: x, y: top)
                    Image(systemName: fraction < 0.1 ? "figure.walk" : "figure.soccer").font(.system(size: 14)).position(x: x, y: 5)
                }
                Path { path in
                    for (index, value) in values.enumerated() {
                        let point = CGPoint(x: left + CGFloat(index) / CGFloat(max(1, values.count - 1)) * (right - left - 2), y: bottom - CGFloat(value / 3) * (bottom - top))
                        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                }.stroke(LinearGradient(colors: [PulseColor.sleep, PulseColor.mint, Color(red: 0.85, green: 0.78, blue: 0.33)], startPoint: .bottom, endPoint: .top), style: StrokeStyle(lineWidth: 1.7, lineJoin: .round))
                Path { p in p.move(to: CGPoint(x: right, y: top - 10)); p.addLine(to: CGPoint(x: right, y: bottom + 7)) }.stroke(.white.opacity(0.65), style: StrokeStyle(lineWidth: 0.8, dash: [4, 3]))
                Circle().fill(.white).frame(width: 4, height: 4).position(x: right, y: bottom + 7)
                HStack {
                    Text("9:33 AM"); Spacer(); Text("2:00 PM"); Spacer(); Text("6:00 PM"); Spacer(); Text("9:29 PM").foregroundStyle(PulseColor.text)
                }.font(PulseFont.body(8).weight(.medium)).foregroundStyle(PulseColor.muted).frame(width: width - 9).position(x: width / 2, y: 181)
            }
        }.frame(height: 194).accessibilityLabel("Illustrative stress graph, scale zero to three, ending at 1.8. Not a live sensor calculation.")
    }
}
