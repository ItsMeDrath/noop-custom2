import SwiftUI

/// Exact path coordinates transcribed from supplied WHOOP Android vector resource.
struct WhoopWordmark: View {
    var body: some View {
        GeometryReader { geometry in
            Self.drawingPath(in: CGRect(origin: .zero, size: geometry.size)).fill(.white)
        }.accessibilityLabel("WHOOP")
    }
    nonisolated static func drawingPath(in rect: CGRect) -> Path {
        let scale = min(rect.width / 247, rect.height / 40)
        return Path { path in
                path.move(to: CGPoint(x: 68.25, y: 0.05))
                path.addLine(to: CGPoint(x: 63.37, y: 0.05))
                path.addLine(to: CGPoint(x: 63.37, y: 39.99))
                path.addLine(to: CGPoint(x: 68.25, y: 39.99))
                path.addLine(to: CGPoint(x: 68.25, y: 0.05))
                path.closeSubpath()
                path.move(to: CGPoint(x: 87.14, y: 17.59))
                path.addLine(to: CGPoint(x: 73.13, y: 17.59))
                path.addLine(to: CGPoint(x: 73.13, y: 22.47))
                path.addLine(to: CGPoint(x: 87.14, y: 22.47))
                path.addLine(to: CGPoint(x: 87.14, y: 17.59))
                path.closeSubpath()
                path.move(to: CGPoint(x: 96.89, y: 0.05))
                path.addLine(to: CGPoint(x: 92.01, y: 0.05))
                path.addLine(to: CGPoint(x: 92.01, y: 39.99))
                path.addLine(to: CGPoint(x: 96.89, y: 39.99))
                path.addLine(to: CGPoint(x: 96.89, y: 0.05))
                path.closeSubpath()
                path.move(to: CGPoint(x: 205.3, y: 40.0))
                path.addLine(to: CGPoint(x: 210.18, y: 40.0))
                path.addLine(to: CGPoint(x: 210.18, y: 0.05))
                path.addLine(to: CGPoint(x: 205.3, y: 0.05))
                path.addLine(to: CGPoint(x: 205.3, y: 40.0))
                path.closeSubpath()
                path.move(to: CGPoint(x: 221.58, y: 0.05))
                path.addLine(to: CGPoint(x: 215.06, y: 0.05))
                path.addLine(to: CGPoint(x: 215.06, y: 4.79))
                path.addLine(to: CGPoint(x: 221.58, y: 4.79))
                path.addCurve(to: CGPoint(x: 230.46, y: 13.67), control1: CGPoint(x: 226.47, y: 4.79), control2: CGPoint(x: 230.46, y: 8.77))
                path.addCurve(to: CGPoint(x: 221.58, y: 22.56), control1: CGPoint(x: 230.46, y: 18.57), control2: CGPoint(x: 226.47, y: 22.56))
                path.addLine(to: CGPoint(x: 215.06, y: 22.56))
                path.addLine(to: CGPoint(x: 215.06, y: 27.3))
                path.addLine(to: CGPoint(x: 221.58, y: 27.3))
                path.addCurve(to: CGPoint(x: 235.2, y: 13.68), control1: CGPoint(x: 229.08, y: 27.3), control2: CGPoint(x: 235.2, y: 21.19))
                path.addCurve(to: CGPoint(x: 221.58, y: 0.05), control1: CGPoint(x: 235.2, y: 6.16), control2: CGPoint(x: 229.08, y: 0.05))
                path.closeSubpath()
                path.move(to: CGPoint(x: 126.53, y: 0.05))
                path.addCurve(to: CGPoint(x: 106.56, y: 20.02), control1: CGPoint(x: 115.52, y: 0.05), control2: CGPoint(x: 106.56, y: 9.01))
                path.addCurve(to: CGPoint(x: 126.53, y: 39.99), control1: CGPoint(x: 106.56, y: 31.04), control2: CGPoint(x: 115.52, y: 39.99))
                path.addCurve(to: CGPoint(x: 146.5, y: 20.02), control1: CGPoint(x: 137.54, y: 39.99), control2: CGPoint(x: 146.5, y: 31.03))
                path.addCurve(to: CGPoint(x: 126.53, y: 0.05), control1: CGPoint(x: 146.5, y: 9.01), control2: CGPoint(x: 137.54, y: 0.05))
                path.closeSubpath()
                path.move(to: CGPoint(x: 126.53, y: 35.28))
                path.addCurve(to: CGPoint(x: 111.27, y: 20.02), control1: CGPoint(x: 118.11, y: 35.28), control2: CGPoint(x: 111.27, y: 28.44))
                path.addCurve(to: CGPoint(x: 126.53, y: 4.76), control1: CGPoint(x: 111.27, y: 11.6), control2: CGPoint(x: 118.11, y: 4.76))
                path.addCurve(to: CGPoint(x: 141.79, y: 20.02), control1: CGPoint(x: 134.95, y: 4.76), control2: CGPoint(x: 141.79, y: 11.6))
                path.addCurve(to: CGPoint(x: 126.53, y: 35.28), control1: CGPoint(x: 141.79, y: 28.44), control2: CGPoint(x: 134.94, y: 35.28))
                path.closeSubpath()
                path.move(to: CGPoint(x: 175.03, y: 0.05))
                path.addCurve(to: CGPoint(x: 155.07, y: 20.02), control1: CGPoint(x: 164.02, y: 0.05), control2: CGPoint(x: 155.07, y: 9.01))
                path.addCurve(to: CGPoint(x: 175.03, y: 39.99), control1: CGPoint(x: 155.07, y: 31.04), control2: CGPoint(x: 164.03, y: 39.99))
                path.addCurve(to: CGPoint(x: 195.01, y: 20.02), control1: CGPoint(x: 186.04, y: 39.99), control2: CGPoint(x: 195.01, y: 31.03))
                path.addCurve(to: CGPoint(x: 175.03, y: 0.05), control1: CGPoint(x: 195.01, y: 9.01), control2: CGPoint(x: 186.04, y: 0.05))
                path.closeSubpath()
                path.move(to: CGPoint(x: 175.03, y: 35.28))
                path.addCurve(to: CGPoint(x: 159.78, y: 20.02), control1: CGPoint(x: 166.62, y: 35.28), control2: CGPoint(x: 159.78, y: 28.44))
                path.addCurve(to: CGPoint(x: 175.03, y: 4.76), control1: CGPoint(x: 159.78, y: 11.6), control2: CGPoint(x: 166.62, y: 4.76))
                path.addCurve(to: CGPoint(x: 190.29, y: 20.02), control1: CGPoint(x: 183.45, y: 4.76), control2: CGPoint(x: 190.29, y: 11.6))
                path.addCurve(to: CGPoint(x: 175.03, y: 35.28), control1: CGPoint(x: 190.29, y: 28.44), control2: CGPoint(x: 183.45, y: 35.28))
                path.closeSubpath()
                path.move(to: CGPoint(x: 39.63, y: 32.22))
                path.addLine(to: CGPoint(x: 34.44, y: 15.14))
                path.addLine(to: CGPoint(x: 29.71, y: 15.14))
                path.addLine(to: CGPoint(x: 37.27, y: 40.0))
                path.addLine(to: CGPoint(x: 42.0, y: 40.0))
                path.addLine(to: CGPoint(x: 54.16, y: 0.05))
                path.addLine(to: CGPoint(x: 49.42, y: 0.05))
                path.addLine(to: CGPoint(x: 39.63, y: 32.22))
                path.closeSubpath()
                path.move(to: CGPoint(x: 5.54, y: 0.05))
                path.addLine(to: CGPoint(x: 0.8, y: 0.05))
                path.addLine(to: CGPoint(x: 8.36, y: 24.9))
                path.addLine(to: CGPoint(x: 13.1, y: 24.9))
                path.addLine(to: CGPoint(x: 5.54, y: 0.05))
                path.closeSubpath()
                path.move(to: CGPoint(x: 25.11, y: 0.05))
                path.addLine(to: CGPoint(x: 12.96, y: 40.0))
                path.addLine(to: CGPoint(x: 17.69, y: 40.0))
                path.addLine(to: CGPoint(x: 29.85, y: 0.05))
                path.addLine(to: CGPoint(x: 25.11, y: 0.05))
                path.closeSubpath()
                path.move(to: CGPoint(x: 243.25, y: 5.89))
                path.addCurve(to: CGPoint(x: 240.3, y: 2.95), control1: CGPoint(x: 241.62, y: 5.89), control2: CGPoint(x: 240.3, y: 4.57))
                path.addCurve(to: CGPoint(x: 243.25, y: 0.0), control1: CGPoint(x: 240.3, y: 1.32), control2: CGPoint(x: 241.62, y: 0.0))
                path.addCurve(to: CGPoint(x: 246.2, y: 2.95), control1: CGPoint(x: 244.88, y: 0.0), control2: CGPoint(x: 246.2, y: 1.32))
                path.addCurve(to: CGPoint(x: 243.25, y: 5.89), control1: CGPoint(x: 246.2, y: 4.57), control2: CGPoint(x: 244.88, y: 5.89))
                path.closeSubpath()
                path.move(to: CGPoint(x: 243.25, y: 0.55))
                path.addCurve(to: CGPoint(x: 240.89, y: 2.95), control1: CGPoint(x: 241.93, y: 0.55), control2: CGPoint(x: 240.89, y: 1.6))
                path.addCurve(to: CGPoint(x: 243.25, y: 5.35), control1: CGPoint(x: 240.89, y: 4.29), control2: CGPoint(x: 241.93, y: 5.35))
                path.addCurve(to: CGPoint(x: 245.6, y: 2.95), control1: CGPoint(x: 244.57, y: 5.35), control2: CGPoint(x: 245.6, y: 4.29))
                path.addCurve(to: CGPoint(x: 243.25, y: 0.55), control1: CGPoint(x: 245.6, y: 1.6), control2: CGPoint(x: 244.57, y: 0.55))
                path.closeSubpath()
                path.move(to: CGPoint(x: 243.87, y: 4.53))
                path.addLine(to: CGPoint(x: 243.22, y: 3.27))
                path.addLine(to: CGPoint(x: 242.81, y: 3.27))
                path.addLine(to: CGPoint(x: 242.81, y: 4.53))
                path.addLine(to: CGPoint(x: 242.22, y: 4.53))
                path.addLine(to: CGPoint(x: 242.22, y: 1.35))
                path.addLine(to: CGPoint(x: 243.42, y: 1.35))
                path.addCurve(to: CGPoint(x: 244.44, y: 2.33), control1: CGPoint(x: 244.02, y: 1.35), control2: CGPoint(x: 244.44, y: 1.8))
                path.addCurve(to: CGPoint(x: 243.81, y: 3.19), control1: CGPoint(x: 244.44, y: 2.78), control2: CGPoint(x: 244.16, y: 3.07))
                path.addLine(to: CGPoint(x: 244.52, y: 4.53))
                path.addLine(to: CGPoint(x: 243.87, y: 4.53))
                path.closeSubpath()
                path.move(to: CGPoint(x: 243.34, y: 1.85))
                path.addLine(to: CGPoint(x: 242.81, y: 1.85))
                path.addLine(to: CGPoint(x: 242.81, y: 2.81))
                path.addLine(to: CGPoint(x: 243.34, y: 2.81))
                path.addCurve(to: CGPoint(x: 243.87, y: 2.32), control1: CGPoint(x: 243.65, y: 2.81), control2: CGPoint(x: 243.87, y: 2.6))
                path.addCurve(to: CGPoint(x: 243.34, y: 1.84), control1: CGPoint(x: 243.87, y: 2.05), control2: CGPoint(x: 243.66, y: 1.84))
                path.addLine(to: CGPoint(x: 243.34, y: 1.85))
                path.closeSubpath()
            }
        .applying(CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                                   tx: rect.minX + (rect.width - 247 * scale) / 2,
                                   ty: rect.minY + (rect.height - 40 * scale) / 2))
    }
}

