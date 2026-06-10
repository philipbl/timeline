"""Tests for the timeline PDF generator."""

import re

import arrow
from click.testing import CliRunner

from reportlab.lib.colors import HexColor

from timeline import EVENT_COLORS, Event, TimelineGenerator, main


def make_generator(events, **kwargs):
    kwargs.setdefault("timeline_start", arrow.get("2026-06-08"))
    return TimelineGenerator(events, **kwargs)


def point(name, date, done=False):
    return Event(name, arrow.get(date), done=done)


def span(name, start, end, done=False):
    return Event(name, arrow.get(start), arrow.get(end), done=done)


# ---------------------------------------------------------------------------
# Event and generator basics
# ---------------------------------------------------------------------------


def test_point_event_is_not_range():
    event = point("A", "2026-06-10")
    assert not event.is_range
    assert event.end is None


def test_range_event_is_range():
    event = span("A", "2026-06-10", "2026-06-12")
    assert event.is_range


def test_total_days_with_explicit_bounds():
    gen = make_generator(
        [point("A", "2026-06-10")],
        timeline_end=arrow.get("2026-06-17"),
    )
    assert gen.total_days == 10  # 6/8 through 6/17 inclusive


def test_end_date_inferred_from_latest_event():
    gen = make_generator(
        [
            point("A", "2026-06-10"),
            span("B", "2026-06-12", "2026-07-02"),
        ]
    )
    assert gen.end_date == arrow.get("2026-07-02")


def test_events_sorted_by_start():
    gen = make_generator(
        [point("Late", "2026-06-20"), point("Early", "2026-06-09")]
    )
    assert [e.name for e in gen.events] == ["Early", "Late"]


def test_event_colors_cycle_through_palette():
    events = [point(f"E{i}", "2026-06-10") for i in range(len(EVENT_COLORS) + 2)]
    gen = make_generator(events)
    assert gen.events[0].color == gen.events[len(EVENT_COLORS)].color
    assert gen.events[0].color != gen.events[1].color


def test_default_colors_assigned_in_date_order():
    # Colors follow timeline order regardless of YAML listing order, so
    # chronologically adjacent events never share a color
    late = point("Late", "2026-06-20")
    early = point("Early", "2026-06-09")
    make_generator([late, early])
    assert early.color == HexColor(EVENT_COLORS[0])
    assert late.color == HexColor(EVENT_COLORS[1])


def test_adjacent_events_never_share_color():
    events = [point(f"E{i}", f"2026-06-{9 + i}") for i in range(10)]
    gen = make_generator(events)
    for a, b in zip(gen.events, gen.events[1:]):
        assert a.color != b.color


def test_explicit_color_respected_and_skipped_in_palette():
    custom = Event("Custom", arrow.get("2026-06-10"), color=HexColor("#123456"))
    default = point("Default", "2026-06-11")
    make_generator([custom, default])
    assert custom.color == HexColor("#123456")
    # Palette assignment skips events with explicit colors
    assert default.color == HexColor(EVENT_COLORS[0])


def test_is_past_day_uses_local_dates():
    gen = make_generator([point("A", "2026-06-10")])
    today = arrow.now()
    assert gen.is_past_day(today.shift(days=-1))
    assert not gen.is_past_day(today)
    assert not gen.is_past_day(today.shift(days=1))


# ---------------------------------------------------------------------------
# Weekend and holiday detection
# ---------------------------------------------------------------------------


def test_weekend_detected():
    gen = make_generator([point("A", "2026-06-10")])
    assert gen.is_weekend_or_holiday(arrow.get("2026-06-13"))  # Saturday
    assert gen.is_weekend_or_holiday(arrow.get("2026-06-14"))  # Sunday
    assert not gen.is_weekend_or_holiday(arrow.get("2026-06-10"))  # Wednesday


def test_us_holiday_detected():
    gen = make_generator([point("A", "2026-06-10")])
    assert gen.is_weekend_or_holiday(arrow.get("2026-11-26"))  # Thanksgiving
    assert gen.is_weekend_or_holiday(arrow.get("2026-12-25"))  # Christmas


