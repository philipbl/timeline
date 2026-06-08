"""
Timeline PDF Generator using ReportLab

This module generates PDF timelines with events, handling:
- Weekend and holiday graying
- Point events (red dots) and range events (red lines)
- Automatic wrapping for long timelines
- Vertical stacking for overlapping events

Usage:
    python timeline.py config.yaml
    python timeline.py config.yaml --output my_timeline.pdf
"""

import math
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
from reportlab.lib.colors import HexColor, gray, red, black


class Event:
    """Represents a timeline event with a name, start date, and optional end date."""

    def __init__(
        self,
        name: str,
        start: arrow.Arrow,
        end: Optional[arrow.Arrow] = None,
        done: bool = False,
    ):
        self.name = name
        self.start = start
        self.end = end
        self.is_range = end is not None
        self.done = done

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
        self.events = sorted(events, key=lambda e: e.start)
        self.output_file = output_file
        # custom_holidays is a list of tuples: (start_date, end_date)
        # For single-day holidays, start_date == end_date
        self.custom_holidays = custom_holidays or []
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
        # Add extra space at top if we have a title
        self.top_margin = self.base_top_margin + (0.4 * inch if title else 0)
        self.bottom_margin = 0.75 * inch

        # Timeline visual constants
        self.day_width = 30  # Width allocated per day
        self.timeline_height = 3  # Height of main timeline bar
        self.tick_height = 15  # Height of date ticks
        self.dot_radius = 4  # Radius for point events
        self.event_vertical_spacing = 20  # Spacing between stacked events
        self.event_base_offset = 25  # Base offset above timeline for events
        self.row_spacing = 1.5 * inch  # Vertical spacing between wrapped rows
        self.max_event_height = (
            1.2 * inch
        )  # Maximum height events can reach above timeline
        self.base_first_row_baseline_offset = 40 if title else 30
        self.title_label_vertical_padding = 8

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
        for holiday_start, holiday_end in self.custom_holidays:
            if holiday_start <= date <= holiday_end:
                return True

        return False

    def get_text_width(self, c: canvas.Canvas, text: str, font_size: int = 10) -> float:
        """Calculate the width of text in points."""
        c.setFont("Helvetica", font_size)
        return c.stringWidth(text, "Helvetica", font_size)

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

    def draw_timeline_row(
        self,
        c: canvas.Canvas,
        row_start_date: arrow.Arrow,
        num_days: int,
        y_baseline: float,
    ) -> None:
        """Draw a single row of the timeline with dates and ticks."""

        # Draw main timeline bar
        start_x = self.left_margin
        end_x = start_x + (num_days * self.day_width)

        # Draw gray background for weekend/holiday periods
        for i in range(num_days):
            current_date = row_start_date.shift(days=i)
            if self.is_weekend_or_holiday(current_date):
                x = start_x + (i * self.day_width)
                # Draw a light gray vertical band for this day
                c.setFillColorRGB(0.95, 0.95, 0.95)  # Light gray
                c.rect(
                    x - self.day_width / 2,
                    y_baseline - 40,
                    self.day_width,
                    55,
                    fill=1,
                    stroke=0,
                )

        c.setStrokeColor(black)
        c.setLineWidth(self.timeline_height)
        c.line(start_x, y_baseline, end_x, y_baseline)

        # Draw ticks and dates
        c.setFont("Helvetica", 8)
        c.setLineWidth(1)

        for i in range(num_days):
            current_date = row_start_date.shift(days=i)
            x = start_x + (i * self.day_width)

            # Determine color based on weekend/holiday status
            is_special = self.is_weekend_or_holiday(current_date)
            color = gray if is_special else black

            # Draw tick mark
            c.setStrokeColor(color)
            c.line(
                x,
                y_baseline - self.tick_height / 2,
                x,
                y_baseline + self.tick_height / 2,
            )

            # Draw date label
            c.setFillColor(color)
            date_text = current_date.format("M/D")
            text_width = self.get_text_width(c, date_text, 8)
            c.drawString(
                x - text_width / 2, y_baseline - self.tick_height - 12, date_text
            )

    def draw_past_day_markers(
        self,
        c: canvas.Canvas,
        row_start_date: arrow.Arrow,
        num_days: int,
        y_baseline: float,
    ) -> None:
        """Draw X marks on past days (before today)."""
        start_x = self.left_margin
        today = arrow.now().floor("day")

        for i in range(num_days):
            current_date = row_start_date.shift(days=i)
            if current_date < today:
                x = start_x + (i * self.day_width)
                x_size = 4
                c.setStrokeColor(black)
                c.setLineWidth(1.5)
                # Draw X on the timeline itself
                c.line(x - x_size, y_baseline - x_size, x + x_size, y_baseline + x_size)
                c.line(x - x_size, y_baseline + x_size, x + x_size, y_baseline - x_size)

    def draw_events_for_row(
        self,
        c: canvas.Canvas,
        row_start_date: arrow.Arrow,
        num_days: int,
        y_baseline: float,
    ) -> None:
        """Draw events that appear in this row."""

        row_end_date = row_start_date.shift(days=num_days - 1)
        start_x = self.left_margin

        # Track occupied text boxes for collision detection
        occupied_boxes = []
        # Track occupied Y levels for each X position range to ensure range events don't overlap
        occupied_ranges = []

        # Process events that overlap with this row
        for event in self.events:
            # Check if event overlaps with this row
            event_end = event.end if event.end else event.start

            if event.start > row_end_date or event_end < row_start_date:
                continue  # Event doesn't appear in this row

            # Calculate event position(s) within the row
            event_row_start = max(event.start, row_start_date)
            event_row_end = min(event_end, row_end_date)

            days_from_row_start = (event_row_start - row_start_date).days
            days_from_row_end = (event_row_end - row_start_date).days

            start_pos_x = start_x + (days_from_row_start * self.day_width)
            end_pos_x = start_x + (days_from_row_end * self.day_width)

            # If event continues beyond this row, extend line to indicate continuation
            if event_end > row_end_date:
                end_pos_x = start_x + (num_days * self.day_width)

            c.setFillColor(red)
            c.setStrokeColor(red)

            # Determine Y offset for this event based on range overlaps
            y_offset_for_line = 0
            if event.is_range:
                # Check if this range overlaps with any existing ranges
                for (
                    occupied_start_x,
                    occupied_end_x,
                    occupied_y_offset,
                ) in occupied_ranges:
                    # Check for X overlap (with some padding)
                    if not (
                        end_pos_x + 5 < occupied_start_x
                        or start_pos_x > occupied_end_x + 5
                    ):
                        # Overlapping, use a higher Y offset
                        y_offset_for_line = max(
                            y_offset_for_line, occupied_y_offset + 8
                        )

                # Record this range's position
                occupied_ranges.append((start_pos_x, end_pos_x, y_offset_for_line))

                # Draw a red line for range events
                c.setLineWidth(3)
                line_y = y_baseline + y_offset_for_line
                c.line(start_pos_x, line_y, end_pos_x, line_y)

                # Draw endcaps only if the event actually starts/ends in this row
                endcap_height = 8
                c.setLineWidth(3)

                # Draw start endcap only if event starts in this row
                if event.start >= row_start_date:
                    c.line(
                        start_pos_x,
                        line_y - endcap_height / 2,
                        start_pos_x,
                        line_y + endcap_height / 2,
                    )

                # Draw end endcap only if event ends in this row
                if event.end <= row_end_date:
                    c.line(
                        end_pos_x,
                        line_y - endcap_height / 2,
                        end_pos_x,
                        line_y + endcap_height / 2,
                    )

                # Use middle of the range for text positioning
                text_x = (start_pos_x + end_pos_x) / 2
            else:
                # Draw a red dot for point events
                c.circle(start_pos_x, y_baseline, self.dot_radius, fill=1, stroke=0)
                text_x = start_pos_x

            # Only draw label if event starts in this row (to avoid duplicate labels on wrapped events)
            should_draw_label = event.start >= row_start_date

            if should_draw_label:
                # Draw event label with collision avoidance
                c.setFont("Helvetica", 10)
                text_width = self.get_text_width(c, event.name, 10)
                text_height = 12

                # Try to place text at increasing heights until no collision
                y_offset = self.event_base_offset + y_offset_for_line
                max_attempts = 20
                attempt = 0

                while attempt < max_attempts:
                    text_x_pos = text_x - text_width / 2
                    text_y_pos = y_baseline + y_offset

                    # Make sure we don't go too high and push labels off the page
                    if y_offset > self.max_event_height:
                        # Place it at max height even if there's overlap
                        c.drawString(
                            text_x_pos, y_baseline + self.max_event_height, event.name
                        )
                        # Draw strikethrough if done
                        if event.done:
                            c.setStrokeColor(black)
                            c.setLineWidth(1.5)
                            c.line(
                                text_x_pos,
                                y_baseline
                                + self.max_event_height
                                + text_height / 2
                                - 3,
                                text_x_pos + text_width,
                                y_baseline
                                + self.max_event_height
                                + text_height / 2
                                - 3,
                            )
                            c.setStrokeColor(red)
                        occupied_boxes.append(
                            (
                                text_x_pos,
                                y_baseline + self.max_event_height,
                                text_width,
                                text_height,
                            )
                        )
                        break

                    if not self.check_text_overlap(
                        text_x_pos, text_y_pos, text_width, text_height, occupied_boxes
                    ):
                        # No collision, draw the text
                        c.drawString(text_x_pos, text_y_pos, event.name)
                        # Draw strikethrough if done
                        if event.done:
                            c.setStrokeColor(black)
                            c.setLineWidth(1.5)
                            c.line(
                                text_x_pos,
                                text_y_pos + text_height / 2 - 3,
                                text_x_pos + text_width,
                                text_y_pos + text_height / 2 - 3,
                            )
                            c.setStrokeColor(red)
                        occupied_boxes.append(
                            (text_x_pos, text_y_pos, text_width, text_height)
                        )
                        break

                    # Collision detected, try higher position
                    y_offset += self.event_vertical_spacing
                    attempt += 1

    def estimate_row_label_top(
        self, row_start_date: arrow.Arrow, num_days: int
    ) -> float:
        """Estimate highest Y position (relative to baseline) used by labels in a row."""
        row_end_date = row_start_date.shift(days=num_days - 1)
        start_x = self.left_margin

        occupied_boxes = []
        occupied_ranges = []
        text_height = 12
        max_label_top = 0.0

        for event in self.events:
            event_end = event.end if event.end else event.start

            if event.start > row_end_date or event_end < row_start_date:
                continue

            event_row_start = max(event.start, row_start_date)
            event_row_end = min(event_end, row_end_date)

            days_from_row_start = (event_row_start - row_start_date).days
            days_from_row_end = (event_row_end - row_start_date).days

            start_pos_x = start_x + (days_from_row_start * self.day_width)
            end_pos_x = start_x + (days_from_row_end * self.day_width)

            if event_end > row_end_date:
                end_pos_x = start_x + (num_days * self.day_width)

            y_offset_for_line = 0
            if event.is_range:
                for (
                    occupied_start_x,
                    occupied_end_x,
                    occupied_y_offset,
                ) in occupied_ranges:
                    if not (
                        end_pos_x + 5 < occupied_start_x
                        or start_pos_x > occupied_end_x + 5
                    ):
                        y_offset_for_line = max(
                            y_offset_for_line, occupied_y_offset + 8
                        )

                occupied_ranges.append((start_pos_x, end_pos_x, y_offset_for_line))
                text_x = (start_pos_x + end_pos_x) / 2
            else:
                text_x = start_pos_x

            should_draw_label = event.start >= row_start_date

            if not should_draw_label:
                continue

            text_width = stringWidth(event.name, "Helvetica", 10)
            y_offset = self.event_base_offset + y_offset_for_line
            max_attempts = 20
            attempt = 0

            while attempt < max_attempts:
                if y_offset > self.max_event_height:
                    placed_y = self.max_event_height
                    max_label_top = max(max_label_top, placed_y + text_height)
                    occupied_boxes.append(
                        (
                            text_x - text_width / 2,
                            placed_y,
                            text_width,
                            text_height,
                        )
                    )
                    break

                text_x_pos = text_x - text_width / 2
                text_y_pos = y_offset

                if not self.check_text_overlap(
                    text_x_pos,
                    text_y_pos,
                    text_width,
                    text_height,
                    occupied_boxes,
                ):
                    max_label_top = max(max_label_top, text_y_pos + text_height)
                    occupied_boxes.append(
                        (text_x_pos, text_y_pos, text_width, text_height)
                    )
                    break

                y_offset += self.event_vertical_spacing
                attempt += 1

        return max_label_top

    def get_first_row_baseline_offset(
        self, row_start_date: arrow.Arrow, num_days: int
    ) -> float:
        """Compute first-row baseline offset, increasing it for stacked labels under a title."""
        if not self.title:
            return self.base_first_row_baseline_offset

        max_label_top = self.estimate_row_label_top(row_start_date, num_days)
        required_gap = max_label_top + self.title_label_vertical_padding

        # title_y - baseline_y = offset + (top_margin - base_top_margin - 5)
        static_gap = self.top_margin - self.base_top_margin - 5
        required_offset = required_gap - static_gap

        return max(self.base_first_row_baseline_offset, required_offset)

    def generate(self) -> None:
        """Generate the PDF timeline."""
        c = canvas.Canvas(self.output_file, pagesize=landscape(letter))

        # Draw title if present
        if self.title:
            c.setFont("Helvetica-Bold", 16)
            c.setFillColor(black)
            title_width = c.stringWidth(self.title, "Helvetica-Bold", 16)
            title_x = (self.page_width - title_width) / 2
            title_y = self.page_height - self.base_top_margin - 5
            c.drawString(title_x, title_y, self.title)

        # Calculate number of rows needed
        num_rows = math.ceil(self.total_days / self.max_days_per_row)

        # Start from top of page
        current_date = self.start_date
        current_y = None

        for row in range(num_rows):
            # Calculate how many days in this row
            remaining_days = self.total_days - (row * self.max_days_per_row)
            days_in_row = min(self.max_days_per_row, remaining_days)

            if current_y is None:
                first_row_offset = self.get_first_row_baseline_offset(
                    current_date, days_in_row
                )
                current_y = self.page_height - self.top_margin - first_row_offset

            # Check if we need a new page
            if current_y < self.bottom_margin + self.row_spacing:
                c.showPage()
                # Draw title on new page if present
                if self.title:
                    c.setFont("Helvetica-Bold", 16)
                    c.setFillColor(black)
                    title_width = c.stringWidth(self.title, "Helvetica-Bold", 16)
                    title_x = (self.page_width - title_width) / 2
                    title_y = self.page_height - self.base_top_margin - 5
                    c.drawString(title_x, title_y, self.title)
                first_row_offset = self.get_first_row_baseline_offset(
                    current_date, days_in_row
                )
                current_y = self.page_height - self.top_margin - first_row_offset

            # Draw the timeline row
            self.draw_timeline_row(c, current_date, days_in_row, current_y)

            # Draw events for this row
            self.draw_events_for_row(c, current_date, days_in_row, current_y)

            # Draw X's on past days (drawn last so they appear on top)
            self.draw_past_day_markers(c, current_date, days_in_row, current_y)

            # Move to next row
            current_date = current_date.shift(days=days_in_row)
            current_y -= self.row_spacing

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

        if not name or not start_str:
            click.echo(f"Warning: Skipping invalid event: {event_data}", err=True)
            continue

        try:
            start = arrow.get(start_str)
            end = arrow.get(end_str) if end_str else None
            events.append(Event(name, start, end, done))
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
                    # Date range with start and end
                    start_str = holiday_data.get("start")
                    end_str = holiday_data.get("end")
                    if start_str and end_str:
                        start = arrow.get(start_str)
                        end = arrow.get(end_str)
                        custom_holidays.append((start, end))
                    elif start_str:
                        # Only start provided, treat as single day
                        date = arrow.get(start_str)
                        custom_holidays.append((date, date))
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
