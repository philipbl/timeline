# Timeline PDF Generator

A Python tool for creating professional timeline PDFs from YAML configuration files. Perfect for project planning, scheduling, and visualizing events over time.

## Features

- **PDF Output**: Generates native PDF timelines using ReportLab
- **Point & Range Events**: 
  - Red dots for single-date events
  - Red lines with endcaps for events with start and end dates
- **Smart Layout**:
  - Automatically wraps long timelines across multiple rows
  - Intelligently stacks overlapping range events at different vertical positions
  - Intelligently positions event labels to avoid text collisions
- **Weekend & Holiday Highlighting**: Weekends and holidays are displayed in gray
- **Flexible Date Ranges**: 
  - By default, timeline spans from first to last event
  - Optional override with custom start/end dates in config
- **Custom Holidays**: Add company-specific or personal holidays in addition to US federal holidays

## Installation

1. Clone or download this repository
2. Install dependencies:

```bash
pip install -r requirements.txt
```

Or install individually:
```bash
pip install reportlab PyYAML holidays arrow click
```

## Usage

### Basic Usage

```bash
python timeline.py config.yaml
```

This creates `timeline.pdf` in the current directory.

### Custom Output Filename

```bash
python timeline.py config.yaml --output my_project_timeline.pdf
# or
python timeline.py config.yaml -o schedule.pdf
```

## Configuration File Format

Create a YAML file with your events and settings:

```yaml
# Optional: Override the default timeline start/end dates
# By default, the timeline starts with the first event and ends with the last event
# timeline_start: "2025-11-01"
# timeline_end: "2025-12-31"

# Optional: Specify custom holidays in addition to US federal holidays
# Format: YYYY-MM-DD
custom_holidays:
  - "2025-11-29"  # Company holiday
  - "2025-12-24"  # Christmas Eve

# Events can have:
# - name: Required event name/label
# - start: Required start date (YYYY-MM-DD)
# - end: Optional end date (YYYY-MM-DD) - if omitted, shows as a dot; if present, shows as a line
events:
  - name: "Project Kickoff"
    start: "2025-11-20"
  
  - name: "Design Phase"
    start: "2025-11-21"
    end: "2025-11-27"
  
  - name: "Development Sprint 1"
    start: "2025-12-01"
    end: "2025-12-14"
  
  - name: "Code Review"
    start: "2025-12-10"
  
  - name: "Launch"
    start: "2025-12-30"
```

### Event Types

1. **Point Events** (single date):
   ```yaml
   - name: "Milestone"
     start: "2025-11-25"
   ```
   Displayed as a red dot with the name above it.

2. **Range Events** (start and end date):
   ```yaml
   - name: "Development Phase"
     start: "2025-11-20"
     end: "2025-12-15"
   ```
   Displayed as a red line with endcaps spanning the dates with the name above.

   **Note**: When multiple range events overlap in time, they are automatically drawn at different vertical offsets so they don't overlap visually.

### Configuration Options

- `timeline_start` (optional): Force timeline to start on a specific date
- `timeline_end` (optional): Force timeline to end on a specific date
- `custom_holidays` (optional): List of additional dates to gray out (beyond US federal holidays)
- `events` (required): List of events with name, start, and optional end dates

## Example

See `example_config.yaml` for a complete example that includes overlapping events. Run it with:

```bash
python timeline.py example_config.yaml
```

## How It Works

1. **Date Parsing**: Parses all event dates from the YAML configuration
2. **Timeline Calculation**: Determines timeline bounds (using first/last events or overrides)
3. **Row Wrapping**: If timeline is too wide for one row, automatically wraps to multiple rows
4. **Page Wrapping**: If multiple rows don't fit on one page, creates additional pages
4. **Event Placement**: 
   - Draws red dots for point events
   - Draws red lines with endcaps for range events
   - When range events overlap, draws them at different vertical positions
   - Positions event labels above the timeline
   - Stacks overlapping event labels vertically to avoid text collisions
6. **Visual Enhancements**:
   - Grays out weekends (Saturday/Sunday)
   - Grays out US federal holidays
   - Grays out custom holidays from config

## Tips

- Use meaningful event names (they appear above the timeline)
- For long timelines, the tool automatically wraps to multiple rows
- Overlapping events are automatically stacked vertically
- Date format in YAML must be YYYY-MM-DD
- Events are automatically sorted by start date

## Dependencies

- **reportlab**: PDF generation
- **PyYAML**: YAML configuration parsing
- **holidays**: US federal holiday detection
- **arrow**: Date/time handling
- **click**: CLI interface

## License

This project is open source and available for personal and commercial use.
