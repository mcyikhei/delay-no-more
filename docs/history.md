# Delay No More — history (1.0 – 1.8.1)

Superseded documents kept for reference. Current behavior lives in README.md and DESIGN.md.

---

## Archived README.md

### Delay No More — slim glass tube

A small transparent Mac desktop pet with custom, brighter card colors inspired by Catppuccin Frappé.

#### Open the update

If an older copy is running, quit it through its stack-shaped menu-bar icon first, then open **Delay No More.app** beside this source folder. Opening another copy while one is running reveals the existing process, so quitting is necessary to load the new design. This app has no Dock icon. The local build is ad-hoc signed and is not a notarized public release.

The app bundle uses the supplied artwork in `assets/AppIcon.png`. **Delay No More alias** is a Finder shortcut to the workspace app and carries the same icon.

#### Use the tube

- Click the **open mouth of the tube**. A single pastel card appears above it, ready for a task name. Press **Return** to save; that same card moves through the opening into the stack.
- Press **Escape** to discard an unfinished card. Switching to another app keeps the draft open. A blank name or failed save leaves your text available to correct and retry.
- **New tasks always go on top.** There are no controls to create tasks in the middle or at the bottom.
- Drag a card inside the tube to reorder it. Other cards slide aside to show a card-sized gap at its destination. Release there to save, or outside the tube to cancel. Drop on the mouth to move it to the top. Reduce Motion shows the preview without sliding.
- Each card keeps its assigned Frappé-inspired color after reordering, Undo and restarting the app.
- **Double-click the top card** to pop it out through the rim while the tube stays still. **Undo task removal** is available in the menu bar for ten seconds.
- Hover over a long name to scroll from its beginning to its end and back. Moving away restores the ellipsis. Short names stay still. With Reduce Motion enabled, the text stays still and a native tooltip shows the full name.
- With VoiceOver, use the mouth's Add action and each card's Move actions. The top card also offers Complete. Accessibility labels always include the full task name.
- **Drag the glass walls, empty interior, gaps or face** to move the tube. Dragging cards reorders them; the mouth adds tasks. Drop near either side of the screen and move the pointer away. The tube leans past the edge at the same scale, with the rim and parts of its top cards visible. Hover or click the exposed glass to reopen it.
- Use the menu-bar icon to show, hide or quit the tube, undo a completion or access storage recovery.

The tube is 104 points wide and 208 points tall, with 35 points of clear space above it reserved when placed. Placement near the menu bar leaves this clearance. The tube, rim and upright panel stay still when a card enters or leaves; only the cards animate. Edge docking and tucking work as before. Scroll using a trackpad or mouse wheel; the scrollbar stays hidden. The pet shows task names with no action buttons, right-click menus or date controls. Saved cards can be reordered and completed; this version has no rename or delete action. The draft uses native text selection and copy/paste. Card travel, smooth edge transitions, glass reflections and the occasional blink respect Reduce Motion.

#### Codex activity companion

Use **Connect Codex activity…** in the menu bar, then open **Settings > Hooks** in Codex and review and trust the Delay No More hooks. New or changed hook definitions must be trusted by Codex before they run. Existing hooks are preserved, and each changed configuration receives an original-file backup beside `~/.codex/hooks.json`. Use **Disconnect Codex activity** to remove only this app’s hooks.

The tube represents all newly observed desktop-owned Codex chats together. The whole glass turns **blue while working**, with larger eyes looking upward. It turns **yellow for detected decision/approval requests**, **red for a confirmed failed turn**, and **green for a confirmed completed turn**. Green persists until the pointer enters or moves over the pet, including its tucked portion. The tube remains anchored and its task cards keep their colors and positions. Reduce Motion uses static colors and expressions.

Pending attention takes priority over other working chats. One chat finishing cannot finish the whole pet while another is active. Once activity stops, a confirmed failure takes priority over green. Starting a new work cycle clears earlier terminal colors. Completion means a Codex turn completed, which does not prove that a multi-turn goal is finished. Approval yellow begins when Codex requests approval and clears on subsequent activity; another hook may resolve approval automatically. An asynchronous question remains yellow until new user input or the turn ends because there is no hook for its eventual UI answer.

