#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  printf '%s\n' "Build an optimized arm64 Meeting Pulse release, DMG, and local installation."
  printf '%s\n' "Set MP_RELEASE_INSTALL=0 to skip replacing /Applications/Meeting Pulse.app."
  exit 0
fi
exec "$SCRIPT_DIR/build-release.sh" arm64 "$@"
