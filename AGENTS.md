# Timeline — project guide

Native SwiftUI macOS app for `.timeline` documents (plain YAML). Renders visual
timelines (dots for single days, bars for ranges) to a live canvas, PDF, PNG,
print, and Quick Look. Also ships an MCP server and Claude plugin. GPLv3,
public at github.com/philipbl/timeline.

Toolchain: Swift Package Manager only (no Xcode project) — Command Line Tools,
Swift 6.x, macOS 26 SDK; deployment target macOS 14. Package is in
`TimelineApp/` (one dependency: Yams). The old Python/ReportLab CLI
(`timeline.py`) is gone; renderer comments that mention it are historical.

## Current state

- Latest release: **v2.3.0** (2026-10-12) — click an empty day to add an
  event, tentative events. `main` is the release branch.
- Deferred ideas (discussed, not built): drag across empty days to create a
  range event; a hover cue showing which day a click would add.
- Known gaps: no VoiceOver (the canvas is one flat bitmap — biggest gap); no
  `.ics` export; no canvas keyboard navigation or multi-select; no
  `LSApplicationCategoryType` in `Info.plist`.

## Build / test / run

```bash
make app        # assemble + sign build/Timeline.app (also runs lsregister)
make run-app    # build + launch
make test       # in-binary self-test suite (TimelineApp --self-test, debug only)
make docs       # regenerate docs/*.png golden images (CI compares against these)
make icon       # regenerate AppIcon.icns / DocIcon.icns (make doc-icon) from scripts/
```

There is no XCTest/swift-testing (no Xcode). Tests live in `SelfTests.swift` and
run via `--self-test`; add one `test("…")` per behavior. Other CLI modes of the
same binary:

- `--render in.timeline out.png|pdf [--dark]` — headless render
- `--compare a.png b.png <tolerance>` — golden-image diff (used by CI)
- `--mcp` — MCP server over stdio

After a code change: `make test`. For renderer changes, `--render` a fixture
(scratch `.timeline` file) and look at the PNG in light and dark, then
`make docs` if `example.timeline` output changed. For UI changes, `make app`
and launch on a **scratch copy** of a document; don't drive the app with
synthetic mouse/keyboard events (it misfires on the maintainer's live
session) — have the maintainer try the interaction. Quitting/relaunching
Timeline closes every open document window, so ask first.

## Architecture

| File | Role |
|---|---|
| `TimelineRenderer.swift` | Core Graphics / Core Text renderer, PDF-style bottom-left coordinates. Layout, drawing, hit testing (`eventHit`, `day(at:)`, `dayColumn(at:)`). Shared by preview, export, print, Quick Look, MCP. Single source of truth. Two layouts: `.paged` (letter landscape PDF/print) and `.continuous` (canvas/PNG). |
| `Models.swift` | `Day` (timezone-free), `TimelineConfig`, `TimelineEvent`, `CustomHoliday`, config mutations (`shiftingEvent`, `removingEvent`, `duplicatingEvent`). |
| `ConfigYAML.swift` | Parse via Yams; serialize **by hand**. |
| `TimelineDocument.swift` | `ReferenceFileDocument`; all edits go through `document.update(_:undoManager:)` for undo. |
| `ContentView.swift` | Window: canvas, + button, toolbar (settings popover, focus, export, share), find panel, editor state, export/print, live reload from disk (`FileWatcher`), per-document zoom/focus saved in UserDefaults. |
| `PreviewView.swift` | Canvas: the renderer draws vectors straight into an `NSView` (`CanvasDrawing`; AppKit tiles it, so memory tracks the window, not the canvas); a transparent SwiftUI shape on top takes click/drag/drop/hover; the `EditorPopover` (hand-rolled `NSPopover`). |
| `EventEditor.swift` | Event form (quick-add NL field for + events, name, dates, Done/Important/Tentative, color, notes). |
| `EditorControls.swift` | Shared controls: `DayPicker`, `OptionalDayRow`, `CustomPaletteEditor`, `HolidayRow`, `Color(hex:)`, `EditorSwitchStyle`. |
| `TimelineSettings.swift` | Per-document settings popover (title, dates, days per row, shading, palette, custom holidays). |
| `Settings.swift` | App settings window (⌘,): `showTodayMarker`, `useAppleIntelligence`, `defaultPalette` (for new docs). |
| `Commands.swift` | Menu commands + shortcuts, routed to the key window via `focusedSceneValue(\.timelineActions)`. |
| `EventParser.swift` / `EventIntelligence.swift` | Deterministic NL parser (tested) + `.ics` parsing; optional Apple Intelligence parser (off by default — nondeterministic). |
| `EventSearch.swift` | ⌘F find panel. |
| `Exporter.swift` / `Sharing.swift` | PDF/PNG output; `ShareLink`/drag-out `Transferable`. |
| `MCPServer.swift` | `--mcp` JSON-RPC server; tools `create_timeline`, `read_timeline`, `add_events`, `update_event`, `remove_event`, `add_holiday`, `set_timeline_options`, `render_timeline`. |
| `DeepLink.swift` | `timeline://add-event` and `timeline://open`. |
| `Main.swift` | Entry point: CLI modes, else the SwiftUI app. |