A still, sleepy face means status is unavailable, disabled or not yet observed. The app cannot reconstruct already-running chats before receiving an identifying hook event. It uses a separate local Codex protocol client to request **only stored turn metadata**, with items explicitly omitted. It matches the returned turn ID before accepting completed/failed/interrupted, discards error text and never resumes a chat or starts model work. There can be a short delay before a terminal result is saved. Missing or mismatched results never become success/failure. Working blue and attention yellow stay latched until a replacement status arrives; silence does not clear either color. Generic Stop and SessionEnd signals keep the current color while the matching outcome is being checked. A confirmed completion changes blue directly to green, with no neutral step. Explicit interruption clears active work, and Disconnect resets observation. Terminal metadata observation can continue for up to 24 hours; missing results do not manufacture an outcome.

The helper accepts a desktop-owned process only when native executable ancestry reaches a bundle identified as `com.openai.chat` or `com.openai.codex`. A standalone CLI process is excluded. A CLI explicitly launched using the desktop’s bundled executable shares that ownership and can be included. If ancestry is unavailable, the helper sends nothing. Remote/cloud jobs are outside this connection.

Hook input is processed in memory and reduced to event type, event ID, session/turn IDs and timestamp. Terminal metadata adds only the outcome enum. Prompt, reply and tool contents are not forwarded or persisted. Status is session-only. The socket is current-user-only; no network port is opened. Hook delivery is nonblocking and fail-open. If the pet is closed, the hook exits successfully. Codex trust is never bypassed.

The installation can also be prepared without a GUI:

```sh
../'Delay No More.app'/Contents/MacOS/DelayNoMore --install-codex-hooks
../'Delay No More.app'/Contents/MacOS/DelayNoMore --codex-connection-check
```

After moving the app, run Connect again to refresh its executable path and review the changed hooks in Codex. The installed desktop Codex CLI must support metadata-only thread/turns/list. Status startup errors can be retried through Connect; configuration errors are shown there. No computer use or GUI testing was performed for this update.

#### Data

Active tasks, card colors, order and window placement save locally to `~/Library/Application Support/DelayNoMore/stack.json`. Existing tasks upgrade automatically without a reset, keeping the color of their saved position. On the first save of an older schema 1 file, the exact original is preserved as `stack.v1.backup.json` before schema 2 removes retired deadline fields. IDs, names, colors, order and placement survive migration. If the backup cannot be made, saving stops and the original stays untouched. Older app versions cannot read schema 2. A name is the only field you enter for a new card. There is no account, cloud service, analytics or notification permission. The optional Codex connection uses only a private local Unix socket.

A failed save preserves the previous committed stack and keeps an unfinished draft available. If saved data is unreadable, use storage recovery in the menu bar; the app does not silently overwrite the file. Avoid running a raw build executable and packaged app concurrently with the same data directory.

For isolated nonvisual checks, `DELAY_NO_MORE_DATA_DIR` overrides the data directory. Optional `DELAY_NO_MORE_DIAGNOSTICS` writes geometry/state without task names.

#### Build and checks

Requires Apple-silicon macOS and Swift command-line tools. macOS 13 is the deployment target; older OS runtime compatibility has not been established. The package script uses an installed macOS 15.2 SDK on this Mac because its newest command-line SDK lacks a SwiftUI macro plugin. Build caches remain in the workspace’s `work` folder.

```sh
./scripts/check.sh
./scripts/package.sh
../'Delay No More.app'/Contents/MacOS/DelayNoMore --self-test
python3 scripts/verify-design.py
```

The standalone core runner works without full Xcode. XCTest sources are also supplied for an Xcode-equipped environment. SwiftUI draws and animates the glass and cards; AppKit owns the transparent floating window and docking; DelayCore owns task storage and the activity reducer. See DESIGN.md, UX-CONTRACT.md and VERIFICATION.md for details.

Visual testing remains stopped at the user's request. See VERIFICATION.md for the actual compilation and nonvisual check results. Native text composition, VoiceOver, animation smoothness and display-edge behavior need separate runtime verification; source review and model tests do not establish them.

---

## Archived UX-CONTRACT.md

### Delay No More interaction contract

