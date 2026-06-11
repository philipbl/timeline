#!/bin/bash
# Launches the Timeline MCP server, building it first if needed.
# All build output goes to stderr; stdout is reserved for the protocol.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/TimelineApp/.build/release/TimelineApp"

if [ ! -x "$BIN" ]; then
  echo "timeline-mcp: building (first run)..." >&2
  (cd "$ROOT/TimelineApp" && swift build -c release) >&2
fi

exec "$BIN" --mcp
