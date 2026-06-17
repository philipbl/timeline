# Timeline — project guide

Native SwiftUI macOS app for `.timeline` documents (plain YAML). Renders visual
timelines (dots for single days, bars for ranges) to a live canvas, PDF, PNG,
print, and Quick Look. Also ships an MCP server and Claude plugin. GPLv3.

Toolchain: Swift Package Manager only (no Xcode project) — Command Line Tools,
Swift 6.x, macOS 26 SDK. Package is in `TimelineApp/`.

## Build / test / run

```bash
make app        # assemble + sign build/Timeline.app (also runs lsregister)
make run-app    # build + launch
make test       # in-binary self-test suite (TimelineApp --self-test, debug only)
make docs       # regenerate docs/*.png golden images (CI compares against these)
```

There is no XCTest/swift-testing (no Xcode). Tests live in `SelfTests.swift` and
run via `--self-test`. Headless rendering for scripting/CI:
`TimelineApp --render in.timeline out.png|pdf [--dark]`.

After a code change: `make test`, and for UI changes rebuild + `make run-app` and
verify visually (or `--render` a fixture and inspect the PNG). Run `make docs`
whenever the renderer output changes, or the golden-image CI check fails.

## Architecture

- **Renderer** (`TimelineRenderer.swift`, Core Graphics / Core Text, PDF-style
  bottom-left coordinates) is shared by the live preview, PNG/PDF export, print,
  both Quick Look appexes, and the MCP server. Single source of truth for layout.
- **UI is canvas-first** (`ContentView` + `PreviewView`): no sidebar. A bottom-right
  "+" button opens a new-event editor popover; clicking an event opens an editor
  popover on the canvas; document settings (incl. custom holidays) live in a
  toolbar popover (`TimelineSettings`). Shared form controls are in
  `EditorControls.swift`.
- **Model**: `Models.swift` (`Day` is timezone-free; `TimelineConfig`,
  `TimelineEvent`, `CustomHoliday`). `ConfigYAML.swift` loads via Yams, serializes
  by hand. `TimelineDocument` is a `ReferenceFileDocument` (undo support).
- **Parsing**: `EventParser` (deterministic, tested) + `EventIntelligence`
  (Apple Intelligence, **opt-in** via `useAppleIntelligence` UserDefaults — it's
  nondeterministic, so off by default). `EventParser.parseICS` handles dropped
  calendar events.
- **Integrations**: `MCPServer.swift` (`--mcp`, JSON-RPC over stdio; repo is a
  Claude plugin + marketplace), `DeepLink.swift` (`timeline://` URL scheme).

## Patterns & gotchas

- Colors must be sRGB (`CGColor(srgbRed:)`) or the canvas mismatches SwiftUI.
- Renderer text uses **CoreText** attribute keys, not AppKit — the Quick Look
  appex targets don't link AppKit (they build from symlinked sources with an
  `-e _NSExtensionMain` linker hack).
- The editor popover (`PreviewView.EditorPopover`) is a hand-rolled `NSPopover`
  with `behavior = .applicationDefined` (survives app switches; repositions in
  place when switching events). Its host view is click-through (`hitTest` → nil).
  Size it with `NSHostingController.sizingOptions = [.preferredContentSize]`.
  Editor toggles use a pure-SwiftUI `EditorSwitchStyle`, because AppKit `NSSwitch`
  renders inactive-gray on first show inside an `.applicationDefined` popover.
- In Swift, `"\r\n"` is a **single Character** — split lines on `\.isNewline`,
  not by comparing to `"\r"`/`"\n"` (real `.ics` files are CRLF).
- Image drag-out lives on the export **toolbar buttons** (`.onDrag`), not the
  canvas — the canvas drag gesture is reserved for moving events.
- `timeline://` only acts on `.timeline` files (the scheme is web-reachable and
  rewrites the target). The renderer clamps the span (~12 years) so a crafted/typo
  date range can't produce a giant bitmap.
- Multiple `Timeline.app` copies in different paths (worktrees, Trash) hijack
  Quick Look via LaunchServices; `make app` re-registers the active build.
- `ConfigYAML.serialize` folds newlines in notes to spaces on reload (minor).
- CI runners may have older Xcode — guard macOS-26-only APIs with `#if compiler`
  + `#available`.

## Conventions

- Commit per fix/feature (Conventional Commits); work on feature branches and
  merge with `--no-ff`. Releases are cut by pushing a `vX.Y.Z` tag (the build
  reads the version from `git describe`).
- Versioning by user expectation: a redesign is a major bump (v2.0.0), additive
  features minor (v2.1.0+), behavior fixes patch.
