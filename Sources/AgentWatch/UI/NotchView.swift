import SwiftUI

/// Dynamic-Island-style notch UI. Three states:
///   - Collapsed: small pill, dot + session count.
///   - Hovering (not clicked): medium preview with session list.
///   - Active (sticky): full popup-size panel with all controls.
/// Click toggles active mode. Click again collapses.
struct NotchView: View {
    @Environment(AppState.self) private var state
    @Environment(NotchUIState.self) private var uiState
    @State private var hovering = false
    @State private var sticky = false
    @State private var pulse = false

    private var topStatus: SessionStatus {
        if state.sessions.contains(where: { $0.status == .needsInput }) { return .needsInput }
        if state.sessions.contains(where: { $0.status == .working })    { return .working }
        return .idle
    }
    private var statusTint: Color { Theme.statusColor(topStatus) }

    /// The notch is silent until something genuinely needs you — the coral
    /// attention ring shows ONLY for needs-input or a pending approval.
    private var needsAttention: Bool { topStatus == .needsInput || approval != nil }

    /// Height of the menu-bar / camera-notch band to keep active content clear of.
    private var menuBarInset: CGFloat {
        NSScreen.notchedScreen()?.safeAreaInsets.top ?? 28
    }

    /// Shared horizontal inset for every stage's content, so the collapsed pill,
    /// preview rows and approval card all read off the same left/right gutter.
    private var contentInset: CGFloat { 14 }

    /// Window outline per stage: a flat-top notch silhouette while collapsed /
    /// preview (mates with the physical notch), but a fully rounded rectangle
    /// when the big panel is unfolded so the glow wraps all the way around.
    private var panelShape: AnyShape {
        switch stage {
        case .active, .approval:
            return AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        default:
            return AnyShape(NotchShape(cornerRadius: cornerRadius))
        }
    }

    /// The pending tool-permission request, if any — drives the approval stage.
    private var approval: ApprovalRequest? { ApprovalBroker.shared.current }

    private var stage: NotchUIState.Stage {
        if approval != nil { return .approval }   // demands attention; overrides hover/click
        if sticky { return .active }
        if hovering { return .preview(rows: max(1, state.sessions.count)) }
        return .collapsed
    }

    private var cornerRadius: CGFloat {
        switch stage {
        case .collapsed: return 14
        case .preview:   return 20
        case .active:    return 26
        case .approval:  return 26
        }
    }

