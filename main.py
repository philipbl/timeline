import arrow
import click
import holidays
from PIL import Image, ImageDraw, ImageFont

FONT_FILE = "Roboto-Regular.ttf"
us_holidays = holidays.UnitedStates()


def is_weekend_or_holiday(date):
    return date.weekday() in [5, 6] or date.datetime in us_holidays


def get_h_margin(events, font, extra_margin=100):
    im = Image.new("RGBA", (50, 50), color="white")
    draw = ImageDraw.Draw(im)

    text_length, text_height = draw.textsize(events[-1][1], font=font)
    return round(text_length / 2 + extra_margin)


def draw_ticks(
    draw,
    start_date,
    time_diff,
    day_size,
    start_x_pos,
    start_y_pos,
    tick_length,
    tick_width,
    date_font,
):
    y_pos = start_y_pos
    # Draw ticks for each day
    for i in range(time_diff + 1):
        x_pos = start_x_pos + i * day_size
        draw.line(
            [(x_pos, y_pos - tick_length / 2), (x_pos, y_pos + tick_length / 2),],
            fill="black",
            width=tick_width,
        )

        cur_date = start_date.shift(days=i)
        date_text = cur_date.format("M/D")
        text_length, text_height = draw.textsize(date_text, font=date_font)

        draw.text(
            (x_pos - text_length / 2, y_pos + 100),
            text=date_text,
            fill="black" if not is_weekend_or_holiday(cur_date) else "gray",
            font=date_font,
        )


def get_text_box(text, draw, font, x_pos, y_pos):
    text_length, text_height = draw.multiline_textsize(text, font=font)

    x_start = x_pos - text_length / 2
    x_end = x_pos + text_length / 2
    y_start = y_pos - text_height
    y_end = y_pos

    return (x_start, y_start), (x_end, y_end)


def intersects(box1, box2):
    return not (
        box1[0][0] > box2[1][0] + 100
        or box1[1][0] < box2[0][0]
        or box1[0][1] > box2[1][1]
        or box1[1][1] < box2[0][1]
    )


def draw_timeline(start_date, end_date, events, file_name, scale_factor=1):
    event_font = ImageFont.truetype(FONT_FILE, int(150 * scale_factor))

    time_diff = (end_date - start_date).days + 1
    day_size = int(500 * scale_factor)
    h_margins = get_h_margin(events, event_font)
    v_margins = 1000
    dot_size = int(80 * scale_factor)

    timeline_width = int(30 * scale_factor)

    im = Image.new(
        "RGBA", (time_diff * day_size + h_margins * 2, v_margins * 2), color="white"
    )
    draw = ImageDraw.Draw(im)

    # Draw main timeline
    draw.line(
        [(h_margins, v_margins), (im.size[0] - h_margins, v_margins)],
        fill="black",
        width=timeline_width,
    )

    draw_ticks(
        draw,
        start_date=start_date,
        time_diff=time_diff,
        day_size=day_size,
        start_x_pos=h_margins,
        start_y_pos=v_margins,
        tick_width=int(20 * scale_factor),
        tick_length=60,
        date_font=ImageFont.truetype(FONT_FILE, int(150 * scale_factor)),
    )

    # Draw events
    event_boxes = []
    for event in events:
        days_offset = (event[0] - start_date).days + 1
        event_text = event[1]

        x_pos = h_margins + days_offset * day_size
        y_pos = v_margins

        draw.ellipse(
            [
                (x_pos - dot_size / 2, y_pos - dot_size / 2),
                (x_pos + dot_size / 2, y_pos + dot_size / 2),
            ],
            fill="black",
        )

        y_offset = 120

        # Calculate location of text
        box = get_text_box(event_text, draw, event_font, x_pos, y_pos - y_offset)

        # Check to see if there is something already overlapping
        for event_box in event_boxes:
            if intersects(box, event_box):
                y_offset += 120
                box = get_text_box(
                    event_text, draw, event_font, x_pos, y_pos - y_offset
                )

        # Keep list of sizes of the text
        event_boxes.append(box)
        # draw.rectangle(event_boxes[-1], outline="black", width=5)

        draw.multiline_text(
            box[0], text=event_text, fill="black", font=event_font, align="center",
        )

    print(event_boxes)
    im.save(file_name, dpi=(300, 300))


@click.command()
@click.argument("events", nargs=-1)
@click.option("--start")
@click.option("--end")
def main(events, start, end):
    # Parse the events
    events = (e.split(" ", 1) for e in events)
    events = ((arrow.get(day), name) for day, name in events)
    events = sorted(events, key=lambda x: x[0])

    if start is None:
        start = arrow.now()
    else:
        start = arrow.get(start)

    if end is not None:
        end = arrow.get(end)
    else:
        end = events[-1][0]

    draw_timeline(start, end, events, "timeline.png", scale_factor=0.5)


if __name__ == "__main__":
    main()
