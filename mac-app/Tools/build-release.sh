#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
APP_NAME="Meeting Pulse"
APP_BUNDLE="$APP_NAME.app"
PROJECT="$ROOT/mac-app/MeetingPulse.xcodeproj"
VERSION="${MP_RELEASE_VERSION:-0.0.9}"
BUILD_NUMBER="${MP_RELEASE_BUILD_NUMBER:-1}"
INSTALL="${MP_RELEASE_INSTALL:-1}"

fail() {
  printf '%s\n' "build-release: $*" >&2
  exit 1
}

usage() {
  printf '%s\n' "Usage: $0 arm64|x86_64"
  printf '%s\n' "Builds an optimized, ad-hoc signed local release and installs it."
}

if [ "$#" -ne 1 ]; then
  usage >&2
  exit 2
fi

TARGET_ARCH="$1"
case "$TARGET_ARCH" in
  arm64) ARCH_LABEL="Apple-Silicon" ;;
  x86_64) ARCH_LABEL="Intel" ;;
  *)
    usage >&2
    fail "unsupported architecture '$TARGET_ARCH'."
    ;;
esac

case "$VERSION" in
  0.0.1|0.0.2|0.0.3|0.0.4|0.0.5|0.0.6|0.0.7|0.0.8|0.0.9) ;;
  *) fail "unsupported release version '$VERSION'; expected 0.0.1 through 0.0.9." ;;
esac

if [ ! -f "$ROOT/mac-app/Config.xcconfig" ]; then
  fail "mac-app/Config.xcconfig is required. Copy mac-app/Config.xcconfig.example first."
fi

for command_name in xcodebuild codesign lipo hdiutil ditto otool; do
  command -v "$command_name" >/dev/null 2>&1 || fail "required tool '$command_name' is not installed."
done

# The DMG helper needs an interpreter with Pillow and ds_store.
PYTHON="${MP_PYTHON:-python3}"
command -v "$PYTHON" >/dev/null 2>&1 \
  || fail "required tool 'python3' (Pillow, ds_store) is not installed."

DMG_SCRIPT="$ROOT/mac-app/Tools/build-dmg.sh"
[ -x "$DMG_SCRIPT" ] || fail "DMG helper is missing or not executable: $DMG_SCRIPT"

BUILD_DIR="${MP_RELEASE_BUILD_DIR:-$ROOT/build/release-$TARGET_ARCH}"
DMG_DIR="${MP_RELEASE_DMG_DIR:-$ROOT/build/dmg}"
ASSET_DIR="${MP_RELEASE_ASSET_DIR:-$ROOT/build/dmg-assets-$TARGET_ARCH}"
APP="$BUILD_DIR/Build/Products/Release/$APP_BUNDLE"
EXECUTABLE="$APP/Contents/MacOS/$APP_NAME"
PLIST="$APP/Contents/Info.plist"
DMG="$DMG_DIR/Meeting-Pulse-$VERSION-$ARCH_LABEL-$TARGET_ARCH.dmg"
LEGACY_DMG="$DMG_DIR/Meeting-Pulse-$VERSION-$TARGET_ARCH.dmg"

rm -rf "$BUILD_DIR"
rm -f "$LEGACY_DMG"
mkdir -p "$BUILD_DIR" "$DMG_DIR" "$ASSET_DIR"

printf '%s\n' "build-release: building $TARGET_ARCH Release app"
xcodebuild \
  -project "$PROJECT" \
  -scheme MeetingPulse \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  -destination "platform=macOS,arch=$TARGET_ARCH" \
  -disableAutomaticPackageResolution \
  ARCHS="$TARGET_ARCH" \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  DEBUG_INFORMATION_FORMAT=none \
  SWIFT_DEBUG_INFORMATION_FORMAT=none \
  GCC_GENERATE_DEBUGGING_SYMBOLS=NO \
  ENABLE_TESTABILITY=NO \
  DEAD_CODE_STRIPPING=YES \
  STRIP_INSTALLED_PRODUCT=YES \
  COPY_PHASE_STRIP=YES \
  SWIFT_COMPILATION_MODE=wholemodule \
  SWIFT_OPTIMIZATION_LEVEL=-O \
  GCC_OPTIMIZATION_LEVEL=3 \
  build

[ -d "$APP" ] || fail "Xcode did not produce $APP."
[ -x "$EXECUTABLE" ] || fail "built app executable is missing: $EXECUTABLE"

ACTUAL_ARCH=$(lipo -archs "$EXECUTABLE" | tr -d '[:space:]')
[ "$ACTUAL_ARCH" = "$TARGET_ARCH" ] || fail "expected $TARGET_ARCH app, got $ACTUAL_ARCH."

if otool -l "$EXECUTABLE" | grep -q '__DWARF'; then
  fail "built executable still contains DWARF debug sections."
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"

codesign --force --deep --sign - --options runtime "$APP"
codesign --verify --deep --strict "$APP"

BUILT_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")
BUILT_BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")
[ "$BUILT_VERSION" = "$VERSION" ] || fail "bundle version is $BUILT_VERSION, expected $VERSION."
[ "$BUILT_BUILD" = "$BUILD_NUMBER" ] || fail "bundle build is $BUILT_BUILD, expected $BUILD_NUMBER."

printf '%s\n' "build-release: creating $DMG"
MP_DMG_APP="$APP" \
MP_DMG_OUT_DIR="$DMG_DIR" \
MP_DMG_ASSET_DIR="$ASSET_DIR" \
MP_DMG_STAGE="$BUILD_DIR/dmg-stage" \
MP_DMG_VOLUME_NAME="$APP_NAME $VERSION ($ARCH_LABEL)" \
MP_DMG_VERSION="$VERSION" \
MP_DMG_ARCH="$TARGET_ARCH" \
MP_DMG_ARCH_LABEL="$ARCH_LABEL" \
MP_PYTHON="$PYTHON" \
"$DMG_SCRIPT"

[ -f "$DMG" ] || fail "DMG helper did not produce $DMG."
hdiutil verify "$DMG" >/dev/null

if [ "$INSTALL" = "1" ]; then
  INSTALL_ROOT="${TMPDIR:-/tmp}/meeting-pulse-install.$$"
  NEW_APP="$INSTALL_ROOT/$APP_BUNDLE"
  BACKUP_APP="$INSTALL_ROOT/previous.app"
  DESTINATION="/Applications/$APP_BUNDLE"

  rm -rf "$INSTALL_ROOT"
  mkdir -p "$INSTALL_ROOT"
  ditto "$APP" "$NEW_APP"

  if [ -e "$DESTINATION" ] || [ -L "$DESTINATION" ]; then
    mv "$DESTINATION" "$BACKUP_APP"
  fi

  if mv "$NEW_APP" "$DESTINATION"; then
    rm -rf "$BACKUP_APP" "$INSTALL_ROOT"
  else
    if [ -e "$BACKUP_APP" ] || [ -L "$BACKUP_APP" ]; then
      mv "$BACKUP_APP" "$DESTINATION" || fail "new app failed to install and the previous app could not be restored."
    fi
    rm -rf "$INSTALL_ROOT"
    fail "could not replace $DESTINATION."
  fi

  printf '%s\n' "build-release: installed $DESTINATION"
else
  printf '%s\n' "build-release: installation skipped (MP_RELEASE_INSTALL=$INSTALL)"
fi

printf '%s\n' "build-release: app=$APP"
printf '%s\n' "build-release: dmg=$DMG"
printf '%s\n' "build-release: ad-hoc signed; not notarized; first launch requires Finder Open or quarantine removal."
