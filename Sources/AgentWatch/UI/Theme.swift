import SwiftUI

/// Visual identity: Liquid Glass + Daft Punk-era neon.
/// Cyan + magenta accents, gold for "needs attention", silver/chrome for idle.
/// All chrome (toolbars, buttons, badges) is glass; bodies stay solid for readability.
enum Theme {
    // Neon accents (Daft Punk / Tron-era electronics)
    static let neonCyan    = Color(red:  0/255, green: 240/255, blue: 255/255)
    static let neonMagenta = Color(red: 255/255, green:  0/255, blue: 229/255)
    static let dpGold      = Color(red: 255/255, green: 200/255, blue:  60/255)
    static let dpChrome    = Color(red: 200/255, green: 200/255, blue: 220/255)
    static let glowOrange  = Color(red: 245/255, green: 130/255, blue:  55/255)   // clay-orange notch glow

    // Backgrounds and inks
    static let inkDeep     = Color(red:   6/255, green:   8/255, blue:  14/255)
    static let inkSoft     = Color(red:  18/255, green:  20/255, blue:  28/255)

    /// Palette for profile accents — cycled by a stable hash of the profile name
    /// so each Claude config profile reads with a consistent distinct color.
    private static let profilePalette: [Color] = [
        neonCyan, neonMagenta, dpGold,
        Color(red:  80/255, green: 255/255, blue: 140/255),  // neon green
        Color(red: 160/255, green: 120/255, blue: 255/255),  // violet
        Color(red: 255/255, green: 140/255, blue:  60/255),  // amber-orange
    ]

    /// Stable accent color for a profile label.
    static func profileColor(_ profile: String) -> Color {
        if profile == "default" { return dpChrome }
        // Deterministic, order-independent hash over the bytes.
        let sum = profile.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return profilePalette[sum % profilePalette.count]
    }

    // Status colors (override SwiftUI semantic ones)
    static func statusColor(_ s: SessionStatus) -> Color {
        switch s {
        case .working:    return neonCyan
        case .idle:       return dpChrome
        case .needsInput: return dpGold
        case .unknown:    return .gray
        }
    }

    // Typography — monospaced rounded for chrome, regular system for body.
    static let chromeFont    = Font.system(.body,   design: .monospaced).weight(.semibold)
    static let chromeCaption = Font.system(.caption,design: .monospaced).weight(.semibold)
    static let chromeTitle   = Font.system(.title2, design: .monospaced).weight(.bold)
    static let displayLarge  = Font.system(size: 32, weight: .bold,      design: .monospaced)
}

// MARK: - Profile section header (groups sessions by Claude config profile)

struct ProfileSectionHeader: View {
    let profile: String
    var count: Int? = nil

    var body: some View {
        let tint = Theme.profileColor(profile)
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
                .shadow(color: tint.opacity(0.7), radius: 2)
            Text(profile.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(tint)
            if let count {
                Text("· \(count)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }
}

// MARK: - Pulsing status dot (visual signal for "Working")

struct StatusDot: View {
    let status: SessionStatus
    @State private var pulse = false

    var body: some View {
        ZStack {
            // Outer glow — only animated when status is .working
            Circle()
                .fill(Theme.statusColor(status).opacity(0.30))
                .frame(width: 18, height: 18)
                .blur(radius: 4)
                .opacity(status == .working && pulse ? 0.85 : 0.40)
                .animation(
                    status == .working
                        ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true)
                        : nil,
                    value: pulse
                )
            // Inner core (no animation)
            Circle()
                .fill(Theme.statusColor(status))
                .frame(width: 8, height: 8)
                .shadow(color: Theme.statusColor(status).opacity(0.8), radius: 3)
        }
        .frame(width: 20, height: 20)
        .task(id: status) {
            // Kick the pulse only for working sessions; idempotent across re-mounts.
            pulse = (status == .working) ? !pulse : false
        }
    }
}

// MARK: - Neon glass capsule for badges/role pills

struct NeonGlassCapsule: View {
    let label: String
    let tint: Color

    var body: some View {
        Text(label.uppercased())
            .font(.caption2.monospaced().weight(.bold))
            .tracking(0.5)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .glassEffect(.regular.tint(tint.opacity(0.18)), in: Capsule())
            .overlay(
                Capsule().strokeBorder(tint.opacity(0.5), lineWidth: 0.5)
            )
    }
}

// MARK: - Reusable styled button (glass + neon accent)

struct NeonGlassButtonStyle: ButtonStyle {
    var tint: Color = Theme.neonCyan
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.monospaced().weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassEffect(.regular.tint(tint.opacity(configuration.isPressed ? 0.35 : 0.18)), in: Capsule())
            .overlay(
                Capsule().strokeBorder(tint.opacity(0.5), lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == NeonGlassButtonStyle {
    static var neonCyan:    NeonGlassButtonStyle { .init(tint: Theme.neonCyan) }
    static var neonMagenta: NeonGlassButtonStyle { .init(tint: Theme.neonMagenta) }
    static var neonGold:    NeonGlassButtonStyle { .init(tint: Theme.dpGold) }
}

// MARK: - View modifier: dark glass background for windows

struct DarkGlassBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    Theme.inkDeep
                    // Subtle radial neon glow in the corner — gives the "cyberpunk room" feel
                    RadialGradient(
                        colors: [Theme.neonCyan.opacity(0.18), .clear],
                        center: .topLeading,
                        startRadius: 30,
                        endRadius: 380
                    )
                    RadialGradient(
                        colors: [Theme.neonMagenta.opacity(0.12), .clear],
                        center: .bottomTrailing,
                        startRadius: 30,
                        endRadius: 380
                    )
                }
                .ignoresSafeArea()
            }
            .preferredColorScheme(.dark)
    }
}

extension View {
    func darkGlassBackground() -> some View { modifier(DarkGlassBackground()) }
}
