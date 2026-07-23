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

    /// Height of the menu-bar / camera-notch band to keep active content clear of.
    private var menuBarInset: CGFloat {
        NSScreen.notchedScreen()?.safeAreaInsets.top ?? 28
    }

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
            // The notch shape + dark fill — fills the entire host window, which
            // the controller resizes to match the current stage exactly.
            panelShape
                .fill(Color.black)
                .overlay(
                    panelShape
                        .stroke(statusTint.opacity(topStatus == .idle ? 0.0 : 0.45), lineWidth: 0.8)
                )
                // Bold pulsating clay-orange glow lining the inside of the panel,
                // following its rounded outline. Clipped to the shape so the whole
                // glow lands inside the window (an outer shadow would be clipped).
                .overlay(
                    ZStack {
                        panelShape
                            .stroke(Theme.glowOrange, lineWidth: pulse ? 10 : 5)
                            .blur(radius: pulse ? 13 : 7)
                        panelShape
                            .stroke(Theme.glowOrange, lineWidth: pulse ? 4 : 2)
                            .blur(radius: 2)
                        panelShape
                            .stroke(Theme.glowOrange, lineWidth: 1.5)
                    }
                    .opacity(pulse ? 1.0 : 0.6)
                )
                .clipShape(panelShape)

            // Content for the current stage
            switch stage {
            case .collapsed:
                collapsedContent.padding(.horizontal, 12).padding(.vertical, 4)
            case .preview:
                expandedContent.padding(.horizontal, 16).padding(.vertical, 12)
            case .active:
                activePanel
            case .approval:
                approvalContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(panelShape)
        .onHover { newValue in
            if !sticky && approval == nil { hovering = newValue }
        }
        .onTapGesture {
            guard approval == nil else { return }   // during approval, taps go to the action buttons
            sticky.toggle()
            if sticky { hovering = true }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
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

    // MARK: - Active (full panel, unfolded on click)

    /// The unfolded panel: MenuBarContent as a rounded card, pushed below the
    /// menu-bar/notch band, in a ScrollView, with the window sized to fit it.
    private var activePanel: some View {
        // The panel fills the window edge-to-edge so the glow on `panelShape`
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
        HStack(spacing: 6) {
            Circle()
                .fill(statusTint)
                .frame(width: 7, height: 7)
                .opacity(topStatus == .idle ? 0.55 : (pulse ? 1.0 : 0.6))
                .shadow(color: statusTint.opacity(0.7), radius: 3)

            if state.sessions.isEmpty {
                Text("AGENTWATCH")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(Theme.dpChrome.opacity(0.65))
            } else {
                Text("\(state.sessions.count)")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                if topStatus == .needsInput {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.dpGold)
                }
            }
        }
    }

    // MARK: - Expanded (full session preview on hover)

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("AGENTWATCH")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(Theme.neonCyan)
                Text("·")
                    .foregroundStyle(Theme.dpChrome.opacity(0.4))
                Text("\(state.sessions.count) ACTIVE")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(Theme.dpChrome.opacity(0.9))
                Spacer()
                Text("CLICK TO OPEN")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.dpChrome.opacity(0.45))
            }

            if state.sessions.isEmpty {
                Text("No active Claude Code sessions")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dpChrome.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            } else {
                VStack(spacing: 4) {
                    ForEach(state.sessions.prefix(6)) { session in
                        notchRow(session: session)
                    }
                    if state.sessions.count > 6 {
                        Text("+ \(state.sessions.count - 6) more")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.dpChrome.opacity(0.5))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Approval (pending tool-permission request, rendered in the notch)

    @ViewBuilder private var approvalContent: some View {
        if let req = approval {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.dpGold)
                    Text("PERMISSION")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .tracking(1.3)
                        .foregroundStyle(Theme.dpChrome.opacity(0.85))
                    Spacer()
                    if let prof = approvalProfile(req) {
                        Text(prof.uppercased())
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(Color.black.opacity(0.55))
                                .overlay(Capsule().strokeBorder(Theme.profileColor(prof).opacity(0.8), lineWidth: 1)))
                    }
                    if ApprovalBroker.shared.pending.count > 1 {
                        Text("+\(ApprovalBroker.shared.pending.count - 1)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.dpChrome.opacity(0.6))
                    }
                }

                Text(req.headline)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                ScrollView(.vertical) {
                    Text(req.detail.isEmpty ? "(no details)" : req.detail)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.dpChrome.opacity(0.9))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))

                HStack(spacing: 8) {
                    approvalButton("Deny", tint: .red) {
                        ApprovalBroker.shared.resolve(req, decision: "deny")
                    }
                    approvalButton("Ask in terminal", tint: Theme.dpChrome.opacity(0.35)) {
                        ApprovalBroker.shared.resolve(req, decision: "ask")
                    }
                    Spacer()
                    approvalButton("Allow", tint: Theme.neonCyan) {
                        ApprovalBroker.shared.resolve(req, decision: "allow")
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, menuBarInset + 8)   // clear the camera housing
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    /// A tap-gesture "button" (not SwiftUI Button) so it works inside the notch's
    /// non-key borderless window, matching how the notch already handles taps.
    private func approvalButton(_ label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Text(label)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 13).padding(.vertical, 7)
            .background(Capsule().fill(tint.opacity(0.9)))
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
                .frame(width: 6, height: 6)
                .shadow(color: Theme.statusColor(session.status).opacity(0.7), radius: 2)
            Text(session.displayTitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            HStack(spacing: 8) {
                Label(session.elapsedString, systemImage: "clock")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.dpChrome.opacity(0.75))
                Label(session.tokensString, systemImage: "circle.hexagongrid")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.neonCyan.opacity(0.85))
            }
            .labelStyle(NotchInlineLabelStyle())
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
        HStack(spacing: 3) {
            configuration.icon
                .imageScale(.small)
            configuration.title
        }
    }
}