Source: the user's accepted macOS plan and subsequent transparent-tube, slim-tube, v1.5 single-card-entry, v1.6 color/drag and v1.6.5 fixed-panel decisions in this chat. The v1.5 decisions supersede the earlier editor, deadline controls and card menus. This is a single local personal stack with no account, network or completed history. The November 5 revision adds optional local Codex activity hooks and removes retired deadline, rename/delete and indexed-creation code. Visual intent and tokens live in DESIGN.md.

| Capability | Canonical owner | Source of truth | Allowed variants | Verification |
|---|---|---|---|---|
| Form | StackView draft lifecycle and TaskEditor native single-line field | v1.5 mouth capture; Return saves, Escape cancels | create only | core validation and native input QA |
| Scrollbar | SwiftUI ScrollView with hidden indicators | DESIGN.md bounded stack | stack only | native overflow QA |
| Toast | Passive draft error, native menu-bar recovery and TaskStore | v1.5 no pet buttons; 10-second latest Undo | validation / save error / read error / Undo | StoreSelfTest and native QA |
| CRUD | TaskStore transactions and StackDocument | v1.5 adds, moves and strictly completes the top task | push / move / complete / undo | core checks and StoreSelfTest |

#### Shared behavior
New tasks always enter index zero. TaskStore.add does not accept a position. Users reorder existing cards manually; moving uses the final post-removal index. Double-clicking the current top card completes that specific task. The top card also exposes a named accessibility action for completion. Revalidate the task ID at commit so rapid input cannot accidentally complete the next card. Saved cards have no rename, edit or delete interaction, including accessibility actions. No right-click menu appears anywhere on the pet.

The latest successful completion replaces the previous Undo. Restoration uses its former numeric index clamped to current length, preserving intervening changes. Undo is available from the native menu bar for ten seconds and is kept in session memory. The tube has no static headings, captions or counts; only task names are shown on the idle view. The active schema 2 task contains only ID, name and immutable color. Before an older schema 1 file is rewritten, JSONStorage must preserve its exact bytes in stack.v1.backup.json. Backup failure blocks the save. Retired deadline values exist only in that backup.

All commits save before publication. Failed saves preserve the last committed model and show an error. Unreadable/version-incompatible saved documents block editing and remain unchanged; Retry rereads the file. This app never silently resets a user's saved stack.

Each card's pastel is assigned at capture and persisted with it. Reordering, completion Undo and restart preserve that color. Existing cards receive their saved-position color once during upgrade, then retain it independently of position.

#### Draft lifecycle
Clicking the open mouth or invoking its Add accessibility action reveals one editable pastel card above the tube. Repeating Add focuses the existing draft rather than creating another one. The field uses native single-line text entry, selection and copy/paste, with an accessible name. Return saves when text composition is finished; Return used to confirm IME composition must not submit a task. Reject a blank name and preserve Unicode.

Successful persistence starts the entry flight: the same card moves through the rim into its top slot. Block duplicate submission while saving or flying. Validation or save failure leaves the draft text intact and exposes a passive, accessibility-labeled error; no icon button or alert form appears. Return retries after correction. Moving focus to another app preserves the unfinished draft. Escape explicitly discards it and ends editing. No save/cancel/date buttons or separate editing popover are part of this flow.

#### Window and focus
The mouse wheel and trackpad scroll the stack with hidden indicators. The upright tube is 104 × 208 points inside a fixed 104 × 243-point panel, including 35 points of clear space above the rim. Allocate this space at placement, including near the menu bar, rather than in response to a draft or card flight. Opening or closing a draft and entering or exiting a card leave the tube, rim and panel frame stationary; only cards animate. This fixed upright geometry does not change actual docking or tucking. Taking keyboard focus is deliberate when opening or refocusing the draft; hover alone does not take focus.

Dragging the glass, empty interior, gaps or face moves the window. Dragging a card reorders it. The panel checks the mouth, visible cards and draft field when a press begins. Card dragging stays in a local gesture: there is no system drag payload or file export, and releases outside the tube cancel. It tracks background drags in screen coordinates and saves the final position on release. Card regions use top-down coordinates and clip to the scroll viewport. Whole-pet movement and tucking are suspended while a card is dragged or flying.

