import AppKit
import Combine
import Observation
import SwiftUI

/// Owns the menu-bar status item for AgentWatch.
/// Left-click toggles the SwiftUI popover. Right-click shows an NSMenu with Quit etc.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let rightClickMenu: NSMenu

    /// Holds the @Observable subscription so the status icon refreshes when state changes.
    private var observationCancellable: Task<Void, Never>?

    init(state: AppState) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let pop = NSPopover()
        pop.behavior = .transient   // dismisses on click-outside
        pop.animates = false        // avoid the system bounce on every open
        // Fixed width, auto height: the hosting controller reports its SwiftUI
        // content's fitting size so the popover grows to show every session
        // (and profile group) instead of clipping at a hardcoded height.
        let host = NSHostingController(
            rootView: MenuBarContent().frame(width: 400).environment(state)
        )
        host.sizingOptions = [.preferredContentSize]
        pop.contentViewController = host
        self.popover = pop

        self.rightClickMenu = NSMenu()
        super.init()

        pop.delegate = self
        configureButton()
        buildRightClickMenu()
        observeState(state)
        refreshIcon(state: state)
    }

    deinit {
        observationCancellable?.cancel()
    }

    // MARK: - Status item button

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(handleButtonClick(_:))
        // Receive both left and right mouse-up so we can branch on event type.
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func handleButtonClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showRightClickMenu()
        } else {
            togglePopover(sender)
        }
    }

    private func showRightClickMenu() {
        guard let button = statusItem.button else { return }
        // popUpMenu shows the menu at the button location and consumes the click
        // so we don't also fire the popover.
        statusItem.menu = rightClickMenu
        button.performClick(nil)
        // Detach the menu after click so the next left-click goes to popover again.
        statusItem.menu = nil
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
            // Bring our app forward so the popover gets focus.
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// External entry point for the notch UI: opens the popover anchored to the
    /// status item, so the visual is identical to a left-click on the icon.
    func togglePopoverFromExternal() {
        guard let button = statusItem.button else { return }
        togglePopover(button)
    }

    // MARK: - Right-click menu

    private func buildRightClickMenu() {
        let m = rightClickMenu

        let refresh = NSMenuItem(title: "Refresh now", action: #selector(menuRefresh), keyEquivalent: "")
        refresh.target = self
        m.addItem(refresh)

        m.addItem(.separator())

        let history = NSMenuItem(title: "History…", action: #selector(menuOpenHistory), keyEquivalent: "")
        history.target = self
        m.addItem(history)

        let search = NSMenuItem(title: "Search…", action: #selector(menuOpenSearch), keyEquivalent: "")
        search.target = self
        m.addItem(search)

        let costs = NSMenuItem(title: "Costs…", action: #selector(menuOpenCosts), keyEquivalent: "")
        costs.target = self
        m.addItem(costs)

        m.addItem(.separator())

        let demo = NSMenuItem(title: "Run mascot demo 🎉", action: #selector(menuMascotDemo), keyEquivalent: "")
        demo.target = self
        m.addItem(demo)

        m.addItem(.separator())

        let loginItem = NSMenuItem(title: "Launch at login", action: #selector(menuToggleLoginItem), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = LoginItem.isEnabled ? .on : .off
        m.addItem(loginItem)

        m.addItem(.separator())

        let about = NSMenuItem(title: "About AgentWatch", action: #selector(menuAbout), keyEquivalent: "")
        about.target = self
        m.addItem(about)

        let quit = NSMenuItem(title: "Quit AgentWatch", action: #selector(menuQuit), keyEquivalent: "q")
        quit.target = self
        m.addItem(quit)
    }

    @objc private func menuRefresh() {
        Task { await AppState.shared.refresh() }
    }
    @objc private func menuOpenHistory() {
        openWindow(id: "history")
    }
    @objc private func menuOpenSearch() {
        openWindow(id: "search")
    }
    @objc private func menuOpenCosts() {
        openWindow(id: "costs")
    }
    @objc private func menuMascotDemo() {
        // Showcase the mascot without waiting for a real session event:
        // a "finished" walk-by, which also rains confetti.
        MascotOverlayController.shared?.show(reason: .finished, profile: "demo")
    }
    @objc private func menuToggleLoginItem(_ sender: NSMenuItem) {
        let now = LoginItem.isEnabled
        if let actual = LoginItem.setEnabled(!now) {
            sender.state = actual ? .on : .off
        }
    }
    @objc private func menuAbout() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }
    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }

    private func openWindow(id: String) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Re-use the SwiftUI window-id mechanism via URL scheme would be cleaner,
        // but the simplest reliable hook is to post a notification the SwiftUI side
        // listens on. We instead poke the SwiftUI environment by opening the URL.
        // For id-based windows, AppKit can call NSDocumentController... easiest:
        // forward to the SwiftUI openWindow action through a shared environment hook.
        WindowOpener.shared.open(id: id)
    }

    // MARK: - Observe AppState to refresh the icon

    private func observeState(_ state: AppState) {
        observationCancellable?.cancel()
        observationCancellable = Task { @MainActor [weak self] in
            var lastCount = -1
            var lastNeed = false
            var lastWork = false
            while !Task.isCancelled {
                guard let self else { return }
                let count = state.sessions.count
                let need  = state.sessions.contains { $0.status == .needsInput }
                let work  = state.sessions.contains { $0.status == .working }
                if count != lastCount || need != lastNeed || work != lastWork {
                    self.refreshIcon(state: state)
                    lastCount = count; lastNeed = need; lastWork = work
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func refreshIcon(state: AppState) {
        guard let button = statusItem.button else { return }
        let symbol: String
        let color: NSColor
        if state.sessions.contains(where: { $0.status == .needsInput }) {
            symbol = "exclamationmark.circle.fill"
            color = NSColor(Theme.dpGold)
        } else if state.sessions.contains(where: { $0.status == .working }) {
            symbol = "circle.fill"
            color = NSColor(Theme.neonCyan)
        } else {
            symbol = "circle.dotted"
            color = NSColor.secondaryLabelColor
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "AgentWatch")
        let config = NSImage.SymbolConfiguration(paletteColors: [color])
        button.image = image?.withSymbolConfiguration(config)
        button.title = state.sessions.isEmpty ? "" : " \(state.sessions.count)"
        button.imagePosition = .imageLeading
    }
}

/// Tiny shim so AppKit-managed menu items can ask SwiftUI to open id-based Windows.
@MainActor
final class WindowOpener: ObservableObject {
    static let shared = WindowOpener()
    @Published var pendingOpen: String?

    func open(id: String) {
        pendingOpen = id
    }
}
