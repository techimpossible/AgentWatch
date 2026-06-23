# AgentWatch

A native Swift menu bar app for monitoring Claude Code sessions on macOS. Zero third-party dependencies, no HTTP/WebSocket server, and no CLI — it only reads your local Claude session files.

Bundle ID: `com.techimpossible.agentwatch` · macOS 26 (Tahoe)+ · Apple silicon.

> **Unofficial.** AgentWatch is not affiliated with, authorized, or endorsed by
> Anthropic. "Claude" and "Claude Code" are trademarks of Anthropic. This is a
> personal project shared **as-is** — issues and pull requests are welcome, but
> there's no support guarantee or release cadence.

## Screenshots

<!-- Drop images into docs/ and uncomment:
![Menu bar popover](docs/popover.png)
![Cost dashboard](docs/costs.png)
![Notch panel + mascot](docs/notch.png)
-->

_Screenshots coming soon. Tip: trigger the mascot/confetti yourself via the menu-bar icon → right-click → **Run mascot demo 🎉**._

## What it does

- **Live session list** in the menu bar. Auto-discovers running `claude` processes and shows status (working / idle / needs input).
- **Multiple profiles.** Discovers every `CLAUDE_CONFIG_DIR` (e.g. `~/.config/claude-*`) alongside the default `~/.claude`, and groups/labels sessions by profile across the popover, History, Search, and Costs.
- **Session actions.** Resume in a new terminal, copy the resume command, copy an `agentwatch://` deep link, bring the live terminal to front, or stop (kill) a session — right from the popover.
- **Favourites.** Star any session to pin it to the top of the list; filter History to favourites only.
- **Transcript viewer**. Click any session to open its full conversation in a separate window.
- **History browser.** Browse every past session across all profiles; filter by project / first prompt / session id, then resume, reveal in Finder, copy the first prompt, or open the transcript.
- **Full-text search** across the *contents* of every session under all discovered profiles, with per-hit profile labels and one-click jump to the transcript, resume command, or deep link.
- **Cost dashboard**. By-profile / per-project / per-model / daily breakdowns of token spend at Anthropic published rates. Disclaimer for proxy/gateway users since billing may differ.
- **Notch panel + mascot.** A Dynamic-Island-style panel (with a pulsing glow) on notched Macs, and an optional character that strolls across on task completion — raining confetti — or peeks up when a session needs input. Click it to make it bounce and inflate; a sixth click pops it into confetti. Toggle it off in the popover.
- **`agentwatch://` URL scheme.** Deep links (e.g. from notes or a task tracker) reopen a session in a terminal.
- **Notifications** when a session transitions into "needs input" (with a 30 s per-session cooldown).
- **Settings** in the popover footer: launch at login, and mascot on/off.

## What it deliberately does not do

- No HTTP server. No WebSocket. No CLI. No IPC of any kind. No network sockets ever opened.
- No telemetry. No analytics. No update check.
- No subagent tree view.
- No third-party Swift packages. Foundation, SwiftUI, AppKit, UserNotifications, OSLog only.

## Build

Requires Swift 6.0+ (Command Line Tools is enough — no full Xcode needed).

```sh
./build.sh                  # produces AgentWatch.app
./build.sh --run            # build + launch in place
./build.sh --install        # build + copy to ~/Applications/AgentWatch.app
./build.sh --install-system # build + copy to /Applications/AgentWatch.app (needs sudo)
```

The build script ad-hoc signs the bundle with `codesign -s -`, which is sufficient for personal use on macOS Sequoia/Tahoe. Notarization is **not** performed — the app is intended for self-build only.

## Audit notes

The codebase is intentionally small (~25 Swift files, ~1,500 lines) so it can be read end-to-end in under an hour.

**Files AgentWatch reads at runtime, and only these:**

| Path | When |
|---|---|
| `~/.claude/sessions/*.json` | Every 3 s polling cycle |
| `~/.claude/projects/*/` | Directory listing on Costs/Search compute |
| `~/.claude/projects/*/*.jsonl` | On-demand: transcript open, Costs/Search refresh |

**Files AgentWatch never reads:** `~/.claude/settings.json`, `~/.claude/history.jsonl`, anything under `~/.claude/plugins/`.

**Verify the runtime posture yourself:**

```sh
# 0 sockets — never opens any network
lsof -nP -iTCP -iUDP | awk -v p=$(pgrep -x AgentWatch) 'NR==1 || $2==p'

# 0 persistent file handles to ~/.claude/ between polls
lsof -p $(pgrep -x AgentWatch) | grep "/\.claude/"

# Bundle contents
ls -la /Applications/AgentWatch.app/Contents/{,MacOS}
```

**Debug logging** is off by default. Enable with `AGENTWATCH_DEBUG=1 open /Applications/AgentWatch.app`; output goes to `/tmp/agentwatch.log` and is not used in normal operation.

## Architecture

```
AgentWatchApp.swift          @main; status item + notch + transcript/Costs/Search/History windows
├── State/
│   ├── AppState.swift        @Observable singleton; polls every 3 s, detects transitions
│   ├── FavoritesStore.swift  Starred sessions (UserDefaults)
│   ├── NotchUIState.swift    Notch stage/size shared with the controller
│   └── Pricing.swift         Per-model Anthropic published rates
├── Discovery/
│   ├── SessionScanner.swift  Reads <profile>/sessions/*.json across profiles
│   ├── ProcessChecker.swift  kill(pid, 0) liveness + SIGTERM/SIGKILL
│   ├── JSONLReader.swift      Streams <profile>/projects/*/*.jsonl
│   ├── HistoryCatalog.swift  Past-session catalog
│   ├── CostCalculator.swift  Pure-function cost aggregation (by profile/project/model/day)
│   └── SearchEngine.swift     Substring search, capped at 200 hits
├── Model/                    Plain structs (Session, Status, TranscriptEntry, CostAggregate)
├── UI/
│   ├── MenuBarContent.swift  The popover (grouped by profile)
│   ├── HistoryView / SearchView / CostsView / TranscriptView
│   ├── NotchView + NotchShape Dynamic-Island panel
│   ├── MascotView + ConfettiView   Walking mascot + burst confetti
│   └── StarButton / CopyButton / Theme
└── Util/
    ├── HomeDir.swift          Profile discovery, path resolution, DebugLog gate
    ├── StatusItemController   Menu-bar item + right-click menu (incl. demo)
    ├── NotchController / MascotOverlayController   Borderless overlay windows
    ├── TerminalLauncher.swift Resume / open / agentwatch:// handling
    ├── LoginItem.swift        Launch-at-login
    └── Notifications.swift    UNUserNotificationCenter + osascript fallback
```

## Pricing data

Anthropic published rates live in `Sources/AgentWatch/State/Pricing.swift`. The `asOf` constant tracks when the rates were last updated. **If you route Claude Code through a proxy or gateway, your actual billing will differ** — these numbers are estimates of token spend at Anthropic's list price.

## Contributing

Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). The guiding
constraints: stay **dependency-free**, native (Foundation/SwiftUI/AppKit), and
auditable (no network, no telemetry).

## License

Released under the MIT License — see [LICENSE](LICENSE).