During a card drag, surrounding cards slide aside to leave a card-sized gap at the current target. This is a temporary preview: a valid release saves the new order once; release outside cancels and restores the committed order. Reduce Motion places cards directly in their preview positions without sliding.

The upright tube docks to either side of the usable screen. After the pointer leaves, a 700 ms delay leads to the tilted preview at the physical display boundary. Hover for 250 ms or click the visible tube to reopen it. An open draft, dragging, card flights, native menu tracking and keyboard focus suspend tucking. Tuck and reveal animate smoothly in both directions and cancel stale transitions when direction changes. The tucked artwork keeps the upright tube and card scale, clipping the rotated glass and parts of the cards at the physical display edge. WindowPlacement stores the upright left and top in AppKit screen coordinates. Restore by display ID and use the menu bar to recover a hidden tube.

#### Access and retention
Local current-user data only, no network. Active task IDs/names/colors, order and window placement are persisted in Application Support using schema 2. Schema 1 migrates through a verified original-file backup before rewriting. Older apps reject the newer version. Completing removes the active record; session memory retains only the latest completion for ten seconds. No completed history. Draft text is not a committed task. Operating-system file backups are outside app control. Each application instance owns one stack; the native launch path prevents duplicate GUI instances.

#### Accessibility and native ownership
Native AppKit owns text selection, caret movement, composition and copy/paste; suppress default text context menus while keeping standard keyboard editing. Owned UI copy is English and task names preserve Unicode. The mouth exposes Add; cards expose their full names and valid Move up/down/top/bottom actions; only the top card exposes Complete. These accessibility actions provide a non-drag path without visible buttons or contextual menus. Passive draft errors expose readable descriptions. The native menu bar retains Show, Hide, Quit, Undo and storage recovery.

Hovering an overflowing task name scrolls it horizontally from beginning to end and back. Hover exit restores its single-line ellipsis. Names that fit remain still. The accessibility label always contains the complete name. Reduce Motion keeps the text static and exposes the full name in a native tooltip.

Reduce Motion disables idle animation, spring travel and animated docking, while keeping final card order, scale and geometry unchanged. Manual VoiceOver, IME, animation, display-edge and extra-monitor verification must be reported separately from model tests. Visual testing remains stopped at the user's request; static contracts do not establish those runtime results.

#### Codex activity contract
The user selected aggregate observation of running desktop Codex chats, then specified blue thinking, red terminal error, yellow decision/approval and green finished. A real hover acknowledges green and restores normal glass. This supersedes v1.7's limited rim-only activity presentation. The reference guides upward-looking eyes and full-vessel tint, with no vessel jump or layout change.

CodexHookBridge owns allow-listed activity metadata and configuration. It installs nine command events while preserving other settings and an exact backup, requiring Codex review/trust without bypass. Model-start signals resume ordinary work; explicit decision/approval requests mark attention. An asynchronous question remains pending through immediate tool return until fresh user input or terminal outcome. Since approval hooks fire before the approval UI, another hook may resolve them automatically; later activity clears the yellow request signal. PostModelRequest attempt failures never determine a terminal error.

CodexTurnMonitor owns a separate local stdio protocol process, with initialize/initialized and thread/turns/list as its only methods. Queries use known session IDs, limit1, descending order and itemsView notLoaded. It asks for no thread preview or message items, performs no resume/start call and projects only a matching turn's status. Late/mismatched turns, nonempty items, errors, missing data and inProgress never become red/green. Mapping of hook session to stored thread can be unavailable for some session kinds; uncertainty remains safe. The monitor stops with disconnect and retains no status across restart.

CodexStatusReducer owns waiting/working/failed/finished/idle/unknown aggregation, outdated-event and duplicate rejection, turn identity, and completion acknowledgement. Attention dominates working. Terminal failure dominates completed results after observed activity ends. Green is latched without expiry; any real pet hover resets the completed entries, shared across upright/tucked views. Waiting and working cannot be dismissed by hover. Root/newturn metadata cannot be replaced by a rejected old/subagent hook. A new work cycle clears old terminal colors. SessionEnd cannot erase a latched outcome. Unknown is used for missing evidence, never an inferred success or error.