def test_custom_holiday_range_detected():
    gen = make_generator(
        [point("A", "2026-06-10")],
        custom_holidays=[(arrow.get("2026-06-15"), arrow.get("2026-06-17"))],
    )
    assert gen.is_weekend_or_holiday(arrow.get("2026-06-15"))
    assert gen.is_weekend_or_holiday(arrow.get("2026-06-17"))
    assert not gen.is_weekend_or_holiday(arrow.get("2026-06-18"))


def test_us_holiday_name():
    gen = make_generator([point("A", "2026-06-10")])
    assert gen.holiday_name(arrow.get("2026-11-26")) == "Thanksgiving Day"
    assert gen.holiday_name(arrow.get("2026-06-13")) is None  # plain Saturday


def test_observed_suffix_stripped_so_adjacent_days_merge():
    gen = make_generator([point("A", "2026-06-10")])
    # July 4, 2026 is a Saturday; July 3 is the observed holiday
    assert gen.holiday_name(arrow.get("2026-07-03")) == "Independence Day"
    assert gen.holiday_name(arrow.get("2026-07-04")) == "Independence Day"


def test_custom_holiday_name():
    gen = make_generator(
        [point("A", "2026-06-10")],
        custom_holidays=[
            (arrow.get("2026-06-15"), arrow.get("2026-06-17"), "Lab Retreat")
        ],
    )
    assert gen.holiday_name(arrow.get("2026-06-16")) == "Lab Retreat"
    assert gen.holiday_name(arrow.get("2026-06-18")) is None


def test_unnamed_custom_holiday_has_no_name_but_is_grayed():
    gen = make_generator(
        [point("A", "2026-06-10")],
        custom_holidays=[(arrow.get("2026-06-15"), arrow.get("2026-06-15"))],
    )
    assert gen.is_weekend_or_holiday(arrow.get("2026-06-15"))
    assert gen.holiday_name(arrow.get("2026-06-15")) is None


# ---------------------------------------------------------------------------
# Row layout
# ---------------------------------------------------------------------------


def get_placement(placements, name):
    return next(p for p in placements if p["event"].name == name)


def test_events_outside_row_excluded():
    gen = make_generator(
        [point("In", "2026-06-10"), point("Out", "2026-08-10")],
        timeline_end=arrow.get("2026-08-15"),
    )
    placements, _ = gen.layout_events_for_row(arrow.get("2026-06-08"), 10)
    names = [p["event"].name for p in placements]
    assert names == ["In"]


def test_wrapped_event_label_only_on_starting_row():
    gen = make_generator(
        [span("Wrap", "2026-06-12", "2026-06-25")],
        timeline_end=arrow.get("2026-06-30"),
    )
    row1, _ = gen.layout_events_for_row(arrow.get("2026-06-08"), 10)
    row2, _ = gen.layout_events_for_row(arrow.get("2026-06-18"), 10)

    assert get_placement(row1, "Wrap")["label_y"] is not None
    assert get_placement(row2, "Wrap")["label_y"] is None


def test_wrapped_event_continuation_flags():
    gen = make_generator(
        [span("Wrap", "2026-06-12", "2026-06-25")],
        timeline_end=arrow.get("2026-06-30"),
    )
    row1, _ = gen.layout_events_for_row(arrow.get("2026-06-08"), 10)
    row2, _ = gen.layout_events_for_row(arrow.get("2026-06-18"), 10)

    p1 = get_placement(row1, "Wrap")
    p2 = get_placement(row2, "Wrap")
    assert not p1["continues_left"] and p1["continues_right"]
    assert p2["continues_left"] and not p2["continues_right"]


def test_overlapping_ranges_stack_vertically():
    gen = make_generator(
        [
            span("A", "2026-06-09", "2026-06-12"),
            span("B", "2026-06-11", "2026-06-14"),
        ]
    )
    placements, _ = gen.layout_events_for_row(arrow.get("2026-06-08"), 10)
    a = get_placement(placements, "A")
    b = get_placement(placements, "B")
    assert b["line_y_offset"] > a["line_y_offset"]


