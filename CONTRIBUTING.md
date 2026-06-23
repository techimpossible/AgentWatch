# Contributing to AgentWatch

Thanks for your interest! AgentWatch is a small, personal project shared as-is.
Issues and pull requests are welcome, but please note there's no support
guarantee or fixed release cadence — responses may be slow.

## Guiding constraints

These are deliberate and unlikely to change. PRs that violate them probably
won't be merged:

- **Dependency-free.** Foundation, SwiftUI, AppKit, UserNotifications, OSLog
  only. No third-party Swift packages.
- **Native.** No web stack, no embedded servers, no CLI, no IPC.
- **Auditable & local.** No network sockets, no telemetry, no analytics, no
  update checks. AgentWatch only ever *reads* files under the discovered Claude
  config dirs — it never writes to them.
- **Small.** The codebase is intentionally readable end-to-end. Keep additions
  focused.

## Building

```sh
./build.sh           # produces AgentWatch.app (ad-hoc signed)
./build.sh --run     # build + launch in place
./build.sh --install # build + copy to ~/Applications/AgentWatch.app
```

Requires Swift 6+ (Command Line Tools is enough — no full Xcode needed) and
Apple silicon on macOS 26 (Tahoe) or later.

## Before opening a PR

- Build cleanly with no new warnings (`swift build`).
- Keep changes scoped; describe what you changed and why.
- If you touch what files are read at runtime, update the **Audit notes** table
  in `README.md` so the trust posture stays accurate.
- Don't commit build artifacts (`.build/`, `*.app`) or local state (`.claude/`)
  — they're git-ignored for a reason.

## Reporting issues

Include your macOS version, how you launched Claude Code (terminal/IDE, and any
`CLAUDE_CONFIG_DIR` profiles), and—if relevant—`AGENTWATCH_DEBUG=1` log output
from `/tmp/agentwatch.log`.