CodexStatusStore owns the receiver, metadata monitor and observable snapshot. TubeStatusPresentation owns shared procedural artwork and clock. NativeWindow owns silhouette hover in upright/tucked views without taking focus. Card names/fills/order, fixed geometry and native input remain independent of status. Color is reinforced by eye/brow/mouth poses and accessibility values. Reduce Motion retains static distinct states. There are no status captions or buttons on the pet. No computer use or visual testing is part of this delivery.

#### Status continuity — v1.8.1
The user's visual report overrides the previous five-minute activity expiry and neutral Stop behavior. Working and waiting remain latched through arbitrary quiet periods. Stop is a provisional lifecycle event and preserves the existing activity. SessionEnd also preserves active state pending matching metadata; it is not proof of interruption. A confirmed TurnCompleted outcome replaces blue/yellow directly with finished, failed or interrupted. Explicit Interrupt still clears working state, and explicit Disconnect resets all observation. Starting the status connection is the only intentional startup reset. Hover acknowledges only finished. These invariants are shared by upright/tucked presentation and hold under Reduce Motion or paused decorative animation.

---

## Archived VERIFICATION.md

### Version 1.8.1 — continuous working color

The user's report identified early loss of blue and a neutral frame before green. Both came from status aggregation: generic Stop set idle while confirmed metadata was pending, SessionEnd could remove an active session, and the five-minute freshness rule could discard active color. Presentation review found paused/Reduce Motion and upright/tucked views already preserve the snapshot's tint.

Working and waiting now remain latched through Stop, SessionEnd and arbitrary silence. A matching TurnCompleted result replaces them directly with finished/failed/interrupted. Explicit Interrupt and Disconnect retain their existing effects; green still clears on hover. Non-new-cycle hooks that omit turn_id preserve the tracked identity. A genuinely new turn with no ID clears the prior identity until fresh evidence establishes it. Terminal callbacks and the reducer both require a match, preventing late results from older work from clearing new blue.

Regression traces cover blue → Stop → SessionEnd → one-day silence → green, with every intermediate state asserted working, and equivalent waiting continuity. They also cover multi-chat outcomes, nil-ID lifecycle events, new nil-ID prompt followed by stale terminal metadata, explicit interruption, failure, completion hover, and late duplicate events. Final verification passed **33/33 core checks** and **97/97 packaged headless checks**. The Apple-silicon release build, strict ad-hoc signature check, Info.plist lint and Finder alias/custom icon checks passed. The 12 runtime design tokens match and task text/fill contrast checks pass; the strict contract auditor reports zero findings. Existing command-line-tools linker search-path warnings remain nonfatal.

No computer use, app GUI launch, screenshots, visual testing or simulated events sent to the running pet were performed for this fix. The source review and automated state traces verify that no neutral status is emitted in the tested paths; they do not establish rendered animation timing. No hook configuration change is required, and no user task data was read or changed. Quit an older running copy and reopen the rebuilt app to use the update.

### Version 1.8.0 — whole-tube status and upward gaze

Implemented November 5, 2026 using command-line tools, with no computer use, GUI launch, screenshots or visual testing.

The full procedural glass vessel/rim/base/feet now tint blue for work, yellow for detected attention, red for confirmed failed turn and green for confirmed completed turn. Thinking uses enlarged white eyes with pupils raised upward. Green is latched until actual pointer entry/movement over the pet, shared by upright/tucked views. The fixed artwork/window frame, card colors and card travel stay independent. Distinct static states support Reduce Motion. Native pointer callbacks were inspected; their actual GUI delivery and rendered animation appearance are not claimed as tested.

The nine owned hook handlers were refreshed in the local configuration. The packaged connection check reports hooks configured and desktop ancestry recognised. Trust was not granted or bypassed.

The source is now stronger than v1.7. Hooks supply prompt/tool/model-start/decision/approval evidence. CodexTurnMonitor launches a separate local stdio protocol client that only initializes and calls thread/turns/list with known thread ID, limit1, descending order and itemsView notLoaded. No resume/start, thread/read or private IPC subscription is used. Only matching stored turn IDs can produce a terminal color. Individual model errors, old results, missing results, interrupted turns, item-bearing responses and timeouts do not become failed/completed. The metadata parser discards error text and message data. Mapping is conservative for session kinds where hook session ID and stored thread ID differ.

