import SwiftUI
import AppKit

// MARK: - Color helpers

extension Color {
    /// Build a Color from a packed 0xRRGGBB hex value.
    init(hex: UInt) {
        self.init(.sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8)  & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255,
            opacity: 1)
    }

    /// Adaptive color resolved per render-time appearance (light/dark).
    static func adaptive(_ light: UInt, _ dark: UInt) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(Color(hex: isDark ? dark : light))
        })
    }
}

/// Visual identity: "Warm Glass" — Anthropic-editorial. Warm neutral surfaces,
/// generous calm, soft depth, Liquid Glass on chrome.
/// Coral is reserved for exactly one meaning — "your turn" (needs-input / primary
/// CTA / approval). Blue = working, green = done, gray = everything else.
enum Theme {
    // MARK: Legacy accents (KEEP names — remapped to the warm palette)

    /// -> working / calm action (blue)
    static let neonCyan    = Color.adaptive(0x5B8AB8, 0x6A9BCC)
    /// -> QUIET neutral (mid gray); the old 2nd loud color is gone
    static let neonMagenta = Color.adaptive(0xB0AEA5, 0xB0AEA5)
    /// -> needs-attention (coral)
    static let dpGold      = Color.adaptive(0xD97757, 0xE0865F)
    /// -> mid gray neutral / idle
    static let dpChrome    = Color(hex: 0xB0AEA5)
    /// -> soft coral notch glow
    static let glowOrange  = Color.adaptive(0xD97757, 0xE0865F)
    /// -> warm surface base
    static let inkDeep     = Color.adaptive(0xFAF9F5, 0x1B1A17)
    /// -> warm raised surface
    static let inkSoft     = Color.adaptive(0xFFFFFF, 0x26241F)

    // MARK: New semantic tokens (use everywhere going forward)

    /// THE one attention/CTA color: needs-input, approval, Allow.
    static let accent        = dpGold                             // coral
    /// "working" status + calm/informational actions
    static let accentBlue    = neonCyan
    /// success / finished
    static let accentGreen   = Color.adaptive(0x67794F, 0x8AA06A)
    /// idle status, neutral chrome
    static let idle          = dpChrome
    /// destructive (kill, deny, quit) — a warm de-neoned red
    static let danger        = Color.adaptive(0xB0503C, 0xC86A54)
    /// label color on a filled-coral CTA (ivory, both modes)
    static let onAccent      = Color(hex: 0xFAF9F5)

    // Surfaces
    static let surface       = inkDeep                            // window / popup base (opaque)
    static let surfaceRaised = inkSoft                            // cards, tiles, hovered rows
    static let surfaceSunken = Color.adaptive(0xF1EFE7, 0x141312) // inset wells, payload boxes
    /// row/control hover plate — apply .opacity(1.0 light / 0.06 dark) at use site
    static let hover         = Color.adaptive(0xE8E6DC, 0xFFFFFF)

    // Text
    static let textPrimary   = Color.adaptive(0x141413, 0xFAF9F5)
    static let textSecondary = Color.adaptive(0x5C5A53, 0xB0AEA5)
    /// + .opacity(0.62) at use in dark contexts
    static let textTertiary  = Color.adaptive(0x8A887F, 0xB0AEA5)

    // Lines — apply opacity at the use site (0.10 light / 0.12 dark; strong 0.16).
    static let hairline       = Color.adaptive(0x141413, 0xFAF9F5)
    static let hairlineStrong = Color.adaptive(0x141413, 0xFAF9F5)
    /// top stop of the Liquid Glass specular rim
    static let specularTop    = Color.adaptive(0xFAF9F5, 0xFAF9F5)
    /// bottom stop of the specular rim
    static let specularBottom = Color.adaptive(0xFAF9F5, 0xFAF9F5)

    // MARK: Profiles

    /// Palette for profile accents — cycled by a stable order-independent hash so
    /// each Claude config profile reads with a consistent distinct color.
    /// Coral is deliberately excluded so profile identity never competes with the
    /// attention state.
    private static let profilePalette: [Color] = [
        Color.adaptive(0x5B8AB8, 0x6A9BCC),  // blue
        Color.adaptive(0x67794F, 0x8AA06A),  // green
        Color.adaptive(0xC68A3E, 0xD69B4E),  // amber
        Color.adaptive(0x8A6F98, 0x9A7AA6),  // plum
        Color.adaptive(0x4F8579, 0x5F9C8F),  // teal
        Color.adaptive(0xA5654E, 0xB5715A),  // clay (browner than coral, distinct)
    ]

    /// Stable accent color for a profile label.
    static func profileColor(_ profile: String) -> Color {
        if profile == "default" { return Color.adaptive(0xB0AEA5, 0xB0AEA5) }
        // Deterministic, order-independent hash over the bytes.
        let sum = profile.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return profilePalette[sum % profilePalette.count]
    }

    // MARK: Status colors

    static func statusColor(_ s: SessionStatus) -> Color {
        switch s {
        case .working:    return accentBlue                       // calm blue
        case .idle:       return idle                             // mid gray, recedes
        case .needsInput: return accent                           // coral — the one loud color
        case .unknown:    return Color.adaptive(0x8A887F, 0x8A887F)
        }
    }

    // MARK: Typography — legacy symbols (KEEP names)

    /// button/row labels
    static let chromeFont    = Font.system(size: 13, weight: .medium,   design: .rounded)
    /// metadata / eyebrows
    static let chromeCaption = Font.system(size: 10, weight: .semibold, design: .monospaced)
    /// section/card titles
    static let chromeTitle   = Font.system(size: 17, weight: .semibold, design: .rounded)
    /// cost total
    static let displayLarge  = Font.system(size: 34, weight: .semibold, design: .monospaced).monospacedDigit()

