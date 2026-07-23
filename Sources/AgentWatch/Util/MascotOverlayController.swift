import AppKit
import SwiftUI

/// Hosts a transparent, click-through window strip across the top of the main
/// screen and walks the mascot across it when a session needs attention.
@MainActor
final class MascotOverlayController {
    static private(set) var shared: MascotOverlayController?

    private static let enabledKey = "mascotEnabled"

    /// User toggle (default on). Persisted in UserDefaults.
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    private let stripHeight: CGFloat = 280   // tall enough for the inflate/burst to grow without clipping
    private var window: NSWindow?
    private var isShowing = false
    private var confettiWindow: NSWindow?

    init() {
        MascotOverlayController.shared = self
        DebugLog.write("mascot: controller ready")
    }

    /// Walk the mascot across the screen for `reason`, labelled with the session's
    /// `profile`. No-op if disabled, if a walk is already in progress, or if
    /// there's no screen.
    func show(reason: MascotReason, profile: String) {
        guard MascotOverlayController.isEnabled else {
            DebugLog.write("mascot: disabled — skip")
            return
        }
        guard !isShowing else {
            DebugLog.write("mascot: already walking — skip")
            return
        }
        guard let screen = NSScreen.main else { return }
        isShowing = true

        // Sit at the bottom of the screen, just above the Dock (visibleFrame.minY
        // is the top of the Dock when present, else the screen's bottom edge).
        let frame = NSRect(
            x: screen.frame.minX,
            y: screen.visibleFrame.minY,
            width: screen.frame.width,
            height: stripHeight
        )

        let w = window ?? makeWindow(frame: frame)
        w.setFrame(frame, display: false)

        let travel = screen.frame.width
        w.contentView = ClickThroughHostingView(
            rootView: MascotView(
                reason: reason,
                profile: profile,
                travel: travel,
                stripHeight: stripHeight,
                onComplete: { [weak self] in self?.finish() },
                onBurst: { [weak self] in self?.celebrate() }
            )
            .environment(\.colorScheme, .dark)
        )
        w.orderFrontRegardless()
        self.window = w
        DebugLog.write("mascot: walking (\(reason)) across width=\(travel)")

        // A finished task is a celebration — rain confetti as it strolls in.
        if reason == .finished { celebrate() }
    }

    private func finish() {
        window?.orderOut(nil)
        isShowing = false
        DebugLog.write("mascot: done")
    }

    /// Rain confetti over the whole screen (triggered when the mascot bursts).
    private func celebrate() {
        guard let screen = NSScreen.main else { return }
        DebugLog.write("mascot: confetti!")
        let w = confettiWindow ?? makeConfettiWindow(frame: screen.frame)
        w.setFrame(screen.frame, display: false)
        w.contentView = NSHostingView(
            rootView: ConfettiView(onDone: { [weak self] in
                self?.confettiWindow?.orderOut(nil)
            })
            .environment(\.colorScheme, .dark)
        )
        w.orderFrontRegardless()
        confettiWindow = w
    }

    private func makeConfettiWindow(frame: NSRect) -> NSWindow {
        let w = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.level = .statusBar
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true   // confetti must never block clicks
        w.isReleasedWhenClosed = false
        return w
    }

    private func makeWindow(frame: NSRect) -> NSWindow {
        let w = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        w.level = .statusBar
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        // Fully click-through. The strip spans the whole width of the screen, so
        // if it intercepted mouse events it would swallow clicks/typing meant for
        // the window behind it (e.g. an editor in the bottom band). A decorative
        // overlay must never steal input, so it ignores mouse events entirely.
        // (The click-to-inflate/burst interaction in MascotView is therefore unreachable.)
        w.ignoresMouseEvents = true
        w.isMovable = false
        w.isReleasedWhenClosed = false
        return w
    }
}

/// Hosting view that accepts the first click even when AgentWatch is in the
/// background — otherwise macOS swallows the click to activate the app and the
/// mascot's tap gesture never fires.
private final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
