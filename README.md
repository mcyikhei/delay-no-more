# Delay No More

A small transparent glass tube on the Mac desktop that holds your to-do cards and shows what your coding agents (Codex and Claude Code) are doing. Native SwiftUI + AppKit, arm64, macOS 13+, no network, no Dock icon. Current version: 1.11.3.

```
Package.swift
Sources/DelayCore/        pure model: tasks, storage, agent status reducer, hit geometry
Sources/DelayNoMore/      the app: AppKit panel, SwiftUI tube, hooks, status store, CLI routes
Sources/DelayCoreChecks/  core checks runnable without XCTest (scripts/check.sh)
Tests/DelayCoreTests/     XCTest versions of the core checks (swift test, needs Xcode)
assets/AppIcon.png        app icon source
scripts/                  check, package, install, icon and palette tools
docs/                     DESIGN.md (tokens, visual rules), history.md, 2026-11-08 handoff
```

## Install
```sh
scripts/package.sh     # builds dist/Delay No More.app
scripts/install.sh     # copies it to ~/Applications/Delay No More.app
open ~/Applications/Delay\ No\ More.app
```
The app has no Dock icon; it lives in the menu bar (stack icon). Only one copy runs at a time — opening a second reveals the first, so quit the old copy from its menu before opening a new build. Builds are ad-hoc signed, not notarized.

## Use the tube
- **Add:** click the tube's open mouth, type, press Return. New cards always go on top. Escape discards; switching apps keeps the draft.
- **Reorder:** drag a card; others slide aside. Release outside the tube to cancel. Drop on the mouth to move to the top.
- **Complete:** double-click the top card (only the top card can complete). Undo is in the menu bar for 10 s.
- **Move / dock:** drag the glass or face. Drop within 20 pt of a screen side to dock; it tucks after 700 ms and reveals on hover (250 ms) or click.
- **Menu bar** (stack icon): Show/Hide, Undo, ✓ Codex activity / ✓ Claude Code activity, Fuel, storage recovery, Quit.

## Agent status
The glass gets a glowing colored outline (no fill, no animation), readable on light and dark desktops:

| Outline | Meaning |
|---|---|
| Blue | Some observed session is working |
| Yellow | A session waits for approval or an answer (outranks blue) |
| Red | A turn failed and hasn't been opened yet (outranks green and blue) |
| Green | A turn finished and hasn't been opened yet, even while other sessions still work — click the tube to open it |
| None, sleepy face | No status yet |

All sessions of both agents combine into one status: yellow > red > green > blue > idle. A session that has started but done nothing yet never hides another session's result. A new prompt clears only its own session's red/green; other sessions' results stay until opened.

- **Claude Code** (all sessions on this Mac, main agent only): prompt/tools → blue; permission prompt or AskUserQuestion → yellow; `Stop` → green; `StopFailure` → red; an idle prompt after Esc → neutral; `SessionEnd` clears active work.
- **Codex** (desktop app sessions): hooks give blue/yellow; green/red come only from the stored turn outcome, read by `CodexTurnMonitor` through `codex app-server` (`thread/turns/list`, items not loaded). It polls every 3 s, then 10 s after 2 min and 30 s after 10 min, and recycles the server every 15 min. ChatGPT also runs hidden helper threads (titles, suggestions, memory) that fire hooks but are never saved: once Codex has sent Stop/SessionEnd for one and the app-server answers "thread not loaded", it is dropped. An "interrupted" reading before Stop is ignored, because a second app-server reading a turn mid-write reports it that way; a real Esc arrives as an Interrupt hook.
- **No stuck colors from dead sessions:** each event records the agent process that ran the hook. Every 30 s, active sessions whose agent process has exited are removed.
- **Open the session behind the colour:** when the tube is yellow, red or green, a quick click on the glass body (not the mouth, not a card) opens the latest session in that colour. Pressing and dragging still moves the pet; a long still press does nothing.
  - Codex: opens the thread in ChatGPT.app via `codex://threads/<id>`.
  - Claude Code in iTerm2 or Terminal.app: brings that exact tab forward, switching to its desktop and screen (the terminal is activated first, then the window is raised, since macOS only follows a window raise by the active app). macOS asks once for permission to control the terminal (it may ask again after a rebuild, since the app is ad-hoc signed). Without permission, or in another app (VS Code, Ghostty…), the hosting app is brought forward instead.
  - Opening a red or green session marks it seen; the tube goes idle once every result has been opened. Yellow stays until you answer. Hovering no longer clears green.
  - Cost: the tab is located once when a session turns yellow/red/green (two `sysctl` calls per ancestor process); nothing polls.
- **Privacy:** hooks forward only event name, session/turn IDs, time and owner PID. They never approve, deny or alter agent work.

**Connect:** tick **Codex activity** or **Claude Code activity** in the menu bar (untick to disconnect). Unticking one agent drops only its sessions and immediately ignores it, including sessions still open; the other agent's status is kept. Or from a shell:
```sh
~/Applications/Delay\ No\ More.app/Contents/MacOS/DelayNoMore --install-hooks claude   # ~/.claude/settings.json
~/Applications/Delay\ No\ More.app/Contents/MacOS/DelayNoMore --install-hooks codex    # ~/.codex/hooks.json
```
Both keep all other settings and save a `*.delay-no-more.<uuid>.backup.json` before the first change. Codex needs the hooks trusted in Settings > Hooks. Claude Code loads hooks when a session starts (review with `/hooks`). Moving the app means reinstalling. `--remove-hooks <agent>` removes only this app's handlers.

