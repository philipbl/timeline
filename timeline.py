"""
Timeline PDF Generator using ReportLab

This module generates PDF timelines with events, handling:
- Weekend and holiday graying, with holiday names under the dates
- Point events (colored dots) and range events (colored bars)
- Same-day point events split the dot into wedges (half-circles for two)
- Automatic wrapping for long timelines
- Vertical stacking for overlapping events
- Leader lines connecting labels to their markers
- X marks on past days

Usage:
    python timeline.py config.yaml
    python timeline.py config.yaml --output my_timeline.pdf
"""

import sys
from typing import List, Tuple, Optional

import arrow
import click
import holidays
import yaml
from reportlab.lib.pagesizes import letter, landscape
from reportlab.lib.units import inch
from reportlab.pdfgen import canvas
from reportlab.pdfbase.pdfmetrics import stringWidth
from reportlab.lib.colors import HexColor


# Bright, playful palette — still dark enough to double as label text
EVENT_COLORS = [
    "#FF6B6B",  # coral
    "#3A86FF",  # bright blue
    "#FF9F1C",  # tangerine
    "#9B5DE5",  # violet
    "#00A878",  # jade
    "#E84A8A",  # pink
]

COLOR_BAR = HexColor("#33333B")
COLOR_TICK = HexColor("#4C4C55")
COLOR_TICK_MUTED = HexColor("#B3B6BC")
COLOR_DATE = HexColor("#55555E")
COLOR_DATE_MUTED = HexColor("#A8ABB2")
COLOR_WEEKEND_BAND = HexColor("#F1F2F5")
COLOR_PAST_X = HexColor("#6E6E76")
COLOR_DONE = HexColor("#9A9AA2")
COLOR_TITLE = HexColor("#26262E")
COLOR_SUBTITLE = HexColor("#8A8A93")
COLOR_FOOTER = HexColor("#B8B8C0")


class Event:
    """Represents a timeline event with a name, start date, and optional end date."""

    def __init__(
        self,
        name: str,
        start: arrow.Arrow,
        end: Optional[arrow.Arrow] = None,
        done: bool = False,
        color=None,
    ):
        self.name = name
        self.start = start
        self.end = end
        self.is_range = end is not None
        self.done = done
        # None means "assign from the default palette"
        self.color = color

    def __repr__(self):
        status = " (done)" if self.done else ""
        if self.is_range:
            return f"Event({self.name}, {self.start.format('YYYY-MM-DD')} to {self.end.format('YYYY-MM-DD')}{status})"
        return f"Event({self.name}, {self.start.format('YYYY-MM-DD')}{status})"


