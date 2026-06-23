# Installing AgentWatch (internal build)

This is an internal build of AgentWatch — a native menu-bar dashboard for Claude Code sessions. It's **ad-hoc signed**, not signed with an Apple Developer ID, so the first launch needs one extra step to satisfy macOS Gatekeeper. After that, it just works.

Apple Silicon Mac on macOS 26 (Tahoe) or later is required.

## Install

1. **Download** `AgentWatch-vX.Y.Z.dmg` (link in Slack / GitHub release).
2. **Double-click the DMG.** A Finder window opens with the AgentWatch icon and an Applications shortcut.
3. **Drag `AgentWatch.app` onto the Applications shortcut.** This installs it to `/Applications`.
4. **Eject the DMG** — drag it to the Trash or right-click → Eject.

## First launch (the Gatekeeper dance — one time only)

Because the build isn't signed by an Apple-notarized Developer ID, the **first** double-click will fail with:

> *"AgentWatch.app" cannot be opened because Apple cannot check it for malicious software.*

This is expected. To get past it once:

**Option A — right-click → Open** (Finder)
1. In `/Applications`, **right-click** (or two-finger click) on `AgentWatch.app`.
2. Choose **Open** from the menu.
3. macOS shows the same warning but now with an **Open** button. Click it.
4. Done. Subsequent double-clicks open it normally.

**Option B — System Settings**
1. Try to open AgentWatch normally. macOS will refuse.
2. Open **System Settings → Privacy & Security**.
3. Scroll to the bottom — you'll see *"AgentWatch was blocked from use…"* with an **Open Anyway** button.
4. Click it, then re-open AgentWatch. Done.

**Option C — Terminal (technical users)**
```sh
xattr -dr com.apple.quarantine /Applications/AgentWatch.app
```
Removes the quarantine attribute. After that, AgentWatch opens normally on double-click.

## What you should see after first launch

- A small icon appears at the top-right of your menu bar — a hollow circle if no Claude Code sessions are running, or a filled cyan dot with a count if there are.
- Click the icon to see the popover: live sessions, History, Search, and Costs buttons.
- No Dock icon, no main window — it's a background menu-bar utility.

## Optional: Launch at login

In the popover footer there's a **LAUNCH AT LOGIN** toggle. Flip it on if you want AgentWatch to start automatically when you log in. macOS will register it as a login item; you can also manage this in **System Settings → General → Login Items & Extensions**.

## Updating

There's no auto-update mechanism. When a new version is available:
1. Quit the running AgentWatch (popover → QUIT).
2. Drag the new `.app` from the new DMG onto Applications, replacing the old copy.
3. Re-launch.

(If you ever skipped the right-click → Open dance for the new version, you may see the Gatekeeper warning again — same fix.)

## What it can do

- **Live session list**: every running `claude` process, with status (working / idle / needs input).
- **Open terminal**: ↗ button on each row brings the host terminal app to the front.
- **Transcript viewer**: click any session to see its full conversation.
- **History**: every past session, with one-click resume (`claude --resume <id>` in a new Terminal window) or reveal-in-Finder.
- **Search**: substring search across every transcript on disk.
- **Costs**: per-day / per-project / per-model token spend at Anthropic published rates.
  - Note: if you route Claude Code through a proxy or gateway, your actual billing differs from these estimates.
- **Notification** when any session transitions to "needs input".

## What it does not do

- No network sockets are ever opened. No telemetry, no update check, no analytics.
- No CLI, no HTTP/WebSocket server, no IPC of any kind.
- No data is sent off your Mac.

## Trust posture (read this once)

This is a self-built, ad-hoc-signed binary distributed internally. It's not notarized by Apple, so macOS can't certify the developer identity. You're trusting the team that built it. The source is auditable in `~/Documents/Github/AgentWatch` (or the internal repo) — ~1,500 lines of Swift, no third-party dependencies.

If you want to verify the running app has zero network activity yourself:
```sh
lsof -nP -iTCP -iUDP | awk -v p=$(pgrep -x AgentWatch) 'NR==1 || $2==p'
```
The output should show only the header row — AgentWatch holds no sockets.

## Uninstall

1. Quit AgentWatch (popover → QUIT).
2. Drag `/Applications/AgentWatch.app` to the Trash.
3. (Optional) Remove the system-managed preference: `defaults delete com.techimpossible.agentwatch`
4. (Optional) If you registered for Launch at Login, unregister via **System Settings → General → Login Items & Extensions**.

AgentWatch never wrote anything to `~/.claude/` — it's strictly read-only against your Claude Code data — so there's nothing to clean up there.

## Trouble?

Ping the channel where you got the DMG link. Common questions:
- *"It says the developer cannot be verified"* — see [First launch](#first-launch-the-gatekeeper-dance--one-time-only) above.
- *"The icon doesn't appear in my menu bar"* — your menu bar may be full; try collapsing other status items, or look near the time/Wi-Fi icons.
- *"Notifications don't fire"* — macOS notification permission may not have been granted; check **System Settings → Notifications → AgentWatch**.
