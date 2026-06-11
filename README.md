# Timeline

A native Mac app for creating timeline PDFs and images. Edit events in a
form, watch the timeline render live, and export to PDF or PNG.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/example-dark.png">
  <img alt="Example timeline" src="docs/example.png">
</picture>

## Features

- **Live preview** — the timeline re-renders as you type, with pinch
  zoom and panning; follows the system light/dark appearance
- **Point & range events** — dots for single days, bars for ranges;
  events sharing a day split the dot into half-circles
- **Smart layout** — wraps long timelines across rows, stacks
  overlapping ranges, and keeps labels from colliding (leader lines
  connect raised labels to their markers)
- **Weekends & holidays** — US federal holidays and weekends are shaded
  with names printed under the dates; add custom holidays, or turn
  shading off
- **Color palettes** — bright (default), muted, and jewel palettes;
  colors assign chronologically so neighboring events never match, with
  per-event overrides
- **Done events** — struck through and grayed out
- **Export** — paged PDF (US letter, landscape) or single PNG at up to
  288 dpi
- **Finder integration** — custom document icon and Quick Look
  previews for .timeline files (select one and press Space)

## Installing

Grab **Timeline.zip** from the latest GitHub release, unzip, and drag
Timeline.app to Applications. Builds are ad-hoc signed: right-click →
Open on first launch.

Releases are cut by pushing a version tag:

```bash
git tag v1.0.0 && git push origin v1.0.0
```

## Building from source

Requires Xcode command line tools (Swift 6).

```bash
make app       # build build/Timeline.app
make run-app   # build and launch
make test      # run the self-test suite
```

## Documents

The app saves `.timeline` files — plain YAML, friendly to version
control (existing `.yaml` configs open via File > Open):

```yaml
title: "Project Timeline"
timeline_start: "2026-06-08"   # optional; defaults to today
timeline_end: "2026-07-20"     # optional; defaults to the last event
days_per_row: 22               # optional; days per timeline row
shade_weekends: true           # optional; default true
shade_holidays: true           # optional; default true
palette: "bright"              # optional; bright | muted | jewel | ocean |
                               #   sunset | forest, or a custom color list:
                               #   palette: ["#D62828", "#003049", "#588157"]

custom_holidays:
  - start: "2026-07-08"
    end: "2026-07-09"
    name: "Lab Retreat"

events:
  - name: "Submit Paper"
    start: "2026-06-18"
  - name: "Family Visiting"
    start: "2026-07-01"
    end: "2026-07-07"
  - name: "Big Deadline"
    start: "2026-06-18"
    important: true            # boxed label
  - name: "Finished Task"
    start: "2026-06-09"
    done: true
    color: "#3A86FF"           # optional override
```

See [example.timeline](example.timeline) for a fuller example.

## Claude plugin

The repo is a Claude Code plugin: an MCP server for managing and
rendering timelines (PNG renders come back inline so the model can see
the result, PDF for print output) plus a skill that teaches Claude the
workflow.

```bash
claude plugin marketplace add philipbl/timeline   # or a local path
claude plugin install timeline@timeline
```

The server binary builds itself on first connection (needs Swift).
Tools: `create_timeline`, `read_timeline`, `add_events`,
`update_event`, `remove_event`, `add_holiday`, `set_timeline_options`,
`render_timeline`.

Manual registration without the plugin:

```bash
claude mcp add -s user timeline -- \
  /path/to/build/Timeline.app/Contents/MacOS/Timeline --mcp
```

Note: if a document is open in the app while Claude edits the file, the
app won't reload it automatically — close and reopen, or let Claude
work on files you don't have open.

## URL scheme

`timeline://` links work from Shortcuts, scripts, or other apps:

```
timeline://add-event?file=~/plan.timeline&name=Dentist&start=2026-06-15
timeline://add-event?file=~/plan.timeline&name=Trip&start=today&end=2026-06-20&important=true
timeline://open?file=~/plan.timeline
```

`add-event` accepts `name`, `start` (required; `YYYY-MM-DD` or `today`),
plus optional `end`, `done`, `important`, and `color`. If the document
is open, the window updates live; otherwise it opens.

## Headless rendering

The app binary doubles as a CLI for scripting and CI:

```bash
TimelineApp/.build/release/TimelineApp --render events.timeline out.pdf
TimelineApp/.build/release/TimelineApp --render events.timeline out.png
```
