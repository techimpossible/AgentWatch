import SwiftUI

/// Why the mascot showed up — drives the speech bubble + accent.
enum MascotReason {
    case needsInput
    case finished

    var message: String {
        switch self {
        case .needsInput: return "needs you!"
        case .finished:   return "all done!"
        }
    }

    var tint: Color {
        switch self {
        case .needsInput: return Theme.dpGold
        case .finished:   return Theme.neonCyan
        }
    }
}

/// A cheerful original "little sponge" character (a friendly yellow square with
/// big eyes, a smile, and stubby limbs) that strolls across the bottom of the
/// screen with a speech bubble, then fades. Drawn entirely in SwiftUI — no
/// assets, and an original design (not a copy of any trademarked character).
///
/// Walk cycle: legs stride and arms swing in opposite phase while the body bobs,
/// and the whole character translates slowly from the left edge to the right.
struct MascotView: View {
    let reason: MascotReason
    var profile: String = "default"   // which Claude config profile triggered this
    let travel: CGFloat          // horizontal distance to cross (overlay width)
    let stripHeight: CGFloat     // overlay height; character sits at the bottom
    var onComplete: () -> Void = {}
    var onBurst: () -> Void = {}   // fired when the user pops it (for confetti)

    // Warm sponge-yellow body with a slightly darker outline.
    private static let body = Color(red: 0.98, green: 0.82, blue: 0.22)
    private static let outline = Color(red: 0.80, green: 0.62, blue: 0.10)

    private let bodyW: CGFloat = 40
    private let bodyH: CGFloat = 44
    private let legLength: CGFloat = 13
    private let armLength: CGFloat = 14
    private let walkDuration: Double = 24.0   // very slow stroll across the screen
    private let stepInterval: Double = 0.38    // half a stride
    private let peekRise: CGFloat = 46         // how high the peek-a-boo lifts above resting

    /// Two behaviours, driven by the reason: a finished task strolls by, a
    /// needs-input session plays peek-a-boo to grab attention.
    private enum Mode { case walk, peekaboo }
    private var mode: Mode { reason == .needsInput ? .peekaboo : .walk }

    @State private var startDate: Date? = nil     // walk start time (time-based x motion)
    @State private var startX: CGFloat = 0        // fixed horizontal spot (peekaboo)
    @State private var stride: Bool = false       // alternates legs/arms (walk)
    @State private var opacity: Double = 0
    @State private var bubbleShown = false
    @State private var jump: CGFloat = 0          // extra height during a random hop
    @State private var peek: CGFloat = 0          // how far tucked below the edge (peekaboo)
    @State private var squash: CGFloat = 0        // -1 squashed … +1 stretched

    // Click-to-inflate: each tap bounces + inflates; the 6th bursts it.
    @State private var clickCount = 0
    @State private var inflate: CGFloat = 1
    @State private var burst = false
    @State private var burstProgress: CGFloat = 0
    @State private var finished = false
    @State private var interacting = false        // user grabbed it: freeze in place
    @State private var frozenX: CGFloat? = nil     // pinned x once interacting (walk)
    @State private var dismissToken = 0            // debounce for idle auto-dismiss

    private var peekHidden: CGFloat { stripHeight + 10 }

    private var charWidth: CGFloat { bodyW * 2.0 }

    var body: some View {
        // TimelineView drives the horizontal walk from elapsed time — it's not a
        // SwiftUI-animated property, so no withAnimation (hops, fades) can ever
        // re-time it. Vertical motion (bob/hop/peek) stays on the animation engine.
        TimelineView(.animation) { context in
            character
                .scaleEffect(inflate, anchor: .bottom)
                .scaleEffect(x: 1 - squash * 0.14, y: 1 + squash * 0.14, anchor: .bottom)
                .offset(y: bob - jump + peek)
                .offset(x: currentX(now: context.date))
                .opacity(opacity)
        }
        // Anchor at the bottom-left of the strip.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .onAppear { start() }
        .task { if mode == .walk { await hopLoop() } }
    }

    // MARK: - Character