def test_disjoint_ranges_share_baseline_offset():
    gen = make_generator(
        [
            span("A", "2026-06-09", "2026-06-10"),
            span("B", "2026-06-15", "2026-06-16"),
        ]
    )
    placements, _ = gen.layout_events_for_row(arrow.get("2026-06-08"), 10)
    a = get_placement(placements, "A")
    b = get_placement(placements, "B")
    assert a["line_y_offset"] == b["line_y_offset"] == gen.range_base_offset


def test_labels_do_not_overlap_each_other():
    # Several events crowded together force label stacking
    gen = make_generator(
        [
            point("Event Alpha", "2026-06-10"),
            point("Event Bravo", "2026-06-11"),
            point("Event Charlie", "2026-06-12"),
        ]
    )
    placements, _ = gen.layout_events_for_row(arrow.get("2026-06-08"), 10)
    boxes = [
        (p["label_x"], p["label_y"], p["text_width"], gen.label_text_height)
        for p in placements
    ]
    for i, (x, y, w, h) in enumerate(boxes):
        for ex, ey, ew, eh in boxes[i + 1 :]:
            overlap = not (x + w < ex or x > ex + ew or y + h < ey or y > ey + eh)
            assert not overlap


def test_labels_avoid_range_bars():
    # A label centered over a stacked bar must be pushed above it
    gen = make_generator(
        [
            span("Low", "2026-06-09", "2026-06-16"),
            span("High", "2026-06-10", "2026-06-15"),
        ]
    )
    placements, _ = gen.layout_events_for_row(arrow.get("2026-06-08"), 10)
    top_bar = max(p["line_y_offset"] for p in placements)
    for p in placements:
        assert p["label_y"] > top_bar


# ---------------------------------------------------------------------------
# Same-day point events (wedges / half-circles)
# ---------------------------------------------------------------------------


def test_same_day_points_split_into_half_circles():
    gen = make_generator(
        [point("A", "2026-06-10"), point("B", "2026-06-10")]
    )
    placements, _ = gen.layout_events_for_row(arrow.get("2026-06-08"), 10)
    a = get_placement(placements, "A")
    b = get_placement(placements, "B")
    assert a["wedge_count"] == b["wedge_count"] == 2
    assert {a["wedge_index"], b["wedge_index"]} == {0, 1}
    assert a["marker_x"] == b["marker_x"]


def test_three_same_day_points_get_thirds():
    gen = make_generator(
        [point(f"E{i}", "2026-06-10") for i in range(3)]
    )
    placements, _ = gen.layout_events_for_row(arrow.get("2026-06-08"), 10)
    assert all(p["wedge_count"] == 3 for p in placements)
    assert sorted(p["wedge_index"] for p in placements) == [0, 1, 2]


def test_lone_point_keeps_full_circle():
    gen = make_generator([point("A", "2026-06-10")])
    placements, _ = gen.layout_events_for_row(arrow.get("2026-06-08"), 10)
    assert placements[0]["wedge_count"] == 1


def test_same_day_point_and_range_do_not_split():
    gen = make_generator(
        [point("Dot", "2026-06-10"), span("Bar", "2026-06-10", "2026-06-12")]
    )
    placements, _ = gen.layout_events_for_row(arrow.get("2026-06-08"), 10)
    assert get_placement(placements, "Dot")["wedge_count"] == 1


# ---------------------------------------------------------------------------
# PDF generation
# ---------------------------------------------------------------------------


def count_pages(pdf_path):
    data = pdf_path.read_bytes()
    return len(re.findall(rb"/Type\s*/Page[^s]", data))


def test_generate_creates_valid_pdf(tmp_path):
    output = tmp_path / "out.pdf"
    gen = make_generator(
        [point("A", "2026-06-10"), span("B", "2026-06-12", "2026-06-20")],
        output_file=str(output),
        title="Test",
    )
    gen.generate()
    assert output.exists()
    assert output.read_bytes().startswith(b"%PDF")
    assert count_pages(output) == 1