Read-only integration evidence on this installed Mac: initialization succeeded; the known-turn query returned metadata with empty item arrays and no preview. The packaged --codex-monitor-check reader returned a matching interrupted terminal result and exited0. This verifies protocol retrieval/projection through the packaged code, not a complete live trusted-hook lifecycle. No transcript/message contents were printed or retained.

Final verification passed **30/30 core scenarios** and **86/86 packaged headless checks**. Release packaging, strict signature verification, Info.plist lint and the Finder alias/icon check passed. All 12 runtime palette tokens match DESIGN.md; task text/fill contrast passes, and the strict contract auditor reports zero findings. Covered scenarios include all four status states, multiple chats, waiting priority, successful finish latch without expiry, hover acknowledgement and non-green hover no-ops, stale/duplicate/previous-turn rejection, terminal failure, interruption, asynchronous questions, projection safety and local sockets. Static palette/design contract and signature checks are rerun for this version. Actual Codex hook trust, prompt-to-event delivery, approval UI resolution timing and visual behavior remain manual verification items.

Attention is a detected request signal. Other hooks may auto-resolve approvals; subsequent activity clears ordinary yellow. Async question completion has no dedicated hook, so pending yellow clears with new user input or turn end. Green means a confirmed turn completed, rather than proof that an entire multi-turn goal has been achieved. Unknown remains appropriate when identification or status observation is unavailable. Neither hover nor status ever changes task data.

### Version 1.7.0 — Codex activity and retired-feature cleanup

Implemented on November 5, 2026 using command-line tools only. No computer use, GUI launch, screenshots or visual testing was performed.

- `scripts/check.sh` passed **30/30 core scenarios**. Deadline-only and retired edit/delete/index-insertion scenarios were removed. Schema 1 migration checks cover exact original backup, preserved IDs/names/colors/order/placement, backup failure, conflicting backup, matching retry and schema 2 fields. Core storage retains corrupt/newer-file protection and atomic writes.
- The packaged executable's `--self-test` passed **51/51 checks**. These cover committed task state and Undo, fixed geometry and reorder targets, two simultaneous observed chats, duplicate and late events, Stop continuation, SessionStart during activity, stale/disconnected/unsupported status, hook setup idempotence and preservation, exact hook configuration backup, malformed configuration preservation, stripping private content, socket-path collision preservation, local datagram delivery and socket mode0600. The local socket cases require running the headless test outside the Codex filesystem/network sandbox. The sandboxed attempt reported Operation not permitted; the approved unsandboxed headless run passed.
- Native Apple-silicon release packaging passed with Swift 6.4/macOS 15.2 SDK, minimum deployment macOS13. Unused command-line-tools developer framework search-path linker warnings remain. Strict ad-hoc signature verification, Info.plist lint, Finder alias resolution and its custom icon passed.
- The ten remaining runtime palette tokens match DESIGN.md. The five task-title/fill contrast checks pass, ranging from6.95:1 to9.20:1. The strict skill contract auditor reports zero findings. This is static evidence, not SwiftUI rendering proof.
- Read-only local inspection found desktop bundle26.1029.61003 and its codex0.166.0-alpha.6. The documented default app-server control socket was absent. No private IPC socket was used and no chat history was retrieved. `thread/read` can include a prompt preview even with turns omitted, so it was not used as a status-only workaround.
- `--codex-connection-check` recognises this Mac's desktop executable ancestry. The sender projects only event/session/turn IDs and time, uses nonblocking datagrams, returns empty JSON and success, and does not alter approvals or continuations. Exact parent association during actual trusted Codex hook execution remains a live integration check.

The implemented source reports observed working/idle/turn-ended/interrupted/uncertain states. It cannot prove successful completion, approval waiting, failures or the completion of an agent goal. It cannot reconstruct already-running unseen chats. Five minutes of silence from working activity produces uncertainty. Desktop-owned bundled CLI usage can be included. Remote jobs are excluded. Status is runtime-only and separate from stack.json.