    private var character: some View {
        ZStack(alignment: .bottom) {
            if bubbleShown {
                speechBubble
                    .offset(y: -(bodyH + legLength + 16))
                    .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
            }
            ZStack(alignment: .bottom) {
                arms
                VStack(spacing: -2) {
                    spongeBody
                    legs
                }
            }
            .opacity(burst ? Double(1 - burstProgress) : 1)
            if burst { burstParticles }
        }
        .frame(width: charWidth, height: stripHeight, alignment: .bottom)
        .contentShape(Rectangle())
        // DragGesture(minimumDistance: 0) registers the press even while the
        // mascot is moving (a plain tap can miss a moving target). The press
        // freezes it in place; release counts as a click.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in beginInteract() }
                .onEnded { _ in handleTap() }
        )
    }

    /// Shards flung outward when the mascot bursts.
    private var burstParticles: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { i in
                let angle = Double(i) / 12 * 2 * .pi
                Circle()
                    .fill(i % 2 == 0 ? Self.body : Self.outline)
                    .frame(width: 7, height: 7)
                    .offset(x: CGFloat(cos(angle)) * 48 * burstProgress,
                            y: CGFloat(sin(angle)) * 48 * burstProgress - (bodyH * 0.5 + legLength))
                    .opacity(Double(1 - burstProgress))
            }
        }
    }

    /// Rounded-square sponge body with faint pores, big eyes, and a smile.
    private var spongeBody: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Self.body)
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Self.outline, lineWidth: 1.5)
                )
                .overlay(pores)

            VStack(spacing: 3) {
                HStack(spacing: 4) {
                    eye
                    eye
                }
                smile
            }
            .padding(.top, 4)
        }
        .frame(width: bodyW, height: bodyH)
        .shadow(color: Self.body.opacity(0.55), radius: 8)
        .shadow(color: reason.tint.opacity(0.40), radius: 14)
    }

    /// A few faint pores to suggest a sponge texture.
    private var pores: some View {
        ZStack {
            poreDot(dx: -10, dy: 12, d: 5)
            poreDot(dx: 9, dy: 9, d: 4)
            poreDot(dx: -6, dy: -6, d: 3.5)
            poreDot(dx: 12, dy: -3, d: 3)
            poreDot(dx: 2, dy: 15, d: 3.5)
        }
    }

    private func poreDot(dx: CGFloat, dy: CGFloat, d: CGFloat) -> some View {
        Ellipse()
            .fill(Self.outline.opacity(0.35))
            .frame(width: d, height: d * 0.8)
            .offset(x: dx, y: dy)
    }

    private var eye: some View {
        ZStack {
            Circle().fill(.white)
                .overlay(Circle().strokeBorder(Self.outline.opacity(0.7), lineWidth: 0.8))
                .frame(width: 11, height: 11)
            Circle().fill(.black.opacity(0.85))
                .frame(width: 4, height: 4)
        }
    }

    private var smile: some View {
        Path { p in
            p.addArc(center: CGPoint(x: 9, y: 0), radius: 9,
                     startAngle: .degrees(20), endAngle: .degrees(160), clockwise: false)
        }
        .stroke(Color.black.opacity(0.7), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        .frame(width: 18, height: 8)
    }

    /// Two legs that stride — one swings forward while the other swings back.
    private var legs: some View {
        HStack(spacing: 8) {
            leg(angle: stride ? 22 : -22)
            leg(angle: stride ? -22 : 22)
        }
    }

    private func leg(angle: Double) -> some View {
        Capsule()
            .fill(Self.body)
            .overlay(Capsule().strokeBorder(Self.outline.opacity(0.6), lineWidth: 1))
            .frame(width: 5, height: legLength)
            .rotationEffect(.degrees(angle), anchor: .top)
    }

    /// Two stubby arms swinging opposite to the legs, at the body's lower sides.
    private var arms: some View {
        HStack {
            arm(angle: stride ? -32 : 16)
            Spacer()
            arm(angle: stride ? 16 : -32)
        }
        .frame(width: bodyW + 10)
        .offset(y: -(legLength + bodyH * 0.32))
    }

    private func arm(angle: Double) -> some View {
        Capsule()
            .fill(Self.body)
            .overlay(Capsule().strokeBorder(Self.outline.opacity(0.6), lineWidth: 1))
            .frame(width: 4, height: armLength)
            .rotationEffect(.degrees(angle), anchor: .top)
    }

    private var speechBubble: some View {
        HStack(spacing: 6) {
            Text(profile.uppercased())
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(Theme.profileColor(profile))
            Text(reason.message)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.80))
                .overlay(Capsule().strokeBorder(Theme.profileColor(profile).opacity(0.8), lineWidth: 1.2))
        )
        .fixedSize()
    }

    // MARK: - Motion

    /// Horizontal position. For walking it's a pure function of elapsed time
    /// (linear, left edge → off the right). For peek-a-boo it's a fixed spot.
    private func currentX(now: Date) -> CGFloat {
        if let frozenX { return frozenX }       // pinned once the user grabs it
        switch mode {
        case .peekaboo:
            return startX
        case .walk:
            guard let startDate else { return -charWidth }
            let elapsed = now.timeIntervalSince(startDate)
            let p = min(1, max(0, elapsed / walkDuration))
            let start = -charWidth              // just off the left edge
            let end = travel                    // off the right edge
            return start + (end - start) * p
        }
    }

    private var bob: CGFloat { (mode == .walk && stride) ? -3 : 0 }

    // MARK: - Interaction

    /// First touch: freeze the mascot in place so the user can land all clicks.
    private func beginInteract() {
        guard !interacting, !burst, !finished else { return }
        interacting = true
        frozenX = currentX(now: Date())                 // pin horizontal position
        if mode == .peekaboo {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { peek = -peekRise }
        }
        scheduleIdleDismiss()
    }

    /// Each click bounces + inflates the mascot; the 6th pops it.
    private func handleTap() {
        guard !burst, !finished else { return }
        clickCount += 1
        if clickCount >= 6 {
            triggerBurst()
        } else {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.42)) {
                inflate = 1 + CGFloat(clickCount) * 0.18
            }
            scheduleIdleDismiss()
        }
    }

    /// If the user stops clicking without bursting it, fade away after a pause.
    private func scheduleIdleDismiss() {
        dismissToken += 1
        let token = dismissToken
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard token == dismissToken, !burst, !finished else { return }
            withAnimation(.easeIn(duration: 0.5)) { opacity = 0 }
            try? await Task.sleep(for: .milliseconds(520))
            finishOnce()
        }
    }

    private func triggerBurst() {
        burst = true
        onBurst()                                                  // screen-wide confetti
        withAnimation(.easeIn(duration: 0.16)) { inflate = 2.8 }   // final swell
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(160))
            withAnimation(.easeOut(duration: 0.5)) {
                burstProgress = 1
                inflate = 0.2
            }
            try? await Task.sleep(for: .milliseconds(520))
            finishOnce()
        }
    }

    /// Call the completion exactly once (burst, walk-off, or peek-away can race).
    private func finishOnce() {
        guard !finished else { return }
        finished = true
        onComplete()
    }

    private func start() {
        switch mode {
        case .walk:     startWalk()
        case .peekaboo: startPeekaboo()
        }
    }

    private func startWalk() {
        // Time-based horizontal motion starts now (see currentX / TimelineView).
        startDate = Date()
        withAnimation(.easeOut(duration: 0.4)) { opacity = 1 }
        // Stride cycle (legs + arms + bob).
        withAnimation(.easeInOut(duration: stepInterval).repeatForever(autoreverses: true)) {
            stride = true
        }
        // Pop the speech bubble shortly after entering.
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6).delay(0.6)) {
            bubbleShown = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(walkDuration))
            // If the user grabbed it, the idle-dismiss handles removal instead.
            guard !interacting, !burst, !finished else { return }
            withAnimation(.easeIn(duration: 0.6)) { opacity = 0 }
            try? await Task.sleep(for: .milliseconds(650))
            finishOnce()
        }
    }

    /// Peek-a-boo: pop up over the bottom edge at a fixed spot a few times, with
    /// the speech bubble, then duck away.
    private func startPeekaboo() {
        // Start tucked below the edge (no animation), at a random horizontal spot.
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) {
            startX = CGFloat.random(in: travel * 0.12 ... travel * 0.72)
            peek = peekHidden
            opacity = 1
        }
        Task { @MainActor in
            let peeks = Int.random(in: 2...3)
            for i in 0..<peeks {
                if interacting { return }   // user grabbed it — hold up; idle/burst dismiss
                // Pop up (lift well above the resting line).
                withAnimation(.spring(response: 0.36, dampingFraction: 0.58)) { peek = -peekRise }
                if i == 0 {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6).delay(0.15)) {
                        bubbleShown = true
                    }
                }
                try? await Task.sleep(for: .seconds(i == peeks - 1 ? 1.6 : 1.1))
                if interacting { return }
                // Duck down (hide the bubble on the way down too).
                if i == peeks - 1 { withAnimation(.easeIn(duration: 0.2)) { bubbleShown = false } }
                withAnimation(.easeIn(duration: 0.32)) { peek = peekHidden }
                try? await Task.sleep(for: .milliseconds(i == peeks - 1 ? 200 : 450))
            }
            if !interacting { finishOnce() }
        }
    }

    /// Hop at random intervals while walking. Cancelled automatically when the
    /// view disappears (via `.task`).
    private func hopLoop() async {
        while !Task.isCancelled {
            let delay = Double.random(in: 1.6...3.8)
            try? await Task.sleep(for: .seconds(delay))
            if Task.isCancelled { return }
            await hop()
        }
    }

    private func hop() async {
        // Anticipate (crouch), launch up with a stretch, fall, land with a squash, settle.
        withAnimation(.easeOut(duration: 0.10)) { squash = -0.45 }
        try? await Task.sleep(for: .milliseconds(100))
        withAnimation(.easeOut(duration: 0.22)) { jump = 26; squash = 0.55 }
        try? await Task.sleep(for: .milliseconds(220))
        withAnimation(.easeIn(duration: 0.20)) { jump = 0 }
        withAnimation(.easeOut(duration: 0.14)) { squash = -0.4 }
        try? await Task.sleep(for: .milliseconds(150))
        withAnimation(.spring(response: 0.26, dampingFraction: 0.5)) { squash = 0 }
    }
}