def test_long_timeline_spans_multiple_pages(tmp_path):
    output = tmp_path / "out.pdf"
    gen = make_generator(
        [point("A", "2026-06-10")],
        timeline_end=arrow.get("2026-12-31"),
        output_file=str(output),
        title="Long",
    )
    gen.generate()
    assert count_pages(output) > 1


def test_generate_without_title(tmp_path):
    output = tmp_path / "out.pdf"
    gen = make_generator([point("A", "2026-06-10")], output_file=str(output))
    gen.generate()
    assert output.read_bytes().startswith(b"%PDF")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


VALID_CONFIG = """
title: "Test"
timeline_start: "2026-06-08"
events:
  - name: First
    start: 2026-06-10
  - name: Second
    start: 2026-06-12
    end: 2026-06-15
  - name: Finished
    start: 2026-06-09
    done: true
"""


def test_cli_generates_pdf(tmp_path):
    config = tmp_path / "config.yaml"
    config.write_text(VALID_CONFIG)
    output = tmp_path / "out.pdf"

    runner = CliRunner()
    result = runner.invoke(main, [str(config), "--output", str(output)])

    assert result.exit_code == 0, result.output
    assert output.exists()
    assert output.read_bytes().startswith(b"%PDF")


def test_cli_rejects_empty_config(tmp_path):
    config = tmp_path / "config.yaml"
    config.write_text("")

    runner = CliRunner()
    result = runner.invoke(main, [str(config)])

    assert result.exit_code == 1


def test_cli_rejects_config_without_events(tmp_path):
    config = tmp_path / "config.yaml"
    config.write_text("title: Nothing\n")

    runner = CliRunner()
    result = runner.invoke(main, [str(config)])

    assert result.exit_code == 1


def test_cli_parses_named_custom_holiday(tmp_path):
    config = tmp_path / "config.yaml"
    config.write_text(
        """
timeline_start: "2026-06-08"
custom_holidays:
  - "2026-06-15"
  - start: "2026-06-16"
    end: "2026-06-17"
    name: "Lab Retreat"
events:
  - name: A
    start: 2026-06-10
"""
    )
    output = tmp_path / "out.pdf"

    runner = CliRunner()
    result = runner.invoke(main, [str(config), "--output", str(output)])

    assert result.exit_code == 0, result.output
    assert output.exists()


def test_cli_parses_event_color(tmp_path):
    config = tmp_path / "config.yaml"
    config.write_text(
        """
timeline_start: "2026-06-08"
events:
  - name: Colored
    start: 2026-06-10
    color: "#123456"
"""
    )
    output = tmp_path / "out.pdf"

    runner = CliRunner()
    result = runner.invoke(main, [str(config), "--output", str(output)])

    assert result.exit_code == 0, result.output
    assert output.exists()


def test_cli_warns_on_invalid_color(tmp_path):
    config = tmp_path / "config.yaml"
    config.write_text(
        """
timeline_start: "2026-06-08"
events:
  - name: Bad Color
    start: 2026-06-10
    color: "not-a-color"
"""
    )
    output = tmp_path / "out.pdf"

    runner = CliRunner()
    result = runner.invoke(main, [str(config), "--output", str(output)])

    assert result.exit_code == 0, result.output
    assert "Invalid color" in result.output
    assert output.exists()


def test_cli_skips_invalid_events_with_warning(tmp_path):
    config = tmp_path / "config.yaml"
    config.write_text(
        """
timeline_start: "2026-06-08"
events:
  - name: Good
    start: 2026-06-10
  - name: Missing Start
"""
    )
    output = tmp_path / "out.pdf"

    runner = CliRunner()
    result = runner.invoke(main, [str(config), "--output", str(output)])

    assert result.exit_code == 0
    assert "Skipping invalid event" in result.output
    assert output.exists()


def test_cli_example_config_builds(tmp_path):
    # The example config shipped with the repo must stay valid
    output = tmp_path / "example.pdf"
    runner = CliRunner()
    result = runner.invoke(
        main, ["example_config.yaml", "--output", str(output)]
    )
    assert result.exit_code == 0, result.output
    assert output.exists()