The seven owned hook handlers were installed in the local user hook configuration after packaging; a nonvisual check confirmed one handler per event and no duplicate owned handlers. The connection check reports hooks configured and native desktop ancestry recognised. Trust was not granted by this implementation.

Live hook trust, real multi-chat delivery, animation appearance, VoiceOver output, Reduce Motion appearance and native desktop interactions remain unverified. The user must review and trust the prepared hooks through Codex's own review flow. No trust bypass is used. Reopen the new packaged app after quitting an older running copy to load this code.

### Delay No More verification — 4 November 2026

Version 1.6.6 packages the supplied PNG as a seven-resolution ICNS with transparency. The companion Finder alias resolves to the workspace app and retains its custom icon resource. The release build, all 69 headless checks and signature verification passed. No app or alias was opened.

Version 1.6.5 reserves 35 points of clear space above the upright tube at placement. Opening the draft or starting and finishing either card flight leaves the upright frame and rim unchanged. The stack uses an ease-out when cards settle. The release build and 69 headless checks passed, including fixed headroom geometry near the menu bar. Live motion remains unverified.

Version 1.6.4 anchors the tube during card completion. Exit animation uses only the space already available above the tube, up to the normal flight height. The release build and all 69 headless checks passed, including full, partial and zero exit clearance. Live pop-out motion was left untested at the user's request.

Version 1.6.3 brightens the five Frappé-inspired card fills. Dark title contrast measures 6.95:1 to 9.20:1. The release build and all 68 headless checks passed. Visual testing remained stopped.

Version 1.6.2 uses Catppuccin Frappé fills. All five fills support the same dark title ink at 4.94:1 to 7.05:1 contrast. The release build, 68 headless checks and archive signature check passed. No live visual testing was performed.

Version 1.6.1 maps the five saved color assignments to Catppuccin Latte fills. Title and draft text use contrasting ink for each fill. The 15 palette tokens matched the runtime values and title contrast measured 4.91:1 to 7.10:1. The release build and all 68 headless checks passed. No live visual testing was performed.

Version 1.6.0 uses five Catppuccin Macchiato colors and stores a color with each card. Older files load with color assignments based on saved positions and retain those assignments on the next atomic write. During a drag, the stack previews the proposed order by leaving the moving card’s slot open. The release build, 37 core checks and 31 packaged-app checks passed. The new checks cover color assignment, migration, reordering, Undo and insertion-slot geometry. The five card fills give 5.08:1 to 7.89:1 contrast with the title ink. Live drag behavior remains unverified at the user's request to stop visual testing.

Version 1.5.1 scrolls overflowing card titles on hover. It restores the ellipsis on exit and uses a static title with a full-name tooltip under Reduce Motion. The release build and all 65 headless checks passed. Live hover behavior and readability remain unverified at the user's request to stop visual testing.

Version 1.5.0 places a native, single-line draft card directly above the tube. Return saves the name and sends that card through the rim. Escape discards the draft. Deadline display and editing, card context menus, and visible pet buttons have been removed. Existing deadlines remain in the saved document. The draft extends the window by up to 35 points without resizing the artwork. The side-docked tube tilts and slides between states within the selected display.

Version 1.4.0 gives the upright and tucked states the same 104 × 208-point viewport. The tucked view draws the top cards using the same card artwork and row spacing. A local pointer gesture handles card reordering. The app creates no system drag payload for cards, and releasing outside the tube cancels the reorder. Double-clicking the top card completes it. Successful creation and completion animate one card through the mouth in a separate layer above the scrolling stack. The pet's Undo button moved to the menu bar.

Version 1.3.0 uses a 104 × 208-point upright frame. The installed Codex app, version 26.1027.61615, caps `avatar-overlay-mascot-width-px` at 224 and computes the native mascot height as `ceil(width / (192 / 208))`. That gives a maximum frame of 224 × 243 logical points. The editor opens in a 220-point popover. The side preview rotates the glass by 36 degrees, mirrored by edge, and clips the lower tube at the selected display boundary. At full size the preview frame is 79 × 168 points.

