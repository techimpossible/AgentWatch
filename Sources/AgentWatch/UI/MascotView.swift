import AppKit
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
        case .needsInput: return Theme.accent       // coral — "your turn"
        case .finished:   return Theme.accentGreen   // green — done
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

    /// Which persona walks this time — the selected default, else a random pick
    /// from the catalog (drawn built-ins + bundled + user-uploaded images).
    /// `DrawnKind` / `MascotPersona` live in MascotCatalog.
    @State private var persona: MascotPersona = MascotCatalog.shared.pick()

    /// The drawn kind for this appearance, or nil when it's an image persona.
    private var drawnKind: DrawnKind? {
        if case .drawn(let k) = persona { return k }
        return nil
    }
    /// True when this appearance is a bundled image rather than a drawn character.
    private var isImage: Bool {
        if case .image = persona { return true }
        return false
    }

    /// Body + outline colours for the drawn characters (they also tint the burst
    /// shards). Image personas fall back to a neutral pair.
    private var bodyColor: Color {
        switch persona {
        case .drawn(.sponge): return Color(red: 0.98, green: 0.82, blue: 0.22)
        case .drawn(.robot):  return Color(red: 0.64, green: 0.68, blue: 0.74)
        case .drawn(.blob):   return Color(red: 0.62, green: 0.50, blue: 0.96)
        case .image:          return Color(red: 0.55, green: 0.70, blue: 0.45)
        }
    }
    private var outlineColor: Color {
        switch persona {
        case .drawn(.sponge): return Color(red: 0.80, green: 0.62, blue: 0.10)
        case .drawn(.robot):  return Color(red: 0.30, green: 0.34, blue: 0.40)
        case .drawn(.blob):   return Color(red: 0.36, green: 0.28, blue: 0.62)
        case .image:          return Color(red: 0.30, green: 0.42, blue: 0.24)
        }
    }

    /// Size for image personas (drawn characters use bodyW/bodyH).
    private let imageSize: CGFloat = 96

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
    @State private var appearDate = Date()        // drives the continuous groove + dance clock
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

    private var charWidth: CGFloat { max(bodyW * 2.0, imageSize) }

    var body: some View {
        // TimelineView drives the horizontal walk from elapsed time — it's not a
        // SwiftUI-animated property, so no withAnimation (hops, fades) can ever
        // re-time it. Vertical motion (bob/hop/peek) stays on the animation engine.
        TimelineView(.animation) { context in
            character(now: context.date)
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

    private func character(now: Date) -> some View {
        ZStack(alignment: .bottom) {
            if bubbleShown { bubbleOrChip }
            creatureBody(now: now)
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

    /// The bubble above the mascot: drawn characters use the reason/profile speech
    /// bubble; image personas may carry their own bubble in the art, so they get a
    /// small profile chip instead.
    @ViewBuilder private var bubbleOrChip: some View {
        if isImage {
            imageProfileChip
                .offset(y: -(imageSize + 4))
                .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
        } else {
            speechBubble
                .offset(y: -(bodyH + legLength + 16))
                .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
        }
    }

    /// The character for this appearance. Drawn kinds share the striding legs +
    /// swinging arms; an image persona is a self-contained picture — multi-frame
    /// ones dance through their frames, single-frame ones waddle.
    @ViewBuilder private func creatureBody(now: Date) -> some View {
        switch persona {
        case .image(let frames):
            imageBody(frames, now: now)
        case .drawn:
            ZStack(alignment: .bottom) {
                arms
                VStack(spacing: -2) {
                    drawnBody
                    legs
                }
            }
        }
    }

    @ViewBuilder private var drawnBody: some View {
        switch persona {
        case .drawn(.robot): robotBody
        case .drawn(.blob):  blobBody
        default:             spongeBody
        }
    }

    // MARK: - Dance timing (multi-frame image mascots)

    private let beatInterval: Double = 0.55           // dance tempo — seconds per pose
    private let moonwalkDuration: Double = 1.8        // one mid-crossing moonwalk interlude
    private let moonwalkSlideDistance: CGFloat = 140  // backward glide during the interlude
    private let moonwalkStartFraction: Double = 0.45  // where in the crossing it happens

    /// When the single moonwalk interlude begins (walk mode, 3+ frames).
    private var moonwalkStart: Double { walkDuration * moonwalkStartFraction }

    /// How much of the interlude has elapsed by time t (0…moonwalkDuration).
    private func moonwalkOverlap(_ elapsed: Double) -> Double {
        min(max(elapsed - moonwalkStart, 0), moonwalkDuration)
    }

    /// 0…1 opacity blend into the moonwalk frame, smoothstepped over 0.3s edges.
    private func moonwalkBlend(_ elapsed: Double) -> CGFloat {
        let u = elapsed - moonwalkStart
        guard u > 0, u < moonwalkDuration else { return 0 }
        let e = min(min(u, moonwalkDuration - u) / 0.3, 1)
        return CGFloat(e * e * (3 - 2 * e))
    }

    /// Current pose, next pose, and the crossfade amount into it (0…1, ramping
    /// through the last quarter of each beat) — pure function of the pose clock.
    private func danceFrame(clock: Double, poses: Int) -> (cur: Int, next: Int, fade: CGFloat) {
        let t = clock.truncatingRemainder(dividingBy: beatInterval * Double(poses))
        let i = min(Int(t / beatInterval), poses - 1)
        let f = (t - Double(i) * beatInterval) / beatInterval
        let raw = f > 0.75 ? CGFloat((f - 0.75) / 0.25) : 0
        return (i, (i + 1) % poses, raw * raw * (3 - 2 * raw))  // smoothstep
    }

    /// Image persona. Multi-frame mascots dance-stroll: poses crossfade on the
    /// beat while a continuous sine groove rocks the body. With 3+ frames in
    /// walk mode, the LAST frame is the moonwalk — shown once, mid-crossing,
    /// while `danceX` glides backward; the pose clock pauses underneath it and
    /// the groove flattens so the glide reads as one smooth move. Single-frame
    /// mascots keep the gentle waddle.
    private func imageBody(_ frames: [NSImage], now: Date) -> some View {
        let elapsed = now.timeIntervalSince(appearDate)
        let animated = frames.count > 1
        let hasMoonwalk = mode == .walk && frames.count >= 3
        let poses = hasMoonwalk ? frames.count - 1 : frames.count
        // Pose clock pauses while the moonwalk interlude plays.
        let clock = hasMoonwalk ? elapsed - moonwalkOverlap(elapsed) : elapsed
        let (cur, next, fade) = animated
            ? danceFrame(clock: clock, poses: poses)
            : (0, 0, 0)
        let moon = hasMoonwalk ? moonwalkBlend(elapsed) : 0
        // Groove flattens during the glide; lean back slightly instead.
        let sway = animated ? sin(clock * .pi / beatInterval) * Double(1 - moon) : 0
        return ZStack {
            Image(nsImage: frames[cur]).resizable().scaledToFit()
                .opacity(Double((1 - fade) * (1 - moon)))
            Image(nsImage: frames[next]).resizable().scaledToFit()
                .opacity(Double(fade * (1 - moon)))
            if hasMoonwalk {
                Image(nsImage: frames[frames.count - 1]).resizable().scaledToFit()
                    .opacity(Double(moon))
            }
        }
        .frame(width: imageSize, height: imageSize)
        .rotationEffect(.degrees(animated ? sway * 5 - Double(moon) * 4 : (stride ? 3 : -3)),
                        anchor: .bottom)
        .scaleEffect(x: 1 + abs(sway) * 0.03, y: 1 - abs(sway) * 0.05, anchor: .bottom)
        .offset(y: -abs(sway) * 4)
        .shadow(color: reason.tint.opacity(0.30), radius: 12)
    }

    /// Horizontal dance travel: a steady stroll across the screen with ONE
    /// moonwalk interlude mid-crossing — forward motion eases out, the mascot
    /// glides smoothly backward, then the stroll resumes. Forward speed is
    /// solved so the crossing still completes in `walkDuration`.
    private func danceX(elapsed: Double, frames: Int) -> CGFloat {
        let span = travel + charWidth
        // Steady speed covering the span plus the backslide, minus glide time.
        let v = (span + moonwalkSlideDistance) / CGFloat(walkDuration - moonwalkDuration)
        let u = moonwalkOverlap(elapsed)                    // 0…moonwalkDuration
        let p = u / moonwalkDuration                        // glide progress 0…1
        let glide = CGFloat(p * p * (3 - 2 * p))            // smoothstep: ease out + back in
        let forward = v * CGFloat(elapsed - u)              // stroll pauses during the glide
        return -charWidth + forward - moonwalkSlideDistance * glide
    }

    /// Boxy robot: square eyes, a straight mouth, and a little antenna.
    private var robotBody: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(bodyColor)
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(outlineColor, lineWidth: 1.5))
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 1).fill(.black.opacity(0.8)).frame(width: 6, height: 6)
                    RoundedRectangle(cornerRadius: 1).fill(.black.opacity(0.8)).frame(width: 6, height: 6)
                }
                RoundedRectangle(cornerRadius: 1).fill(outlineColor).frame(width: 14, height: 2.5)
            }
        }
        .frame(width: bodyW, height: bodyH)
        .overlay(alignment: .top) {
            ZStack {
                Capsule().fill(outlineColor).frame(width: 2, height: 8)
                Circle().fill(reason.tint).frame(width: 5, height: 5).offset(y: -6)
            }
            .offset(y: -7)
        }
        .shadow(color: bodyColor.opacity(0.5), radius: 8)
        .shadow(color: reason.tint.opacity(0.30), radius: 12)
    }

    /// Rounded blob with two big eyes.
    private var blobBody: some View {
        ZStack {
            Ellipse()
                .fill(bodyColor)
                .overlay(Ellipse().strokeBorder(outlineColor, lineWidth: 1.5))
            HStack(spacing: 5) { eye; eye }.offset(y: -2)
        }
        .frame(width: bodyW, height: bodyH)
        .shadow(color: bodyColor.opacity(0.5), radius: 8)
        .shadow(color: reason.tint.opacity(0.30), radius: 12)
    }

    /// Small profile pill for image personas (whose art may include a bubble).
    private var imageProfileChip: some View {
        Text(profile.uppercased())
            .font(.system(size: 10, weight: .heavy, design: .monospaced))
            .tracking(0.5)
            .foregroundStyle(Theme.profileColor(profile))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Theme.surfaceRaised)
                    .overlay(Capsule().strokeBorder(Theme.profileColor(profile).opacity(0.65), lineWidth: 1))
            )
            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
            .fixedSize()
    }

    /// Shards flung outward when the mascot bursts.
    private var burstParticles: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { i in
                let angle = Double(i) / 12 * 2 * .pi
                Circle()
                    .fill(i % 2 == 0 ? bodyColor : outlineColor)
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
                .fill(bodyColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(outlineColor, lineWidth: 1.5)
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
        .shadow(color: bodyColor.opacity(0.55), radius: 8)
        .shadow(color: reason.tint.opacity(0.30), radius: 12)
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
            .fill(outlineColor.opacity(0.35))
            .frame(width: d, height: d * 0.8)
            .offset(x: dx, y: dy)
    }

    private var eye: some View {
        ZStack {
            Circle().fill(.white)
                .overlay(Circle().strokeBorder(outlineColor.opacity(0.7), lineWidth: 0.8))
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
            .fill(bodyColor)
            .overlay(Capsule().strokeBorder(outlineColor.opacity(0.6), lineWidth: 1))
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
            .fill(bodyColor)
            .overlay(Capsule().strokeBorder(outlineColor.opacity(0.6), lineWidth: 1))
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
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Theme.surfaceRaised)
                .overlay(Capsule().strokeBorder(Theme.profileColor(profile).opacity(0.65), lineWidth: 1.2))
        )
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        .fixedSize()
    }

    // MARK: - Motion

    /// Horizontal position. For walking it's a pure function of elapsed time —
    /// linear for drawn/single-image mascots, dance travel (forward scoots +
    /// backward moonwalk glides) for multi-frame ones. Peek-a-boo is a fixed spot.
    private func currentX(now: Date) -> CGFloat {
        if let frozenX { return frozenX }       // pinned once the user grabs it
        switch mode {
        case .peekaboo:
            return startX
        case .walk:
            guard let startDate else { return -charWidth }
            let elapsed = min(now.timeIntervalSince(startDate), walkDuration)
            if case .image(let frames) = persona, frames.count >= 3 {
                return danceX(elapsed: elapsed, frames: frames.count)
            }
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
        appearDate = Date()
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
