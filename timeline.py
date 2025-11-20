"""
Timeline PDF Generator using ReportLab

This module generates PDF timelines with events, handling:
- Weekend and holiday graying
- Point events (red dots) and range events (red lines)
- Automatic wrapping for long timelines
- Vertical stacking for overlapping events
"""

import math
from datetime import datetime, timedelta
from typing import List, Tuple, Optional

import arrow
import holidays
from reportlab.lib.pagesizes import letter, landscape
from reportlab.lib.units import inch
from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor, gray, red, black


class Event:
    """Represents a timeline event with a name, start date, and optional end date."""

    def __init__(
        self, name: str, start: arrow.Arrow, end: Optional[arrow.Arrow] = None
    ):
        self.name = name
        self.start = start
        self.end = end
        self.is_range = end is not None

    def __repr__(self):
        if self.is_range:
            return f"Event({self.name}, {self.start.format('YYYY-MM-DD')} to {self.end.format('YYYY-MM-DD')})"
        return f"Event({self.name}, {self.start.format('YYYY-MM-DD')})"


class TimelineGenerator:
    """Generates PDF timelines from event data."""

    def __init__(
        self,
        events: List[Event],
        output_file: str = "timeline.pdf",
        timeline_start: Optional[arrow.Arrow] = None,
        timeline_end: Optional[arrow.Arrow] = None,
        custom_holidays: Optional[List[arrow.Arrow]] = None,
    ):
        self.events = sorted(events, key=lambda e: e.start)
        self.output_file = output_file
        self.custom_holidays = custom_holidays or []
        self.us_holidays = holidays.UnitedStates()

        # Determine timeline bounds
        if timeline_start:
            self.start_date = timeline_start
        else:
            self.start_date = self.events[0].start if self.events else arrow.now()

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
        self.top_margin = 0.75 * inch
        self.bottom_margin = 0.75 * inch

        # Timeline visual constants
        self.day_width = 30  # Width allocated per day
        self.timeline_height = 3  # Height of main timeline bar
        self.tick_height = 15  # Height of date ticks
        self.dot_radius = 4  # Radius for point events
        self.event_vertical_spacing = 20  # Spacing between stacked events
        self.event_base_offset = 25  # Base offset above timeline for events
        self.row_spacing = 1.5 * inch  # Vertical spacing between wrapped rows

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

        # Check custom holidays
        for holiday in self.custom_holidays:
            if date.date() == holiday.date():
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

        c.setStrokeColor(black)
        c.setLineWidth(self.timeline_height)
        c.line(start_x, y_baseline, end_x, y_baseline)

        # Draw ticks and dates
        c.setFont("Helvetica", 8)
        c.setLineWidth(1)

        for i in range(num_days + 1):
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

            c.setFillColor(red)
            c.setStrokeColor(red)

            if event.is_range:
                # Draw a red line for range events
                c.setLineWidth(3)
                c.line(start_pos_x, y_baseline, end_pos_x, y_baseline)

                # Use middle of the range for text positioning
                text_x = (start_pos_x + end_pos_x) / 2
            else:
                # Draw a red dot for point events
                c.circle(start_pos_x, y_baseline, self.dot_radius, fill=1, stroke=0)
                text_x = start_pos_x

            # Draw event label with collision avoidance
            c.setFont("Helvetica", 10)
            text_width = self.get_text_width(c, event.name, 10)
            text_height = 12

            # Try to place text at increasing heights until no collision
            y_offset = self.event_base_offset
            max_attempts = 20
            attempt = 0

            while attempt < max_attempts:
                text_x_pos = text_x - text_width / 2
                text_y_pos = y_baseline + y_offset

                if not self.check_text_overlap(
                    text_x_pos, text_y_pos, text_width, text_height, occupied_boxes
                ):
                    # No collision, draw the text
                    c.drawString(text_x_pos, text_y_pos, event.name)
                    occupied_boxes.append(
                        (text_x_pos, text_y_pos, text_width, text_height)
                    )
                    break

                # Collision detected, try higher position
                y_offset += self.event_vertical_spacing
                attempt += 1

    def generate(self) -> None:
        """Generate the PDF timeline."""
        c = canvas.Canvas(self.output_file, pagesize=landscape(letter))

        # Calculate number of rows needed
        num_rows = math.ceil(self.total_days / self.max_days_per_row)

        # Start from top of page
        current_date = self.start_date
        current_y = self.page_height - self.top_margin

        for row in range(num_rows):
            # Calculate how many days in this row
            remaining_days = self.total_days - (row * self.max_days_per_row)
            days_in_row = min(self.max_days_per_row, remaining_days)

            # Check if we need a new page
            if current_y < self.bottom_margin + self.row_spacing:
                c.showPage()
                current_y = self.page_height - self.top_margin

            # Draw the timeline row
            self.draw_timeline_row(c, current_date, days_in_row, current_y)

            # Draw events for this row
            self.draw_events_for_row(c, current_date, days_in_row, current_y)

            # Move to next row
            current_date = current_date.shift(days=days_in_row)
            current_y -= self.row_spacing

        # Save the PDF
        c.save()
        print(f"Timeline saved to: {self.output_file}")


def create_timeline(
    events: List[Event],
    output_file: str = "timeline.pdf",
    timeline_start: Optional[arrow.Arrow] = None,
    timeline_end: Optional[arrow.Arrow] = None,
    custom_holidays: Optional[List[arrow.Arrow]] = None,
) -> None:
    """
    Create a timeline PDF from a list of events.

    Args:
        events: List of Event objects
        output_file: Output PDF filename
        timeline_start: Optional override for timeline start date
        timeline_end: Optional override for timeline end date
        custom_holidays: Optional list of custom holiday dates
    """
    generator = TimelineGenerator(
        events, output_file, timeline_start, timeline_end, custom_holidays
    )
    generator.generate()
