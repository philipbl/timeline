import math

import arrow
import holidays
from PIL import Image, ImageDraw, ImageFont

FONT_FILE = "Roboto-Regular.ttf"
us_holidays = holidays.UnitedStates()


def is_weekend_or_holiday(date, exclude):
    return date.weekday() in [5, 6] or date.datetime in us_holidays or date in exclude


def get_h_margin(events, font, extra_margin=100):
    im = Image.new("RGBA", (50, 50), color="white")
    draw = ImageDraw.Draw(im)

    # compute text size using modern Pillow API with fallbacks
    text = events[-1][1]
    bbox = draw.textbbox((0, 0), text, font=font)
    text_length = bbox[2] - bbox[0]
    # text_height = bbox[3] - bbox[1]

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
    date_space,
    date_font,
    exclude,
):
    y_pos = start_y_pos
    # Draw ticks for each day
    for i in range(time_diff + 1):
        x_pos = start_x_pos + i * day_size
        draw.line(
            [
                (x_pos, y_pos - tick_length / 2),
                (x_pos, y_pos + tick_length / 2),
            ],
            fill="black",
            width=tick_width,
        )

        cur_date = start_date.shift(days=i)
        date_text = cur_date.format("M/D")
        try:
            bbox = draw.textbbox((0, 0), date_text, font=date_font)
            text_length = bbox[2] - bbox[0]
            text_height = bbox[3] - bbox[1]
        except Exception:
            try:
                text_length, text_height = draw.textsize(date_text, font=date_font)
            except Exception:
                text_length, text_height = date_font.getsize(date_text)

        draw.text(
            (x_pos - text_length / 2, y_pos + date_space),
            text=date_text,
            fill="black" if not is_weekend_or_holiday(cur_date, exclude) else "gray",
            font=date_font,
        )


def get_text_box(text, draw, font, x_pos, y_pos):
    # compute multiline text bbox with fallbacks
    try:
        bbox = draw.multiline_textbbox((0, 0), text, font=font)
        text_length = bbox[2] - bbox[0]
        text_height = bbox[3] - bbox[1]
    except Exception:
        try:
            text_length, text_height = draw.multiline_textsize(text, font=font)
        except Exception:
            # approximate: use largest line width
            lines = text.splitlines()
            widths = [font.getsize(l)[0] for l in lines]
            text_length = max(widths) if widths else 0
            text_height = sum(font.getsize(l)[1] for l in lines)

    x_start = x_pos - text_length / 2
    x_end = x_pos + text_length / 2
    y_start = y_pos - text_height
    y_end = y_pos

    return (x_start, y_start), (x_end, y_end)


def intersects(box1, boxes):
    def _intersect(box1, box2):
        return not (
            box1[0][0] > box2[1][0] + 100
            or box1[1][0] < box2[0][0]
            or box1[0][1] > box2[1][1]
            or box1[1][1] < box2[0][1]
        )

    return any(_intersect(box1, box2) for box2 in boxes)


def draw_events(
    events,
    start_date,
    draw,
    start_x_pos,
    start_y_pos,
    y_offset,
    y_offset_spacing,
    day_size,
    dot_size,
    event_font,
    tick_width,
):
    event_boxes = []
    for event in events:
        days_offset = (event[0] - start_date).days
        event_text = event[1]

        x_pos = start_x_pos + days_offset * day_size
        y_pos = start_y_pos

        draw.ellipse(
            [
                (x_pos - dot_size / 2, y_pos - dot_size / 2),
                (x_pos + dot_size / 2, y_pos + dot_size / 2),
            ],
            fill="red",
        )

        y_pos -= y_offset

        # Calculate location of text
        box = get_text_box(event_text, draw, event_font, x_pos, y_pos)

        # Check to see if there is something already overlapping
        while intersects(box, event_boxes):
            y_pos -= y_offset_spacing
            box = get_text_box(
                event_text,
                draw,
                event_font,
                x_pos,
                y_pos,
            )

        # Keep list of sizes of the text
        event_boxes.append(box)
        # draw.rectangle(event_boxes[-1], outline="black", width=5)

        draw.multiline_text(
            box[0],
            text=event_text,
            fill="red",
            font=event_font,
            align="center",
        )


def draw_main_line(draw, start_x_pos, end_x_pos, y_pos, width):
    draw.line(
        [(start_x_pos, y_pos), (end_x_pos, y_pos)],
        fill="black",
        width=width,
    )


def draw_sub_timeline(
    draw,
    events,
    start_x_pos,
    end_x_pos,
    y_pos,
    timeline_width,
    start_date,
    time_diff,
    day_size,
    tick_width,
    tick_length,
    date_font,
    date_space,
    event_y_offset,
    event_y_offset_spacing,
    dot_size,
    event_font,
    exclude,
):
    draw_main_line(
        draw,
        start_x_pos,
        end_x_pos,
        y_pos,
        width=timeline_width,
    )

    draw_ticks(
        draw,
        start_date=start_date,
        time_diff=time_diff,
        day_size=day_size,
        start_x_pos=start_x_pos,
        start_y_pos=y_pos,
        tick_width=tick_width,
        tick_length=tick_length,
        date_space=date_space,
        date_font=date_font,
        exclude=exclude,
    )

    draw_events(
        events,
        start_date=start_date,
        draw=draw,
        start_x_pos=start_x_pos,
        start_y_pos=y_pos,
        y_offset=event_y_offset,
        y_offset_spacing=event_y_offset_spacing,
        day_size=day_size,
        dot_size=dot_size,
        event_font=event_font,
        tick_width=tick_width,
    )


def get_events(start, end, events):
    for e in events:
        if start <= e[0] <= end:
            yield e


def split(start_date, end_date, events, max_days=15):
    time_diff = (end_date - start_date).days + 1
    groups = math.ceil(time_diff / max_days)

    for i in range(1, groups + 1):
        new_end_date = start_date.shift(days=max_days - 1)

        if end_date < new_end_date:
            new_end_date = end_date

        print(
            start_date,
            new_end_date,
            new_end_date - start_date,
        )
        yield (
            start_date,
            new_end_date,
            list(get_events(start_date, new_end_date, events)),
        )
        start_date = new_end_date.shift(days=+1)


def draw_timeline(start_date, end_date, events, file_name, exclude):
    event_font = ImageFont.truetype(FONT_FILE, 55)
    max_days = 15
    day_size = 200
    rows = math.ceil((end_date - start_date).days / max_days)
    h_margins = 150
    v_margins = (8.5 * 300) / (rows + 1)

    im = Image.new("RGBA", (int(11 * 300), int(8.5 * 300)), color="white")
    draw = ImageDraw.Draw(im)

    for i, (sub_start_date, sub_end_date, sub_events) in enumerate(
        split(start_date, end_date, events, max_days=max_days)
    ):
        time_diff = (sub_end_date - sub_start_date).days
        print(time_diff)

        if sub_end_date != end_date:
            extra = 1
        else:
            extra = 0

        draw_sub_timeline(
            draw,
            events=sub_events,
            start_x_pos=h_margins,
            end_x_pos=h_margins + (time_diff + extra) * day_size,
            y_pos=v_margins * (i + 1),
            timeline_width=10,
            start_date=sub_start_date,
            time_diff=time_diff,
            day_size=day_size,
            tick_width=10,
            tick_length=40,
            date_font=ImageFont.truetype(FONT_FILE, 55),
            event_y_offset=60,
            event_y_offset_spacing=90,
            dot_size=30,
            date_space=40,
            event_font=event_font,
            exclude=exclude,
        )

    im.save(file_name, dpi=(300, 300), format="PNG")
