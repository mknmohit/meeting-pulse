#!/bin/sh
set -eu

PROCESS_NAME="${1:-Meeting Pulse}"
PID=$(pgrep -x "$PROCESS_NAME" || true)

if [ -z "$PID" ]; then
  printf '%s\n' "Meeting Pulse is not running." >&2
  exit 1
fi

printf '%s\n' "Memory (PASS if phys_footprint <= 80 MB):"
footprint -a "$PROCESS_NAME"

printf '%s\n' "CPU (PASS if average <= 1.0% over ten minutes):"
top -l 60 -s 10 -pid "$PID" -stats cpu |
  awk '/^[0-9]/{sum += $1; count += 1} END { if (count == 0) exit 1; printf "avg cpu%% %.2f\n", sum / count }'
