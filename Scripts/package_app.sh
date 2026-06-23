#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
PRODUCT_NAME="toolKit"
APP_NAME="$PRODUCT_NAME.app"
BUNDLE_DIR="$ROOT_DIR/dist/$APP_NAME"
CONTENTS_DIR="$BUNDLE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
PLIST_TEMPLATE="$ROOT_DIR/AppBundle/Info.plist"

cd "$ROOT_DIR"

swift build --configuration release

BIN_PATH=""
for candidate in \
  "$BUILD_DIR/arm64-apple-macosx/release/$PRODUCT_NAME" \
  "$BUILD_DIR/apple/Products/Release/$PRODUCT_NAME" \
  "$BUILD_DIR/release/$PRODUCT_NAME"
do
  if [[ -x "$candidate" ]]; then
    BIN_PATH="$candidate"
    break
  fi
done

if [[ -z "$BIN_PATH" ]]; then
  echo "Could not find built binary for $PRODUCT_NAME" >&2
  exit 1
fi

rm -rf "$BUNDLE_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN_PATH" "$MACOS_DIR/$PRODUCT_NAME"
cp "$PLIST_TEMPLATE" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/AppBundle/toolKit.icns" "$RESOURCES_DIR/toolKit.icns"

/usr/bin/touch "$BUNDLE_DIR"
/usr/bin/codesign --force --deep --sign - "$BUNDLE_DIR" >/dev/null 2>&1 || true

echo "Created app bundle at: $BUNDLE_DIR"
