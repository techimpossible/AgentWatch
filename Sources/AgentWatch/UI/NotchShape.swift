import SwiftUI

/// A shape that hangs from the top of the screen with a flat top edge
/// (mating with the notch / menu bar) and rounded bottom corners.
/// Mimics the iPhone Dynamic Island silhouette.
struct NotchShape: Shape {
    var cornerRadius: CGFloat = 18

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(cornerRadius, rect.width / 2, rect.height)
        // Start at top-left
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Top edge (flat, mates with notch)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        // Right side down to start of bottom-right curve
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        // Bottom-right rounded corner
        p.addArc(
            center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
            radius: r,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        // Bottom edge to start of bottom-left curve
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        // Bottom-left rounded corner
        p.addArc(
            center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
            radius: r,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        // Left edge back to top
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        return p
    }
}
