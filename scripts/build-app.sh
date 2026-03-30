#!/bin/zsh
set -euo pipefail

ROOT_DIR=${0:A:h:h}
CONFIGURATION=${1:-debug}
MODE=${CONFIGURATION:l}
APP_NAME=VibeMD
APP_BUNDLE="$ROOT_DIR/build/$APP_NAME.app"
EXECUTABLE_PATH="$ROOT_DIR/.build/$MODE/$APP_NAME"
BUILD_PRODUCTS_DIR="$ROOT_DIR/.build/$MODE"

case "$MODE" in
  debug|release) ;;
  *)
    echo "Unsupported configuration: $CONFIGURATION"
    echo "Use 'debug' or 'release'."
    exit 1
    ;;
esac

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift toolchain unavailable. Install Xcode or the Command Line Tools first."
  exit 1
fi

mkdir -p "$ROOT_DIR/build"

# Build the Swift executable that backs the app bundle.
swift build -c "$MODE" --product "$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

# Assemble the minimal macOS app bundle structure.
cp "$ROOT_DIR/App/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$EXECUTABLE_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/App/Resources/$APP_NAME.icns" "$APP_BUNDLE/Contents/Resources/$APP_NAME.icns"

# Copy SwiftPM resource bundles so bundled CSS and other assets are available at runtime.
for resource_bundle in "$BUILD_PRODUCTS_DIR"/*.bundle(N); do
  cp -R "$resource_bundle" "$APP_BUNDLE/Contents/Resources/"
done

echo "Built local app bundle at $APP_BUNDLE"