    // MARK: Typography — new role tokens

    /// window headers (COSTS, HISTORY)
    static let titleWindow  = Font.system(size: 20, weight: .semibold, design: .rounded)
    /// approval headline, card titles
    static let titleCard    = Font.system(size: 15, weight: .semibold, design: .rounded)
    /// session row primary
    static let rowTitle     = Font.system(size: 13, weight: .medium,   design: .rounded)
    /// section labels, tile captions, "PERMISSION" (UPPERCASE, tracking 1.2)
    static let eyebrow      = Font.system(size: 10, weight: .semibold, design: .monospaced)
    /// profile header, chip labels (UPPERCASE, tracking 1.4)
    static let eyebrowTiny  = Font.system(size: 9,  weight: .semibold, design: .monospaced)
    /// empty-state copy, disclaimers, sentence subtitles
    static let prose        = Font.system(size: 13, weight: .regular,  design: .serif)
    /// IDs, cwd, timers, token counts
    static let mono         = Font.system(size: 11, weight: .medium,   design: .monospaced).monospacedDigit()
    /// dollar amounts, metric values
    static let monoStrong   = Font.system(.callout, design: .monospaced).weight(.semibold).monospacedDigit()
    /// command/tool payload
    static let approvalDetail = Font.system(size: 11, weight: .regular, design: .monospaced)
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
            Text(profile.uppercased())
                .font(Theme.eyebrowTiny)
                .tracking(1.4)
                .foregroundStyle(tint)
            if let count {
                Text("· \(count)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
        }
        .padding(.top, 12)
        .padding(.bottom, 6)
        .padding(.horizontal, 14)
    }
}

// MARK: - Status dot (glanceable signal; only working + needsInput animate)

struct StatusDot: View {
    let status: SessionStatus
    @State private var pulse = false

    var body: some View {
        ZStack {
            if status == .working || status == .needsInput {
                Circle()
                    .fill(Theme.statusColor(status).opacity(0.22))
                    .frame(width: 16, height: 16)
                    .blur(radius: 3)
                    .opacity(pulse ? 0.85 : 0.40)
                    .animation(
                        .easeInOut(duration: status == .needsInput ? 1.6 : 1.2)
                            .repeatForever(autoreverses: true),
                        value: pulse
                    )
            }
            // Inner core — no hard colored shadow.
            Circle()
                .fill(Theme.statusColor(status))
                .frame(width: 8, height: 8)
        }
        .frame(width: 18, height: 18)
        .task(id: status) {
            pulse = (status == .working || status == .needsInput) ? true : false
        }
    }
}

// MARK: - Quiet profile chip / badge

struct NeonGlassCapsule: View {
    let label: String
    let tint: Color

    var body: some View {
        Text(label.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(0.5)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Theme.surfaceRaised))
            .overlay(
                Capsule().strokeBorder(tint.opacity(0.45), lineWidth: 0.75)
            )
    }
}

// MARK: - Reusable glass button (one style, prominent flag)

struct NeonGlassButtonStyle: ButtonStyle {
    var tint: Color = Theme.accentBlue
    var prominent: Bool = false                         // true = filled coral CTA

    func makeBody(configuration c: Configuration) -> some View {
        c.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(prominent ? Theme.onAccent : tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassEffect(.regular.tint(prominent
                ? tint.opacity(c.isPressed ? 0.98 : 0.88)
                : tint.opacity(c.isPressed ? 0.24 : 0.12)), in: Capsule())
            .overlay(
                Capsule().strokeBorder(
                    LinearGradient(colors: [Theme.specularTop.opacity(0.30), Theme.specularBottom.opacity(0.05)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.75)
            )
            .overlay(
                Capsule().strokeBorder(tint.opacity(prominent ? 0 : 0.35), lineWidth: 0.5)
            )
            .scaleEffect(c.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: c.isPressed)
    }
}

extension ButtonStyle where Self == NeonGlassButtonStyle {
    /// default calm action (blue)
    static var neonCyan:    NeonGlassButtonStyle { .init(tint: Theme.accentBlue) }
    /// now QUIET neutral (mid gray)
    static var neonMagenta: NeonGlassButtonStyle { .init(tint: Theme.idle) }
    /// coral attention (sparing)
    static var neonGold:    NeonGlassButtonStyle { .init(tint: Theme.accent) }
    /// filled coral — Allow / the one CTA
    static var primary:     NeonGlassButtonStyle { .init(tint: Theme.accent, prominent: true) }
    /// toolbar/row icons
    static var secondary:   NeonGlassButtonStyle { .init(tint: Theme.textSecondary) }
    /// destructive
    static var danger:      NeonGlassButtonStyle { .init(tint: Theme.danger) }
}

// MARK: - View modifier: warm surface background for windows

struct DarkGlassBackground: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    Theme.surface                                       // opaque warm base
                    LinearGradient(
                        colors: [Color.white.opacity(scheme == .dark ? 0.03 : 0.0), .clear],
                        startPoint: .top, endPoint: .bottom)            // faint top sheen
                    RadialGradient(
                        colors: [Theme.accent.opacity(scheme == .dark ? 0.06 : 0.05), .clear],
                        center: .topTrailing,
                        startRadius: 20, endRadius: 320)                // single warm accent
                }
                .ignoresSafeArea()
            }
            .preferredColorScheme(.dark)
    }
}

extension View {
    func darkGlassBackground() -> some View { modifier(DarkGlassBackground()) }
}
