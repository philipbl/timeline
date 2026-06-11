---
name: timeline
description: Create, edit, and render visual timeline documents using the timeline MCP tools. Use when the user asks to create a timeline, schedule, or visual plan; add/change/remove events on a timeline; or render a timeline as a PNG or PDF.
---

# Timeline documents

`.timeline` files are plain YAML describing a horizontal timeline:
point events (dots), range events (bars), shaded weekends/holidays, and
automatic color assignment. Manage them with the `timeline` MCP tools.

## Workflow

1. `create_timeline` — set `timeline_start` (YYYY-MM-DD) when the user
   will track progress day by day (past days get crossed off); omit
   dates for a freeform/historical timeline (bounds infer from events).
2. `add_events` — batch all events in one call. An `end` date makes a
   bar; omitting it makes a dot. Mark deadlines `important: true`
   (boxed label) and finished items `done: true` (struck through).
3. `render_timeline` to a `.png` and **look at the returned image** —
   check for crowded labels or bad color pairings, adjust (e.g.
   `days_per_row` via `set_timeline_options`), and re-render.
4. Final output: render to `.pdf` for printing (US letter landscape,
   paged) or `.png` for sharing (single image; `dark: true` for a
   dark version).

## Conventions

- Dates are always `YYYY-MM-DD`.
- Event names must be unique within a document (updates match by name).
- Palettes: `bright` (default), `muted`, `jewel`, `ocean`, `sunset`,
  `forest`.
- US federal holidays shade automatically; `add_holiday` for custom
  ones (a `name` prints under the dates).
- To show the user the document in the native app: `open <file>.timeline`.
- Don't edit a file that's currently open in the Timeline app; it won't
  reload external changes.