Version 1.2.0 narrows the native window from 320 to 220 points and keeps a 500-point minimum height when the screen allows. All scroll indicators, the three mouth buttons and the card ellipsis buttons are removed. The open elliptical mouth creates a task. Card actions move to right-click context menus and named accessibility actions. Dragging glass walls, empty interior, gaps, feet or face routes to native window dragging; cards retain reorder dragging. Editor, Undo and error controls retain their own interactions. New tasks still always push to the top and the saved JSON schema is unchanged.

Version 1.2.1 handles pet movement in the panel's mouse-down, drag and release events. The hit decision uses the panel's current bounds and the protected control regions. Movement starts after three points, follows the original grip offset in screen coordinates, and commits placement on release.

#### Nonvisual verification

- Native Apple-silicon release build and .app packaging succeeded with Swift 6.4 and the installed macOS 15.2 SDK. Deployment target remains macOS 13. The command-line tools' unused developer-framework search paths produce linker warnings; the build completes.
- **35 core scenarios passed**, including eight hit-region checks and two window movement checks. The new checks cover the drag threshold, fixed grip offset across pointer updates and returning to the original window position. The runner also covers task ordering, completion, Undo, deadlines, persistence and recovery.
- **30 packaged-app checks passed**. They cover task state and persistence, local reorder targets, equal artwork scale, mirrored docking, and release outside the tube. The two v1.5 checks cover name-only capture alongside legacy deadlines and the intermediate dock pose’s geometry and hit mapping.
- Ad-hoc signature verification and Info.plist lint succeeded. The app is not a notarized public release.
- Thirteen runtime color tokens match DESIGN.md. Checked opaque text/pastel combinations exceed 4.5:1 contrast; glass itself is decorative and translucent. This does not establish rendered contrast over every desktop image.
- The panel routes mouse events using the current visible silhouette, the mouth and clipped control bounds. The scroll views use hidden indicators.
- The idle tube displays task names. Tooltips and accessibility actions provide task names and gesture equivalents. Draft validation uses an outline and accessibility announcement. Storage errors and recovery are available in the menu bar.
- Source inspection found no system drag provider or drop delegate. Local drag targets move existing IDs to final indexes. The stack and tucked preview contain neither a checkmark nor an Undo button.
- The frontend skill’s strict contract auditor returned zero findings. Its web-focused parser does not validate Swift rendering or interaction; this is contract-presence evidence only.

#### Visual testing boundary

**No GUI launch, screenshot, UI automation or visual testing was performed for this redesign, as requested by the user.** The supplied image was used as design reference, not as evidence of the app's rendered result.

The floating draft, IME composition, input focus, Return/Escape, secondary clicks, card gestures, tuck and reveal motion, and Reduce Motion remain unverified in the running GUI for version 1.5.0. VoiceOver, long-stack scrolling, display changes, multiple monitors, and Spaces/full-screen behavior also remain manual acceptance scenarios.

Earlier v1 visual testing observed task creation, completion and Undo, but does not validate this revision. That earlier testing also recorded a later UI/data order discrepancy whose cause was not established; this redesign does not claim to resolve it. Single-store model/persistence checks pass. Running a raw executable beside the packaged app with the same data directory can create competing writers; avoid that configuration.

Compilation and headless checks used the available Apple-silicon Mac. The deployment target is macOS 13. The standalone runner supplies the test results for this command-line-tools installation, which lacks XCTest. Local token and contrast checks passed. Registry access for the DESIGN.md linter failed earlier.

#### Reproduce without opening the GUI

From this source folder:

```sh
./scripts/check.sh
./scripts/package.sh
../'Delay No More.app'/Contents/MacOS/DelayNoMore --self-test
python3 scripts/verify-design.py
codesign --verify --strict '../Delay No More.app'
```

The package script selects the installed macOS 15.2 SDK to avoid a missing macro plugin in this Mac’s newest command-line SDK. Set DELAY_NO_MORE_SDK to choose another SDK; if 15.2 is absent the script uses xcrun’s default. Separate release debug symbols are omitted because dsymutil cannot run fully inside this workspace sandbox. No system-wide toolchain setting is changed.

Quit any currently running older version through its menu-bar icon, then reopen the rebuilt app to load the new interface. This update does not launch, quit or manipulate an existing running instance.
