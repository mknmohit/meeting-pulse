#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
BUILD_DIR="${MP_LOCAL_BUILD_DIR:-$ROOT/build/local}"
CONFIGURATION="${MP_LOCAL_CONFIGURATION:-Debug}"
PROJECT="$ROOT/mac-app/MeetingPulse.xcodeproj"
APP="$BUILD_DIR/Build/Products/$CONFIGURATION/Meeting Pulse.app"

if [ ! -f "$ROOT/mac-app/Config.xcconfig" ]; then
  printf '%s\n' "Meeting Pulse: mac-app/Config.xcconfig is required." >&2
  printf '%s\n' "Copy mac-app/Config.xcconfig.example and fill in local values first." >&2
  exit 1
fi

mkdir -p "$BUILD_DIR"

if [ "${MP_LOCAL_SIGNING:-adhoc}" = "none" ]; then
  xcodebuild \
    -project "$PROJECT" \
    -scheme MeetingPulse \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$BUILD_DIR" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    -disableAutomaticPackageResolution \
    build
  printf '%s\n' "Built unsigned local app: $APP"
else
  xcodebuild \
    -project "$PROJECT" \
    -scheme MeetingPulse \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$BUILD_DIR" \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY=- \
    -disableAutomaticPackageResolution \
    build
  codesign --verify --deep --strict "$APP"
  printf '%s\n' "Built ad-hoc signed local app: $APP"
fi

printf '%s\n' "This build is for local use only. It is not notarized or suitable for public distribution."
printf '%s\n' "Meeting Pulse stores local secrets in Application Support without a Keychain prompt."
printf '%s\n' "The first launch after the storage change starts setup again."