Quick Look targets (`Sources/TimelineQuickLook`, `Sources/TimelineThumbnail`)
build from **symlinks** to `Models`, `ConfigYAML`, `TimelineRenderer`,
`USHolidays`. Plugin: `.claude-plugin/` (plugin + marketplace), `.mcp.json` →
`bin/timeline-mcp.sh`, `skills/timeline/SKILL.md`.

## `.timeline` format

Top level: `title`, `timeline_start`, `timeline_end` (omit both → bounds come
from events and past days aren't crossed off), `days_per_row` (3–60),
`shade_weekends`, `shade_holidays`, `palette` (name or list of hex),
`custom_holidays`, `events`. Event keys: `name`, `start`, `end` (makes a bar),
`done`, `important`, `tentative`, `notes`, `color`.

How flags render: done → gray + strikethrough; important → box around label;
tentative → hollow ring / dashed bar over a faint tint, italic label dimmed by
`Theme.tentativeAlpha`, with the axis clipped out from under the marker.
Unnamed events aren't drawn and take no palette slot (palette colors are
assigned chronologically).

**Adding an event field** touches: `Models`, `ConfigYAML` (parse + serialize),
`EventEditor`, `MCPServer` (`add_events` + `update_event` schemas and
handlers), `DeepLink`, renderer, `README.md`, `skills/timeline/SKILL.md`, and
the YAML/MCP round-trip tests in `SelfTests`.

## Canvas interactions

- Click an event → editor popover on the canvas. Drag an event to move it;
  drag a bar end to resize (one undo step per drag).
- Click empty space in a row's band (label area above the axis through the
  date labels below) → new event on that day, editor anchored there, no
  quick-add field, name field focused. Range bars sit on the axis and stack
  **upward**, so the date labels are never covered — clicking them always
  adds, even under a multi-day bar.
- While an editor is open, an empty click only closes it (never adds).
- "+" button → new event on today, editor anchored to the button, with the
  quick-add field. Return in the name field closes the editor; ⌘Return
  closes from anywhere.
- New events left blank are discarded on close; Escape discards a new event
  and just closes an existing one. Editor state in `ContentView`:
  `editingEventID`, `isNewEvent` (+ button), `isNewOnCanvas` (click-added).
- Drop text / calendar events (`.ics`) on the canvas → parsed into an event.
  ⇧⌘V creates one from clipboard text; ⇧⌘C copies the image.

## Patterns & gotchas

- Colors must be sRGB (`CGColor(srgbRed:)`) or the canvas mismatches SwiftUI.
- Renderer text uses **CoreText** attribute keys, not AppKit — the Quick Look
  appex targets don't link AppKit (`-e _NSExtensionMain` linker hack).
- The editor popover (`PreviewView.EditorPopover`) is a hand-rolled `NSPopover`
  with `behavior = .applicationDefined` (survives app switches; repositions in
  place when the edited event changes, otherwise stays put). Its host view is
  click-through (`hitTest` → nil). Its `anchorRect` is in bottom-left canvas
  coordinates. Size it with `NSHostingController.sizingOptions =
  [.preferredContentSize]`. Editor toggles use a pure-SwiftUI
  `EditorSwitchStyle`, because AppKit `NSSwitch` renders inactive-gray on first
  show inside an `.applicationDefined` popover.
- Don't go back to rendering the canvas as one bitmap `Image`: SwiftUI and
  CoreAnimation hold ~3 copies, which reached 430–770 MB for a year-long
  timeline. `drawPage` skips rows outside the clip so tile redraws stay
  cheap. Measure with `footprint <pid>`.
- No double-click handler on the canvas: pairing it with single-click delays
  every click ~0.3 s.
- In Swift, `"\r\n"` is a **single Character** — split lines on `\.isNewline`,
  not by comparing to `"\r"`/`"\n"` (real `.ics` files are CRLF).
- Image drag-out lives on the export **toolbar buttons** (`.onDrag`), not the
  canvas — the canvas drag gesture is reserved for moving events.
- `timeline://` only acts on `.timeline` files (the scheme is web-reachable and
  rewrites the target). The renderer clamps the span (~12 years) so a crafted/typo
  date range can't produce a giant bitmap.
- Multiple `Timeline.app` copies in different paths (worktrees, Trash) hijack
  Quick Look via LaunchServices; `make app` re-registers the active build.
- `ConfigYAML.serialize` folds newlines in notes to spaces on reload (minor);
  document autosave drops YAML comments.
- `bin/timeline-mcp.sh` builds the release binary only if it's missing, so a
  stale binary keeps serving old tools — `swift build -c release` after MCP
  changes. Installed plugins are a cached snapshot: bump
  `.claude-plugin/plugin.json` `version` and run `claude plugin update`.
- CI runners may have older Xcode — guard macOS-26-only APIs with `#if compiler`
  + `#available`.

## Conventions

- Commit per fix/feature (Conventional Commits); work on feature branches and
  merge into `main` with `--no-ff` (`Merge <feature>` messages).
- Release: annotated tag `git tag -a vX.Y.Z -m "vX.Y.Z — summary"`, push
  `main` and the tag. The tag triggers `.github/workflows/release.yml` (builds
  `Timeline.zip`, ad-hoc signed, GitHub release); `make app` reads the version
  from `git describe`. CI (`ci.yml`) on `main`/PRs builds, runs the self-tests,
  and compares the example render to `docs/example.png`.
- Versioning by user expectation: a redesign is a major bump (v2.0.0), additive
  features minor, fixes to obviously expected behavior patch — even when the fix
  is new code.