    var body: some View {
        ZStack {
            // The notch surface — dense, dark Liquid Glass mated to the physical
            // bezel. Opaque warm base + frosted material + specular rim. The window
            // is resized by the controller to match the current stage exactly.
            panelShape
                .fill(Theme.surface)                               // near-opaque warm-dark base
                .overlay(panelShape.fill(.regularMaterial))        // Liquid Glass substrate
                .overlay(
                    // The one dimensional flourish: a soft specular rim.
                    panelShape.stroke(
                        LinearGradient(
                            colors: [Theme.specularTop.opacity(0.30), Theme.specularBottom.opacity(0.05)],
                            startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.75)
                )
                .overlay(edgeTreatment)
                .clipShape(panelShape)

            // Content for the current stage
            switch stage {
            case .collapsed:
                collapsedContent.padding(.horizontal, 12).padding(.vertical, 4)
            case .preview:
                expandedContent.padding(.horizontal, contentInset).padding(.vertical, 12)
            case .active:
                activePanel
            case .approval:
                approvalContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(panelShape)
        .preferredColorScheme(.dark)     // the notch always renders dark (physical bezel)
        .onHover { newValue in
            if !sticky && approval == nil { hovering = newValue }
        }
        .onTapGesture {
            guard approval == nil else { return }   // during approval, taps go to the action buttons
            sticky.toggle()
            if sticky { hovering = true }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulse.toggle()
            }
            // Ensure the window starts at the right size on first show.
            uiState.stage = stage
        }
        .onChange(of: stage) { _, newStage in
            // Push stage to the controller so it can resize the host window.
            uiState.stage = newStage
        }
    }

    /// Outer edge per state: a coral attention ring only when something needs you,
    /// a quiet static blue edge while working, and a barely-there hairline at rest.
    @ViewBuilder private var edgeTreatment: some View {
        if needsAttention {
            ZStack {
                panelShape
                    .stroke(Theme.accent.opacity(pulse ? 0.55 : 0.30), lineWidth: 2)
                    .blur(radius: 3)
                panelShape
                    .stroke(Theme.accent.opacity(0.7), lineWidth: 1)
            }
        } else if topStatus == .working {
            panelShape.stroke(Theme.accentBlue.opacity(0.35), lineWidth: 1)
        } else {
            panelShape.stroke(Theme.hairline.opacity(0.12), lineWidth: 0.5)
        }
    }

    // MARK: - Active (full panel, unfolded on click)

    /// The unfolded panel: MenuBarContent as a rounded card, pushed below the
    /// menu-bar/notch band, in a ScrollView, with the window sized to fit it.
    private var activePanel: some View {
        // The panel fills the window edge-to-edge so the rim on `panelShape`
        // hugs it exactly; breathing room is inside MenuBarContent (top/bottom
        // insets) rather than an outer gutter.
        return ScrollView(.vertical, showsIndicators: false) {
            MenuBarContent(topInset: menuBarInset + 12, bottomInset: 16)
                .environment(state)
                .frame(width: NotchUIState.expandedWidth)
                .fixedSize(horizontal: false, vertical: true)   // natural height
                .background(GeometryReader { g in
                    Color.clear.preference(key: ActiveContentHeightKey.self, value: g.size.height)
                })
        }
        .scrollBounceBehavior(.basedOnSize)
        .clipShape(panelShape)
        .onPreferenceChange(ActiveContentHeightKey.self) { h in
            // Grow the window to fit content; the controller clamps to the
            // screen and the ScrollView handles any overflow.
            uiState.activeDesiredHeight = h
        }
    }

    // MARK: - Collapsed (just below the notch)

    private var collapsedContent: some View {
        // Dot + count travel together as one centered group (both axes).
        HStack(spacing: 6) {
            // idle = mid gray (no halo) · working = blue · needsInput = coral.
            Circle()
                .fill(statusTint)
                .frame(width: 8, height: 8)
                .opacity(topStatus == .idle ? 0.55 : (pulse ? 1.0 : 0.6))

            if state.sessions.isEmpty {
                Text("AGENTWATCH")
                    .font(Theme.eyebrowTiny)
                    .tracking(1.4)
                    .foregroundStyle(Theme.textSecondary.opacity(0.65))
            } else {
                Text("\(state.sessions.count)")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                // No exclamation glyph — the coral dot + ring already signal
                // needs-input, keeping the pill quiet.
            }
        }
        .fixedSize()
    }

    // MARK: - Expanded (full session preview on hover)

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("AGENTWATCH")
                    .font(Theme.eyebrowTiny)
                    .tracking(1.4)
                    .foregroundStyle(Theme.accentBlue)
                Text("·")
                    .font(Theme.eyebrow)
                    .foregroundStyle(Theme.textTertiary)
                Text("\(state.sessions.count) ACTIVE")
                    .font(Theme.eyebrow)
                    .tracking(1.2)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("CLICK TO OPEN")
                    .font(Theme.eyebrowTiny)
                    .tracking(1.4)
                    .foregroundStyle(Theme.textTertiary)
            }

            if state.sessions.isEmpty {
                Text("No active Claude Code sessions")
                    .font(Theme.prose)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            } else {
                VStack(spacing: 8) {
                    ForEach(state.sessions.prefix(6)) { session in
                        notchRow(session: session)
                    }
                    if state.sessions.count > 6 {
                        Text("+ \(state.sessions.count - 6) more")
                            .font(Theme.mono)
                            .foregroundStyle(Theme.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Approval (pending tool-permission request, rendered in the notch)

    @ViewBuilder private var approvalContent: some View {
        if let req = approval {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.accent)
                    Text("PERMISSION")
                        .font(Theme.eyebrow)
                        .tracking(1.2)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    if let prof = approvalProfile(req) {
                        // Glass chip variant — floats over the busy card content.
                        Text(prof.uppercased())
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .tracking(0.5)
                            .foregroundStyle(Theme.profileColor(prof))
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .glassEffect(.regular.tint(Theme.profileColor(prof).opacity(0.16)), in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.profileColor(prof).opacity(0.45), lineWidth: 0.75))
                    }
                    if ApprovalBroker.shared.pending.count > 1 {
                        Text("+\(ApprovalBroker.shared.pending.count - 1)")
                            .font(Theme.mono)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }

                Text(req.headline)
                    .font(Theme.titleCard)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)

                ScrollView(.vertical) {
                    Text(req.detail.isEmpty ? "(no details)" : req.detail)
                        .font(Theme.approvalDetail)
                        .foregroundStyle(Theme.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surfaceSunken))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.hairline.opacity(0.12), lineWidth: 0.5)
                )

                HStack(spacing: 8) {
                    approvalButton("Deny", tint: Theme.danger, prominent: true) {
                        ApprovalBroker.shared.resolve(req, decision: "deny")
                    }
                    approvalButton("Ask in terminal", tint: Theme.textSecondary) {
                        ApprovalBroker.shared.resolve(req, decision: "ask")
                    }
                    Spacer()
                    approvalButton("Allow", tint: Theme.accent, prominent: true) {
                        ApprovalBroker.shared.resolve(req, decision: "allow")
                    }
                }
            }
            .padding(.horizontal, contentInset)
            .padding(.top, menuBarInset + 8)   // clear the camera housing
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    /// A tap-gesture "button" (not SwiftUI Button) so it works inside the notch's
    /// non-key borderless window, matching how the notch already handles taps.
    /// `prominent` = filled (coral CTA / danger); otherwise neutral glass.
    /// Every button shares one label font + inset so all three are the same
    /// height and rest on a single baseline.
    private func approvalButton(_ label: String, tint: Color, prominent: Bool = false,
                                action: @escaping () -> Void) -> some View {
        Text(label)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .lineLimit(1)
            .foregroundStyle(prominent ? Theme.onAccent : tint)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .glassEffect(.regular.tint(prominent ? tint.opacity(0.88) : tint.opacity(0.12)), in: Capsule())
            .overlay(
                Capsule().strokeBorder(
                    LinearGradient(colors: [Theme.specularTop.opacity(0.30), Theme.specularBottom.opacity(0.05)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.75)
            )
            .overlay(Capsule().strokeBorder(tint.opacity(prominent ? 0 : 0.35), lineWidth: 0.5))
            .contentShape(Capsule())
            .onTapGesture(perform: action)
    }

    private func approvalProfile(_ req: ApprovalRequest) -> String? {
        state.sessions.first { $0.sessionId == req.sessionId }?.profile
    }

    private func notchRow(session: Session) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Theme.statusColor(session.status))
                .frame(width: 8, height: 8)
            Text(session.displayTitle)
                .font(Theme.rowTitle)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            // Trailing meta — mono, right-aligned, never clipped by a long title.
            HStack(spacing: 8) {
                Label(session.elapsedString, systemImage: "clock")
                    .font(Theme.mono)
                    .foregroundStyle(Theme.textSecondary)
                Label(session.tokensString, systemImage: "circle.hexagongrid")
                    .font(Theme.mono)
                    .foregroundStyle(Theme.textSecondary)
            }
            .labelStyle(NotchInlineLabelStyle())
            .fixedSize(horizontal: true, vertical: false)
        }
    }
}

/// Reports the active panel's natural content height up to NotchView.
private struct ActiveContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Tighter Label rendering — small icon, then text — for the cramped notch rows.
private struct NotchInlineLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
                .imageScale(.small)
            configuration.title
        }
    }
}