/// Monogram polygons from the same supplied vector resource as the wordmark.
struct WhoopMonogram: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / 54.16, rect.height / 40)
        let dx = rect.midX - 54.16 * scale / 2
        let dy = rect.midY - 40 * scale / 2
        let contours: [[CGPoint]] = [
            [CGPoint(x: 39.63, y: 32.22), CGPoint(x: 34.44, y: 15.14), CGPoint(x: 29.71, y: 15.14), CGPoint(x: 37.27, y: 40), CGPoint(x: 42, y: 40), CGPoint(x: 54.16, y: 0.05), CGPoint(x: 49.42, y: 0.05)],
            [CGPoint(x: 5.54, y: 0.05), CGPoint(x: 0.8, y: 0.05), CGPoint(x: 8.36, y: 24.9), CGPoint(x: 13.1, y: 24.9)],
            [CGPoint(x: 25.11, y: 0.05), CGPoint(x: 12.96, y: 40), CGPoint(x: 17.69, y: 40), CGPoint(x: 29.85, y: 0.05)]
        ]
        return Path { path in
            for contour in contours {
                guard let first = contour.first else { continue }
                path.move(to: CGPoint(x: dx + first.x * scale, y: dy + first.y * scale))
                for point in contour.dropFirst() { path.addLine(to: CGPoint(x: dx + point.x * scale, y: dy + point.y * scale)) }
                path.closeSubpath()
            }
        }
    }
}