class TimelineGenerator:
    """Generates PDF timelines from event data."""

    def __init__(
        self,
        events: List[Event],
        output_file: str = "timeline.pdf",
        timeline_start: Optional[arrow.Arrow] = None,
        timeline_end: Optional[arrow.Arrow] = None,
        custom_holidays: Optional[List[Tuple[arrow.Arrow, arrow.Arrow]]] = None,
        title: Optional[str] = None,
    ):
        # Assign default colors in chronological order so events adjacent
        # on the timeline never share a color (palette repeats only every
        # len(EVENT_COLORS)th event); explicit colors are left untouched
        self.events = sorted(events, key=lambda e: e.start)
        palette_index = 0
        for event in self.events:
            if event.color is None:
                event.color = HexColor(
                    EVENT_COLORS[palette_index % len(EVENT_COLORS)]
                )
                palette_index += 1
        self.output_file = output_file
        # custom_holidays entries are (start_date, end_date) or
        # (start_date, end_date, name); normalize to 3-tuples with the
        # name defaulting to None. Single-day holidays have start == end.
        self.custom_holidays = [
            (h[0], h[1], h[2] if len(h) > 2 else None)
            for h in (custom_holidays or [])
        ]
        self.us_holidays = holidays.UnitedStates()
        self.title = title

        # Determine timeline bounds
        if timeline_start:
            self.start_date = timeline_start
        else:
            self.start_date = arrow.now().to("UTC").floor("day")

        if timeline_end:
            self.end_date = timeline_end
        else:
            # Find the last date from events (either end date or start date)
            last_date = self.start_date
            for event in self.events:
                if event.end and event.end > last_date:
                    last_date = event.end
                elif event.start > last_date:
                    last_date = event.start
            self.end_date = last_date

        # PDF layout constants
        self.page_width, self.page_height = landscape(letter)
        self.left_margin = 0.75 * inch
        self.right_margin = 0.75 * inch
        self.base_top_margin = 0.75 * inch
        # Add extra space at top if we have a title (title + subtitle)
        self.top_margin = self.base_top_margin + (0.55 * inch if title else 0)
        self.bottom_margin = 0.75 * inch

        # Timeline visual constants
        self.day_width = 30  # Width allocated per day
        self.tick_height = 12  # Height of date ticks
        self.dot_radius = 4.5  # Radius for point events
        self.range_base_offset = 10  # Range bars float this far above the baseline
        self.range_stack_spacing = 9  # Extra offset per stacked range bar
        self.event_vertical_spacing = 16  # Spacing between stacked labels
        self.event_base_offset = 25  # Base offset above timeline for labels
        self.max_event_height = (
            1.2 * inch
        )  # Maximum height labels can reach above timeline
        self.row_depth_below = 52  # Space a row needs below its baseline
        self.label_font = ("Helvetica-Bold", 9)
        self.label_text_height = 12

        # Calculate max days per row
        self.usable_width = self.page_width - self.left_margin - self.right_margin
        self.max_days_per_row = int(self.usable_width / self.day_width)

        # Calculate total days
        self.total_days = (self.end_date - self.start_date).days + 1

    def is_weekend_or_holiday(self, date: arrow.Arrow) -> bool:
        """Check if a date is a weekend or holiday."""
        # Check weekend (Saturday=5, Sunday=6)
        if date.weekday() in [5, 6]:
            return True

        # Check US federal holidays
        if date.date() in self.us_holidays:
            return True

        # Check custom holidays (supports date ranges)
        for holiday_start, holiday_end, _ in self.custom_holidays:
            if holiday_start <= date <= holiday_end:
                return True

        return False

    def holiday_name(self, date: arrow.Arrow) -> Optional[str]:
        """Return the holiday name for a date, or None (weekends have no name)."""
        us_name = self.us_holidays.get(date.date())
        if us_name:
            # Strip "(observed)" so the observed day and the actual day
            # merge into a single label when adjacent
            return us_name.replace(" (observed)", "")

        for holiday_start, holiday_end, name in self.custom_holidays:
            if name and holiday_start <= date <= holiday_end:
                return name

        return None

    def is_past_day(self, date: arrow.Arrow) -> bool:
        """True if a date is before today in local time.

        Compares calendar dates (not instants) so a UTC-parsed event date
        isn't marked past while it is still today locally.
        """
        return date.date() < arrow.now().date()

    def check_text_overlap(
        self,
        x: float,
        y: float,
        width: float,
        height: float,
        existing_boxes: List[Tuple[float, float, float, float]],
    ) -> bool:
        """Check if a text box overlaps with any existing boxes."""
        padding = 5  # Add some padding for visual separation
        for ex, ey, ew, eh in existing_boxes:
            # Check if boxes overlap
            if not (
                x + width + padding < ex
                or x > ex + ew + padding
                or y + height + padding < ey
                or y > ey + eh + padding
            ):
                return True
        return False

    def layout_events_for_row(
        self, row_start_date: arrow.Arrow, num_days: int
    ) -> Tuple[List[dict], float]:
        """Compute marker and label positions (relative to the baseline) for a row.

        Returns (placements, max_label_top) where max_label_top is the highest
        point above the baseline used by any label.
        """
        row_end_date = row_start_date.shift(days=num_days - 1)
        start_x = self.left_margin
        bar_end_x = start_x + (num_days - 1) * self.day_width

        occupied_boxes = []
        occupied_ranges = []
        placements = []
        max_label_top = 0.0

        # Count point events sharing the same day so their dots can be
        # split into wedges (half-circles for two)
        point_counts = {}
        for event in self.events:
            if not event.is_range and row_start_date <= event.start <= row_end_date:
                key = event.start.format("YYYY-MM-DD")
                point_counts[key] = point_counts.get(key, 0) + 1
        point_seen = {}

        for event in self.events:
            event_end = event.end if event.end else event.start

            if event.start > row_end_date or event_end < row_start_date:
                continue  # Event doesn't appear in this row

            event_row_start = max(event.start, row_start_date)
            event_row_end = min(event_end, row_end_date)

            days_from_row_start = (event_row_start - row_start_date).days
            days_from_row_end = (event_row_end - row_start_date).days

            start_pos_x = start_x + (days_from_row_start * self.day_width)
            end_pos_x = start_x + (days_from_row_end * self.day_width)

            continues_left = event.start < row_start_date
            continues_right = event_end > row_end_date

            # Center the label over the visible portion of the event
            marker_x = (start_pos_x + end_pos_x) / 2 if event.is_range else start_pos_x

            # Extend continuing events slightly past the row edges (arrowheads added there)
            if continues_left:
                start_pos_x = start_x - 10
            if continues_right:
                end_pos_x = bar_end_x + 10

            # Stack overlapping range bars
            line_y_offset = 0
            if event.is_range:
                line_y_offset = self.range_base_offset
                for occ_start_x, occ_end_x, occ_y_offset in occupied_ranges:
                    if not (
                        end_pos_x + 5 < occ_start_x or start_pos_x > occ_end_x + 5
                    ):
                        line_y_offset = max(
                            line_y_offset, occ_y_offset + self.range_stack_spacing
                        )
                occupied_ranges.append((start_pos_x, end_pos_x, line_y_offset))
                # Register the bar as an obstacle so labels avoid it
                occupied_boxes.append(
                    (start_pos_x, line_y_offset - 4, end_pos_x - start_pos_x, 8)
                )

            wedge_index = 0
            wedge_count = 1
            if not event.is_range:
                key = event.start.format("YYYY-MM-DD")
                wedge_count = point_counts[key]
                wedge_index = point_seen.get(key, 0)
                point_seen[key] = wedge_index + 1

            placements.append(
                {
                    "event": event,
                    "is_range": event.is_range,
                    "start_x": start_pos_x,
                    "end_x": end_pos_x,
                    "marker_x": marker_x,
                    "line_y_offset": line_y_offset,
                    "continues_left": continues_left,
                    "continues_right": continues_right,
                    "wedge_index": wedge_index,
                    "wedge_count": wedge_count,
                    "label_x": None,
                    "label_y": None,
                    "text_width": 0,
                }
            )

        # Second pass: place labels once all bars are known, so labels
        # avoid both other labels and every range bar in the row.
        for placement in placements:
            event = placement["event"]

            # Only place a label if the event starts in this row
            # (avoids duplicate labels on wrapped events)
            if event.start < row_start_date:
                continue

            marker_x = placement["marker_x"]
            stack_extra = 0
            if placement["is_range"]:
                stack_extra = placement["line_y_offset"] - self.range_base_offset

            text_width = stringWidth(event.name, *self.label_font)
            text_height = self.label_text_height
            y_offset = self.event_base_offset + stack_extra
            max_attempts = 20

            for _ in range(max_attempts):
                if y_offset > self.max_event_height:
                    # Place at max height even if there's overlap
                    y_offset = self.max_event_height
                    break
                if not self.check_text_overlap(
                    marker_x - text_width / 2,
                    y_offset,
                    text_width,
                    text_height,
                    occupied_boxes,
                ):
                    break
                y_offset += self.event_vertical_spacing

            placement["label_x"] = marker_x - text_width / 2
            placement["label_y"] = y_offset
            placement["text_width"] = text_width
            occupied_boxes.append(
                (marker_x - text_width / 2, y_offset, text_width, text_height)
            )
            max_label_top = max(max_label_top, y_offset + text_height)

        return placements, max_label_top

    def draw_timeline_row(
        self,
        c: canvas.Canvas,
        row_start_date: arrow.Arrow,
        num_days: int,
        y_baseline: float,
    ) -> None:
        """Draw a single row of the timeline with dates and ticks."""

        start_x = self.left_margin
        bar_end_x = start_x + (num_days - 1) * self.day_width

        band_bottom = y_baseline - 40
        band_height = 54

        # Draw merged gray bands for consecutive weekend/holiday days
        i = 0
        while i < num_days:
            if self.is_weekend_or_holiday(row_start_date.shift(days=i)):
                j = i
                while j + 1 < num_days and self.is_weekend_or_holiday(
                    row_start_date.shift(days=j + 1)
                ):
                    j += 1
                band_x = start_x + (i * self.day_width) - self.day_width / 2
                band_width = (j - i + 1) * self.day_width
                c.setFillColor(COLOR_WEEKEND_BAND)
                c.roundRect(
                    band_x, band_bottom, band_width, band_height, 4, fill=1, stroke=0
                )
                i = j + 1
            else:
                i += 1

        # Draw main timeline bar
        c.setStrokeColor(COLOR_BAR)
        c.setLineWidth(2.5)
        c.setLineCap(1)  # Round caps
        c.line(start_x, y_baseline, bar_end_x, y_baseline)
        c.setLineCap(0)

        # Draw ticks and dates
        c.setLineWidth(1)

        for i in range(num_days):
            current_date = row_start_date.shift(days=i)
            x = start_x + (i * self.day_width)

            is_special = self.is_weekend_or_holiday(current_date)

            # Draw tick mark
            c.setStrokeColor(COLOR_TICK_MUTED if is_special else COLOR_TICK)
            c.line(
                x,
                y_baseline - self.tick_height / 2,
                x,
                y_baseline + self.tick_height / 2,
            )

            # Draw date label
            c.setFont("Helvetica", 8)
            c.setFillColor(COLOR_DATE_MUTED if is_special else COLOR_DATE)
            date_text = current_date.format("M/D")
            c.drawCentredString(x, y_baseline - self.tick_height / 2 - 12, date_text)

        # Holiday names under the dates. A name is centered in its gray
        # band when it is the band's only holiday; bands holding several
        # holidays center each name over its own days. Labels that would
        # overlap an earlier one are skipped.
        c.setFont("Helvetica-Oblique", 6.5)
        c.setFillColor(COLOR_SUBTITLE)
        last_label_end = float("-inf")
        i = 0
        while i < num_days:
            if not self.is_weekend_or_holiday(row_start_date.shift(days=i)):
                i += 1
                continue

            # Band run [i, j] of consecutive weekend/holiday days
            j = i
            while j + 1 < num_days and self.is_weekend_or_holiday(
                row_start_date.shift(days=j + 1)
            ):
                j += 1

            # Group the named days within the band
            groups = []
            k = i
            while k <= j:
                name = self.holiday_name(row_start_date.shift(days=k))
                if name:
                    g = k
                    while (
                        g + 1 <= j
                        and self.holiday_name(row_start_date.shift(days=g + 1))
                        == name
                    ):
                        g += 1
                    groups.append((name, k, g))
                    k = g + 1
                else:
                    k += 1

            for name, group_start, group_end in groups:
                if len(groups) == 1:
                    center_day = (i + j) / 2
                else:
                    center_day = (group_start + group_end) / 2
                center_x = start_x + center_day * self.day_width
                name_width = stringWidth(name, "Helvetica-Oblique", 6.5)
                if center_x - name_width / 2 > last_label_end + 4:
                    c.drawCentredString(center_x, y_baseline - 36, name)
                    last_label_end = center_x + name_width / 2

            i = j + 1

    def draw_past_day_markers(
        self,
        c: canvas.Canvas,
        row_start_date: arrow.Arrow,
        num_days: int,
        y_baseline: float,
    ) -> None:
        """Draw X marks on past days (before today)."""
        start_x = self.left_margin

        c.setStrokeColor(COLOR_PAST_X)
        c.setLineWidth(1.3)
        for i in range(num_days):
            current_date = row_start_date.shift(days=i)
            if self.is_past_day(current_date):
                x = start_x + (i * self.day_width)
                x_size = 3.5
                # Draw X on the timeline itself
                c.line(x - x_size, y_baseline - x_size, x + x_size, y_baseline + x_size)
                c.line(x - x_size, y_baseline + x_size, x + x_size, y_baseline - x_size)

    def draw_arrowhead(
        self, c: canvas.Canvas, x: float, y: float, direction: int, color
    ) -> None:
        """Draw a small triangle at (x, y) pointing left (-1) or right (+1)."""
        size = 5
        p = c.beginPath()
        p.moveTo(x, y - size * 0.8)
        p.lineTo(x + direction * size, y)
        p.lineTo(x, y + size * 0.8)
        p.close()
        c.setFillColor(color)
        c.drawPath(p, fill=1, stroke=0)

    def draw_events_for_row(
        self,
        c: canvas.Canvas,
        row_start_date: arrow.Arrow,
        num_days: int,
        y_baseline: float,
    ) -> None:
        """Draw events that appear in this row."""

        placements, _ = self.layout_events_for_row(row_start_date, num_days)

        for p in placements:
            event = p["event"]
            color = COLOR_DONE if event.done else event.color

            if p["is_range"]:
                # Draw a floating bar above the timeline for range events
                line_y = y_baseline + p["line_y_offset"]
                c.setStrokeColor(color)
                c.setLineWidth(4.5)
                c.setLineCap(1)  # Round caps
                c.line(p["start_x"], line_y, p["end_x"], line_y)
                c.setLineCap(0)

                # Arrowheads indicate the event continues on another row
                if p["continues_left"]:
                    self.draw_arrowhead(c, p["start_x"], line_y, -1, color)
                if p["continues_right"]:
                    self.draw_arrowhead(c, p["end_x"], line_y, 1, color)

                marker_top = p["line_y_offset"] + 4
            else:
                # Draw a colored dot for point events; events sharing a day
                # split the dot into wedges (half-circles for two)
                c.setFillColor(color)
                if p["wedge_count"] > 1:
                    r = self.dot_radius + 1  # slightly larger so wedges stay legible
                    extent = 360 / p["wedge_count"]
                    start_angle = 90 + p["wedge_index"] * extent
                    c.wedge(
                        p["marker_x"] - r,
                        y_baseline - r,
                        p["marker_x"] + r,
                        y_baseline + r,
                        start_angle,
                        extent,
                        fill=1,
                        stroke=0,
                    )
                    marker_top = r + 2
                else:
                    c.circle(
                        p["marker_x"], y_baseline, self.dot_radius, fill=1, stroke=0
                    )
                    marker_top = self.dot_radius + 2

            if p["label_y"] is None:
                continue

            label_y_abs = y_baseline + p["label_y"]

            # Leader line connecting a raised label back to its marker
            if p["label_y"] - 3 - marker_top > 10:
                c.setStrokeColor(color, alpha=0.4)
                c.setLineWidth(0.8)
                c.line(
                    p["marker_x"],
                    y_baseline + marker_top,
                    p["marker_x"],
                    label_y_abs - 3,
                )
                c.setStrokeAlpha(1)

            # Draw the label
            c.setFont(*self.label_font)
            c.setFillColor(color)
            c.drawString(p["label_x"], label_y_abs, event.name)

            if event.done:
                c.setStrokeColor(COLOR_DONE)
                c.setLineWidth(1.2)
                strike_y = label_y_abs + self.label_text_height / 2 - 3
                c.line(
                    p["label_x"], strike_y, p["label_x"] + p["text_width"], strike_y
                )

    def draw_page_header(self, c: canvas.Canvas) -> None:
        """Draw the title, subtitle, and footer on the current page."""
        if self.title:
            title_y = self.page_height - self.base_top_margin
            c.setFont("Helvetica-Bold", 18)
            c.setFillColor(COLOR_TITLE)
            c.drawCentredString(self.page_width / 2, title_y, self.title)

            subtitle = (
                f"{self.start_date.format('MMM D')} – "
                f"{self.end_date.format('MMM D, YYYY')}"
            )
            c.setFont("Helvetica", 9.5)
            c.setFillColor(COLOR_SUBTITLE)
            c.drawCentredString(self.page_width / 2, title_y - 16, subtitle)

        c.setFont("Helvetica", 7)
        c.setFillColor(COLOR_FOOTER)
        c.drawRightString(
            self.page_width - self.right_margin,
            0.4 * inch,
            f"Generated {arrow.now().format('MMM D, YYYY')}",
        )

    def generate(self) -> None:
        """Generate the PDF timeline."""
        c = canvas.Canvas(self.output_file, pagesize=landscape(letter))

        # Split the timeline into rows
        rows = []
        current_date = self.start_date
        remaining = self.total_days
        while remaining > 0:
            days_in_row = min(self.max_days_per_row, remaining)
            rows.append((current_date, days_in_row))
            current_date = current_date.shift(days=days_in_row)
            remaining -= days_in_row

        self.draw_page_header(c)
        page_top = self.page_height - self.top_margin
        current_y = None

        for row_date, days_in_row in rows:
            # Space rows based on how high this row's labels actually stack
            _, label_top = self.layout_events_for_row(row_date, days_in_row)
            label_top = max(label_top, self.event_base_offset + 12)
            gap_above = label_top + 8

            if current_y is None:
                current_y = page_top - gap_above
            else:
                current_y -= self.row_depth_below + gap_above

            # Check if we need a new page
            if current_y < self.bottom_margin + self.row_depth_below:
                c.showPage()
                self.draw_page_header(c)
                current_y = page_top - gap_above

            self.draw_timeline_row(c, row_date, days_in_row, current_y)
            self.draw_events_for_row(c, row_date, days_in_row, current_y)
            # X's on past days drawn last so they appear on top
            self.draw_past_day_markers(c, row_date, days_in_row, current_y)

        # Save the PDF
        c.save()


