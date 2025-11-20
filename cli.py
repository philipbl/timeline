"""
CLI tool for generating timeline PDFs from YAML configuration files.

Usage:
    python cli.py config.yaml
    python cli.py config.yaml --output my_timeline.pdf
"""

import sys
from pathlib import Path

import arrow
import click
import yaml

from timeline import Event, create_timeline


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

        if not name or not start_str:
            click.echo(f"Warning: Skipping invalid event: {event_data}", err=True)
            continue

        try:
            start = arrow.get(start_str)
            end = arrow.get(end_str) if end_str else None
            events.append(Event(name, start, end))
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

    # Parse custom holidays
    custom_holidays = []
    if "custom_holidays" in config:
        for holiday_str in config["custom_holidays"]:
            try:
                custom_holidays.append(arrow.get(holiday_str))
            except Exception as e:
                click.echo(
                    f"Warning: Could not parse holiday '{holiday_str}': {e}", err=True
                )

    # Generate the timeline
    click.echo(f"Generating timeline with {len(events)} events...")
    create_timeline(
        events=events,
        output_file=output,
        timeline_start=timeline_start,
        timeline_end=timeline_end,
        custom_holidays=custom_holidays,
    )
    click.echo(f"✓ Timeline saved to: {output}")


if __name__ == "__main__":
    main()
