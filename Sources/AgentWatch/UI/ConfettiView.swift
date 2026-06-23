import SwiftUI

/// A one-shot, full-screen confetti shower. Pieces spawn across the top and
/// fall with a gentle sway and spin, fading out near the bottom. Drawn entirely
/// in SwiftUI; hosted in a transparent click-through window over the whole screen.
struct ConfettiView: View {
    var onDone: () -> Void = {}

    private struct Piece: Identifiable {
        let id: Int
        let xFrac: CGFloat      // 0…1 across the width
        let size: CGFloat
        let color: Color
        let fallTime: Double
        let delay: Double
        let swayAmp: CGFloat
        let swayFreq: Double
        let swayPhase: Double
        let spin: Double         // deg/sec, signed
        let rounded: Bool
    }

    private static let palette: [Color] = [
        Color(red: 0.98, green: 0.82, blue: 0.22),   // sponge yellow
        Color(red: 0.85, green: 0.47, blue: 0.34),   // clay
        Theme.neonCyan, Theme.neonMagenta, Theme.dpGold,
        Color(red: 0.36, green: 0.92, blue: 0.55),   // green
        Color(red: 0.62, green: 0.47, blue: 1.0),    // violet
    ]

    @State private var pieces: [Piece] = ConfettiView.make()
    @State private var start: Date? = nil

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { context in
                let t = start.map { context.date.timeIntervalSince($0) } ?? 0
                ZStack {
                    ForEach(pieces) { p in
                        pieceView(p, t: t, size: geo.size)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            start = Date()
            // Remove the overlay once the longest piece has fallen.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(4.6))
                onDone()
            }
        }
    }

    @ViewBuilder
    private func pieceView(_ p: Piece, t: Double, size: CGSize) -> some View {
        let pt = t - p.delay
        if pt >= 0 {
            let progress = pt / p.fallTime
            let y = -30 + (size.height + 60) * CGFloat(progress)
            let x = p.xFrac * size.width + sin(pt * p.swayFreq + p.swayPhase) * p.swayAmp
            let fade = progress > 0.85 ? max(0, 1 - (progress - 0.85) / 0.15) : 1
            Group {
                if p.rounded {
                    Circle().fill(p.color)
                } else {
                    RoundedRectangle(cornerRadius: 1.5).fill(p.color)
                }
            }
            .frame(width: p.size, height: p.size * (p.rounded ? 1 : 0.6))
            .rotationEffect(.degrees(p.spin * pt))
            .position(x: x, y: y)
            .opacity(Double(fade))
        }
    }

    private static func make() -> [Piece] {
        (0..<140).map { i in
            Piece(
                id: i,
                xFrac: CGFloat.random(in: 0...1),
                size: CGFloat.random(in: 6...12),
                color: palette.randomElement() ?? .yellow,
                fallTime: Double.random(in: 2.6...3.8),
                delay: Double.random(in: 0...0.8),
                swayAmp: CGFloat.random(in: 8...30),
                swayFreq: Double.random(in: 1.5...3.5),
                swayPhase: Double.random(in: 0...(2 * .pi)),
                spin: Double.random(in: 120...520) * (Bool.random() ? 1 : -1),
                rounded: Bool.random()
            )
        }
    }
}
