#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="内存管家"
EXECUTABLE_NAME="MemoryBar"
ARCH="$(uname -m)"
SDK_PATH="$(xcrun --show-sdk-path)"

cd "$ROOT_DIR"

APP_DIR="$ROOT_DIR/dist/${APP_NAME}.app"
CONTENTS_DIR="$APP_DIR/Contents"
BUILD_DIR="$ROOT_DIR/.build/app"

rm -rf "$APP_DIR"
mkdir -p "$BUILD_DIR" "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"

swiftc \
  -sdk "$SDK_PATH" \
  -target "${ARCH}-apple-macosx13.0" \
  "$ROOT_DIR"/Sources/MemoryBar/*.swift \
  -o "$BUILD_DIR/$EXECUTABLE_NAME"

cp "$BUILD_DIR/$EXECUTABLE_NAME" "$CONTENTS_DIR/MacOS/$EXECUTABLE_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
chmod +x "$CONTENTS_DIR/MacOS/$EXECUTABLE_NAME"

plutil -lint "$CONTENTS_DIR/Info.plist" >/dev/null

echo "$APP_DIR"
