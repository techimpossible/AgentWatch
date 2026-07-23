import AppKit
import Combine
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// Owns the menu-bar status item for AgentWatch.
/// Left-click toggles the SwiftUI popover. Right-click shows an NSMenu with Quit etc.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let rightClickMenu: NSMenu
    /// Submenu of selectable mascots — rebuilt each time it opens (see menuNeedsUpdate).
    private let mascotMenu = NSMenu(title: "Mascot")
    /// Submenu to enable/disable in-app tool approvals per profile — rebuilt on open.
    private let approvalsMenu = NSMenu(title: "Approvals")

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

        let mascot = NSMenuItem(title: "Mascot", action: nil, keyEquivalent: "")
        mascotMenu.delegate = self          // rebuilt on open so new uploads appear
        mascot.submenu = mascotMenu
        m.addItem(mascot)

        let demo = NSMenuItem(title: "Run mascot demo 🎉", action: #selector(menuMascotDemo), keyEquivalent: "")
        demo.target = self
        m.addItem(demo)

        m.addItem(.separator())

        let approvals = NSMenuItem(title: "Approvals (beta)", action: nil, keyEquivalent: "")
        approvalsMenu.delegate = self       // rebuilt on open to reflect install state
        approvals.submenu = approvalsMenu
        m.addItem(approvals)

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

    // MARK: - Mascot submenu

    /// Rebuild whichever submenu is opening so it always reflects current state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === mascotMenu { rebuildMascotMenu(menu) }
        else if menu === approvalsMenu { rebuildApprovalsMenu(menu) }
    }

    private func rebuildMascotMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let selected = MascotCatalog.shared.selectionID

        let random = NSMenuItem(title: "Random (all)", action: #selector(menuSelectMascot(_:)), keyEquivalent: "")
        random.target = self
        random.representedObject = nil          // nil => random rotation
        random.state = (selected == nil) ? .on : .off
        menu.addItem(random)
        menu.addItem(.separator())

        for item in MascotCatalog.shared.items() {
            let mi = NSMenuItem(title: item.name, action: #selector(menuSelectMascot(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = item.id
            mi.state = (selected == item.id) ? .on : .off
            if case .image(let url) = item.source, let img = NSImage(contentsOf: url) {
                let thumb = NSImage(size: NSSize(width: 18, height: 18))
                thumb.lockFocus()
                img.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
                thumb.unlockFocus()
                mi.image = thumb
            }
            menu.addItem(mi)
        }

        menu.addItem(.separator())
        let add = NSMenuItem(title: "Add Mascot from File…", action: #selector(menuAddMascot), keyEquivalent: "")
        add.target = self
        menu.addItem(add)
        let openDir = NSMenuItem(title: "Open Mascots Folder…", action: #selector(menuOpenMascotsFolder), keyEquivalent: "")
        openDir.target = self
        menu.addItem(openDir)
    }

    @objc private func menuSelectMascot(_ sender: NSMenuItem) {
        MascotCatalog.shared.selectionID = sender.representedObject as? String
        // Immediately show the pick so the choice is visible.
        MascotOverlayController.shared?.show(reason: .finished, profile: "demo")
    }

    @objc private func menuAddMascot() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Add Mascot"
        panel.message = "Choose an image to use as a mascot. A square, transparent PNG works best."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let id = MascotCatalog.shared.addMascot(from: url) {
            MascotCatalog.shared.selectionID = id     // select the freshly added one
            MascotOverlayController.shared?.show(reason: .finished, profile: "demo")
        } else {
            let alert = NSAlert()
            alert.messageText = "Couldn't add that image"
            alert.informativeText = "AgentWatch couldn't read that file as an image. Try a PNG."
            alert.runModal()
        }
    }

    @objc private func menuOpenMascotsFolder() {
        NSWorkspace.shared.open(MascotCatalog.shared.userMascotsDir)
    }

    // MARK: - Approvals submenu

    private func rebuildApprovalsMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let header = NSMenuItem(title: "Approve tool calls in AgentWatch", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let profiles = Array(Set(ClaudeHome.roots.map { $0.profile })).sorted()
        if profiles.isEmpty {
            let none = NSMenuItem(title: "No profiles found", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        } else {
            for profile in profiles {
                let mi = NSMenuItem(title: profile, action: #selector(menuToggleApproval(_:)), keyEquivalent: "")
                mi.target = self
                mi.representedObject = profile
                mi.state = ApprovalHookInstaller.isInstalled(profile: profile) ? .on : .off
                menu.addItem(mi)
            }
        }

        menu.addItem(.separator())
        let note = NSMenuItem(title: "Installs a PreToolUse hook. Restart the Claude session to take effect.",
                              action: nil, keyEquivalent: "")
        note.isEnabled = false
        menu.addItem(note)
    }

    @objc private func menuToggleApproval(_ sender: NSMenuItem) {
        guard let profile = sender.representedObject as? String else { return }
        if ApprovalHookInstaller.isInstalled(profile: profile) {
            ApprovalHookInstaller.uninstall(profile: profile)
        } else {
            ApprovalHookInstaller.install(profile: profile)
        }
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
        // Lightweight in-memory change detector: it only reads already-scanned
        // session state (no ps/file I/O), so its 1s cadence stays independent of
        // AppState's adaptive polling and keeps the icon responsive when state
        // changes between scans.
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
        // Warm Glass status palette: coral = "your turn", blue = working,
        // mid gray = everything else. Coral appears only for needs-input.
        let symbol: String
        let color: NSColor
        if state.sessions.contains(where: { $0.status == .needsInput }) {
            symbol = "exclamationmark.circle.fill"
            color = NSColor(Theme.accent)            // coral — the one attention color
        } else if state.sessions.contains(where: { $0.status == .working }) {
            symbol = "circle.fill"
            color = NSColor(Theme.accentBlue)        // calm blue — working
        } else {
            symbol = "circle.dotted"
            color = NSColor(Theme.idle)              // mid gray — idle, recedes
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
