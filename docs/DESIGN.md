---
version: alpha
colors:
  accent: "#6553B4"
  ink: "#403456"
  pink: "#FFC7F0"
  lemon: "#FFE4AE"
  mint: "#97EBDF"
  blue: "#B3CAFF"
  lilac: "#E4C1FB"
  glass: "#DCEEFF"
  codexWorking: "#38B6FF"
  codexFailed: "#F07474"
  codexWaiting: "#F3D25C"
  codexFinished: "#75D8AB"
  water: "#5AAEFF"
typography:
  body:
    fontFamily: "SF Pro Rounded, system-ui"
    fontSize: "12px"
  utility:
    fontFamily: "SF Pro, system-ui"
    fontSize: "11px"
rounded:
  card: "8px"
  panel: "36px"
spacing:
  unit: "4px"
  panel: "9px"
components:
  taskCard:
    backgroundColor: "#FFC7F0"
    color: "#403456"
  draftCard:
    backgroundColor: "#FFC7F0"
    color: "#403456"
---
# Delay No More — glass tube

## Overview
The user's November 4 revisions and attached reference define a transparent vertical glass tube containing colorful physical event cards. It has a tiny face and feet integrated into the glass base, no separate character. In v1.5, clicking its mouth reveals one editable pastel card above the opening. Pressing Return sends that same card through the rim into the stack. This physical continuity is the signature. Keep the object light and playful, with no visible toolbar, form panel or action buttons.

## Colors
Runtime ownership is Model B. `Sources/DelayNoMore/Theme.swift` owns the palette and this file mirrors it. Card fills brighten and enrich the pink, yellow, teal, blue and mauve hues of Catppuccin Frappé. Each card receives a color at capture and keeps it through reordering, completion Undo and restart. On upgrade, older cards receive the corresponding color for their saved position. Use dark title text on each fill. A contrasting dashed outline marks a draft error. Use darker lower edges for thickness. Glass uses faint white, blue and lilac gradients; the center stays translucent and the surrounding native window stays clear. Never put a solid rectangular canvas behind the tube. The tucked preview reuses the tube artwork and palette. [Catppuccin Frappé palette](https://catppuccin.com/palette/#frapp%C3%A9)

## Typography
The idle pet contains only user task names. Omit the app title, tagline, Next/Later labels, position numbers, counts, empty-state prose, insertion labels and status captions. The draft contains a native single-line name field inside the card artwork, with no date fields, checkmark, cancel button or static heading. Preserve Unicode, native selection and copy/paste. Accessibility labels contain the full saved names. A passive, accessibility-labeled error may accompany the draft when validation or saving fails. Storage recovery and Undo belong in the native menu bar.

## Layout
The upright tube occupies 104 × 208 points. In v1.6.5, its fixed native panel includes 35 points of clear space above the tube, allocated when placing it. Placement near the menu bar preserves that clearance. Opening a draft or sending a card in or out never changes the panel frame, tube position or rim position; only the cards animate. TubeMetrics owns this geometry, the 20-point mouth, the 28-point base and the 30-point card rows. Cards show one line with ellipsis for overflow. On hover, an overflowing name scrolls horizontally from beginning to end and back. Leaving restores the ellipsis. Short names stay still. Reduce Motion keeps text static with a native full-name tooltip. The native field scrolls horizontally while entering long names. Scroll the stack with the trackpad or mouse wheel. Drag cards to reorder them. Drag the glass or empty space to move the pet.

At a side edge the tube leans outward, keeping the open rim and part of the glass and cards visible. Tucking and revealing are smooth, interruptible transitions. The upright and tucked artwork use the same tube and card dimensions; clip them at the physical display boundary rather than shrinking them into a replacement handle. Hover or click the exposed tube to reopen it. Reduce Motion uses an immediate transition with the same final geometry.

While a card is dragged, surrounding cards slide aside to open a card-sized gap at the current insertion target. A valid release saves the order. Releasing outside cancels the preview. Reduce Motion moves cards directly to their preview positions.

## Elevation & Depth
Draw glass procedurally in SwiftUI with an elliptical lip, thin reflective side walls, transparent center, rounded base and small feet. Overlay highlights must not intercept input. Cards use a thin top shine and a darker offset lower layer; avoid a serious dashboard or flat list-panel appearance. No bitmap cutout or image-rendered text is needed. Remove the native rectangular window shadow.

## Shapes
Card corners are eight points. The vessel stays upright during normal use. The tucked preview tilts toward its dock edge while the task controls stay in the upright view.

## Components
Canonical owners: Theme for tokens; TubeArtwork for glass, mouth, face and reflections; StackView for card gestures, flights, capture and passive errors; TaskEditor for the native single-line name field; TaskStore for committed data and session-only Undo; NativeWindow for transparent hosting, focus and docking; AppMain for menu-bar recovery. No sibling screens exist. Native AppKit text editing owns caret, selection, composition and copy/paste. Suppress right-click menus on both the cards and the native text editor. Native scrolling remains enabled but all scroll indicators are hidden. This explicit user choice supersedes the previous visible-scrollbar default. There is no web/CSS adapter.

A captured card travels from its editable position through the mouth, then takes its top slot. Keep its text and pastel face continuous across that transition. Double-clicking the top card animates it upward through the opening while the tube stays anchored. The remaining cards ease into place after it exits. Subtle reflections and occasional blinking animate the vessel without making it roam. Reduce Motion disables idle animation and spring travel. The mouth and task cards expose named accessibility actions without adding visible controls. Do not auto-hide while a draft is open, while dragging or during a card flight, native menu tracking or keyboard focus.

## Do's and Don'ts
- Keep the pet free of action buttons, right-click menus and form-panel chrome.
- Capture always pushes to the top; reordering is a separate manual action.
- Only the top card can complete, enforced in both presentation and model.
- Double-click the top card to complete it. Keep task recovery in the menu bar for ten seconds.
- Return saves a draft; Escape discards it. Moving focus away preserves the draft.
- Migrate stored tasks to schema 2 and preserve the exact schema 1 file in stack.v1.backup.json before the first rewrite. Retired deadline data exists only in that backup.
- Keep validation and save failures readable and accessible; route storage recovery through the menu bar.
- Do not add rename or delete paths to the pet or its accessibility actions.

## Agent activity
Status is a glowing colored outline around the glass vessel, rim and base: a crisp 1.6 pt line with a soft halo, so it reads against light and dark (including blue) desktops. The glass itself stays clear. Working is electric blue with large upward-looking eyes. Waiting for an approval or answer is yellow with wide eyes and raised brows. A failed turn is red with worried brows. A completed turn is green with a relaxed smile until a real hover acknowledges it. Idle is plain glass with a neutral face; unknown is plain glass with a sleepy face. There is no status text, tooltip or button on the pet; accessibility values carry the status. The `codex*` color tokens are shared by both agents.

Status never animates: the pet usually sits tucked at a screen edge, so every state is a still pose drawn once per change and an idle or busy tube costs no redraws. Card capture, drag, flights, docking and the long-title hover scroll are the only motion, and Reduce Motion still governs those.