## Usage water
The tube holds still, clear blue water with a soft, single-swell surface, showing how much of an agent's usage limit is **left**: full = nothing used, half = half left, empty = used up. It refills when the limit resets. Cards float in front of it. Choose the source in the menu bar under **Fuel**:

| Choice | Limit shown | Where the number comes from |
|---|---|---|
| Off | — | — |
| Codex weekly usage | Codex weekly window | `codex app-server` `account/rateLimits/read`, read when selected, every 5 min, and after each Codex turn. Codex answers with its own login; Delay No More makes no network calls. |
| Claude Code 5-hour usage | Claude Code 5-hour window | Claude Code's status line. Selecting it installs a status line in `~/.claude/settings.json` that shows `5h 58% left` and forwards the number to the tube; choosing another option removes it. It never replaces a status line you already have. Updates whenever a Claude Code session refreshes its status line. |

The menu line under the choices shows e.g. `58% left · resets 14:30`. The last reading per agent is remembered across restarts, and the water refills when the window resets. Only the percent and reset time are kept — no account, plan or credit data. Check Codex from a shell with `--usage-check`.

**Visual test without touching real status:**
```sh
'.../DelayNoMore' --status-preview working|waiting|failed|finished|clear [seconds ≤ 60]
```
A preview overlays the pet. When it ends, the current live status shows. Clicking the tube ends a preview without opening anything.

**Diagnostics:** `~/Library/Logs/DelayNoMore/status.log` (≤ 256 KB, rotated). Each line: agent, event, hashed session/turn IDs, state transition, monitor match. No prompts, payloads or task names.

## Architecture
| File | Role |
|---|---|
| `DelayCore/StackDocument.swift`, `JSONStorage.swift` | Task model; atomic JSON with schema-1 backup |
| `DelayCore/AgentStatus.swift` | `AgentEvent`, `AgentStatusReducer` (per-agent policy, aggregation, liveness pruning), `AgentStatusPreview` |
| `DelayCore/AgentUsage.swift` | Usage window model and Claude/Codex projections |
| `AgentUsageStore.swift` | Water source selection, readings, Codex reads, reset drain |
| `AgentHookBridge.swift` | Hook helper (projection, owner PID, desktop ancestry for Codex), hook and status-line install/remove |
| `AgentStatusStore.swift` | Socket listener, reducer + preview → published snapshot, monitor sync, liveness, `StatusLog` |
| `CodexTurnMonitor.swift` | Codex stored-outcome reader |
| `TubeStatusPresentation.swift` | Status context and still poses (`TubeStatusAppearance.make`) |
| `TubeArtwork.swift` | Glass, rim, face, reflections and the status `GlowOutline` |
| `StackView.swift`, `TaskEditor.swift`, `TubeCardFace.swift` | Cards, draft, drag, flights |
| `NativeWindow.swift`, `PetHitViews.swift`, `TuckedTubeView.swift` | Panel, docking, hover and hit testing |
| `AppMain.swift` | Lifecycle, menu bar, CLI routes |

Data: `~/Library/Application Support/DelayNoMore/stack.json` (schema 2) and `codex.sock` (mode 0600, shared by both agents). `DELAY_NO_MORE_DATA_DIR` isolates task data for tests.

## Build and checks
```sh
scripts/check.sh                                   # core model checks
scripts/package.sh                                 # release build → dist/
DELAY_NO_MORE_DATA_DIR=$(mktemp -d) 'dist/Delay No More.app/Contents/MacOS/DelayNoMore' --self-test
python3 scripts/verify-design.py                   # palette in docs/DESIGN.md matches Theme.swift
```
`--self-test` runs the store, status, hook-config and local-socket checks headlessly against temporary files; `DELAY_NO_MORE_DATA_DIR` keeps it away from your real stack. Requires the Xcode Command Line Tools (Swift 5.9+); `package.sh` prefers the macOS 15.2 SDK if present (override with `DELAY_NO_MORE_SDK`).

## Verification — 1.9.1 (8 November 2026)
- 33/33 core checks; 143/143 packaged headless checks (97 carried over, 46 new: Claude policy, mixed-agent priority, nil-turn monitor sync, dead-owner pruning, preview isolation, Claude settings merge, legacy-hook replacement, still poses).
- Release build, strict ad-hoc signature, plist lint, palette verification passed.
- Energy baseline (1.8.1): 19.59 "12 hr power" in Activity Monitor. In the unknown state the same build measured 0.0% CPU, so the drain came from the always-on 20 fps redraw in idle/active states and the 2 s poller (measured separately: ~1% CPU, memory +3 MB/s).
- 1.9.0 live measurements (animated status): green/idle 0.73% CPU (blink only), blue 13.5% (15 fps SwiftUI updates). 1.9.1 removes all status animation in favor of a static glowing outline; its live CPU has not been measured yet and is expected to match the unknown state's ~0%.
- Claude Code hooks confirmed live through 1.9.0: `UserPromptSubmit → working`, tool events, `Stop → finished` in `status.log`.
