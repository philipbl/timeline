import io
from pathlib import Path
import tempfile

import arrow
from flask import Flask, send_file, request

from timeline import draw_timeline

app = Flask(__name__)


@app.route("/generate")
def generate_timeline():

    if "events" not in request.args:
        return "Must provide at least one event", 400

    events = request.args.get("events")
    events = events.split(",")
    events = (e.split(" ", 1) for e in events)
    events = ((arrow.get(day), name) for day, name in events)
    events = sorted(events, key=lambda x: x[0])

    exclude = []

    start = request.args.get("start", arrow.now())
    start = arrow.get(start)

    end = request.args.get("end", events[-1][0])
    end = arrow.get(end)

    with tempfile.TemporaryDirectory() as tmp_dir:
        file_name = Path(tmp_dir) / "timeline.png"

        with open(file_name, "wb") as file:
            draw_timeline(start, end, events, file, exclude)

        return send_file(file_name)


if __name__ == "__main__":
    app.run(debug=True)