# CLI Interface
@click.command()
@click.argument("config_file", type=click.Path(exists=True))
@click.option(
    "--output",
    "-o",
    default="timeline.pdf",
    help="Output PDF filename (default: timeline.pdf)",
)
def main(config_file, output):
    """Generate a timeline PDF from a YAML configuration file.

    CONFIG_FILE: Path to the YAML configuration file containing events and settings.
    """

    # Load and parse the YAML configuration
    with open(config_file, "r") as f:
        config = yaml.safe_load(f)

    if not config:
        click.echo("Error: Configuration file is empty", err=True)
        sys.exit(1)

    # Parse events
    events = []
    event_list = config.get("events", [])

    if not event_list:
        click.echo("Error: No events found in configuration file", err=True)
        sys.exit(1)

    for event_data in event_list:
        name = event_data.get("name")
        start_str = event_data.get("start")
        end_str = event_data.get("end")
        done = event_data.get("done", False)
        color_str = event_data.get("color")

        if not name or not start_str:
            click.echo(f"Warning: Skipping invalid event: {event_data}", err=True)
            continue

        color = None
        if color_str:
            try:
                color = HexColor(color_str)
            except ValueError:
                click.echo(
                    f"Warning: Invalid color '{color_str}' for event '{name}', "
                    "using default palette",
                    err=True,
                )

        try:
            start = arrow.get(start_str)
            end = arrow.get(end_str) if end_str else None
            events.append(Event(name, start, end, done, color))
        except Exception as e:
            click.echo(f"Warning: Could not parse event '{name}': {e}", err=True)
            continue

    if not events:
        click.echo("Error: No valid events found in configuration file", err=True)
        sys.exit(1)

    # Parse optional timeline start/end overrides
    timeline_start = None
    timeline_end = None

    if "timeline_start" in config:
        try:
            timeline_start = arrow.get(config["timeline_start"])
        except Exception as e:
            click.echo(f"Warning: Could not parse timeline_start: {e}", err=True)

    if "timeline_end" in config:
        try:
            timeline_end = arrow.get(config["timeline_end"])
        except Exception as e:
            click.echo(f"Warning: Could not parse timeline_end: {e}", err=True)

    # Parse custom holidays (supports both single dates and date ranges)
    custom_holidays = []
    if "custom_holidays" in config:
        for holiday_data in config["custom_holidays"] or []:
            try:
                # Check if it's a string (single date) or dict (date range)
                if isinstance(holiday_data, str):
                    # Single date - start and end are the same
                    date = arrow.get(holiday_data)
                    custom_holidays.append((date, date))
                elif isinstance(holiday_data, dict):
                    # Date range with start, end, and optional name
                    start_str = holiday_data.get("start")
                    end_str = holiday_data.get("end")
                    holiday_name = holiday_data.get("name")
                    if start_str and end_str:
                        start = arrow.get(start_str)
                        end = arrow.get(end_str)
                        custom_holidays.append((start, end, holiday_name))
                    elif start_str:
                        # Only start provided, treat as single day
                        date = arrow.get(start_str)
                        custom_holidays.append((date, date, holiday_name))
                    else:
                        click.echo(
                            f"Warning: Invalid holiday data: {holiday_data}", err=True
                        )
                else:
                    click.echo(
                        f"Warning: Invalid holiday format: {holiday_data}", err=True
                    )
            except Exception as e:
                click.echo(
                    f"Warning: Could not parse holiday '{holiday_data}': {e}", err=True
                )

    # Parse optional title
    title = config.get("title")

    # Generate the timeline
    click.echo(f"Generating timeline with {len(events)} events...")

    TimelineGenerator(
        events,
        output,
        timeline_start,
        timeline_end,
        custom_holidays,
        title,
    ).generate()

    click.echo(f"✓ Timeline saved to: {output}")


if __name__ == "__main__":
    main()
