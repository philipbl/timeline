import math
import re
from datetime import datetime

import arrow
import click
import holidays
from PIL import Image, ImageDraw, ImageFont

from timeline import draw_timeline


@click.command()
@click.argument("events", nargs=-1)
@click.option("--start")
@click.option("--end")
@click.option("--exclude", multiple=True)
@click.option("--file_name", default="timeline.png")
def main(events, start, end, exclude, file_name):
    if len(events) == 0:
        print("You must pass in at least one event")
        exit()

    # Parse the events. Support three input styles:
    #  - Single quoted string: "2025-11-25 event name"
    #  - Separate tokens: 11/24 test
    #  - Short dates like MM/DD or MM/DD/YY (assume current century/year)

    def normalize_day(day_str):
        # MM/DD -> assume current year
        if re.match(r"^\d{1,2}/\d{1,2}$", day_str):
            year = datetime.now().year
            return arrow.get(f"{year}/{day_str}", "YYYY/M/D")

        # MM/DD/YY -> expand to YYYY (assume 20XX)
        m = re.match(r"^(\d{1,2})/(\d{1,2})/(\d{2})$", day_str)
        if m:
            month, day, yy = m.groups()
            year = 2000 + int(yy)
            return arrow.get(f"{year}/{month}/{day}", "YYYY/M/D")

        # Try arrow's parser for other formats (YYYY-MM-DD, ISO, etc.)
        return arrow.get(day_str)

    # Build (day, name) pairs from tokens
    tokens = list(events)
    parsed = []
    i = 0
    while i < len(tokens):
        token = tokens[i]
        # If token contains a space it was passed as a single argument
        if " " in token:
            day, name = token.split(" ", 1)
            parsed.append((normalize_day(day), name))
            i += 1
            continue

        # Otherwise treat token as date and the next token as the name (if present)
        if i + 1 < len(tokens):
            day = token
            name = tokens[i + 1]
            parsed.append((normalize_day(day), name))
            i += 2
            continue

        # Single leftover token that isn't parsable
        raise click.UsageError(f"Could not parse event token: {token}. Use 'DATE NAME' or quote the whole event.")

    events = sorted(parsed, key=lambda x: x[0])

    if start is None:
        start = arrow.now()
    else:
        start = arrow.get(start)

    if end is not None:
        end = arrow.get(end)
    else:
        end = events[-1][0]

    exclude = [arrow.get(e) for e in exclude]

    with open(file_name, "wb") as f:
        draw_timeline(start, end, events, f, exclude)


if __name__ == "__main__":
    main()
