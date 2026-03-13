#!/bin/bash
# SnapForge DMG Builder — creates a distributable DMG for direct download
# Usage: ./scripts/build_dmg.sh

set -euo pipefail

APP_NAME="SnapForge"
SCHEME="SnapForge"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
DMG_DIR="$BUILD_DIR/dmg"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
DMG_NAME="${APP_NAME}.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"
VOLUME_NAME="$APP_NAME"

echo "🔨 Building $APP_NAME..."

# 1. Clean build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# 2. Build release archive
xcodebuild -project "$PROJECT_DIR/$APP_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" \
    archive \
    CODE_SIGN_IDENTITY="-" \
    2>&1 | tail -5

# 3. Export app from archive
if [ -d "$BUILD_DIR/$APP_NAME.xcarchive/Products/Applications/$APP_NAME.app" ]; then
    cp -R "$BUILD_DIR/$APP_NAME.xcarchive/Products/Applications/$APP_NAME.app" "$APP_PATH"
else
    echo "❌ Archive failed — app not found"
    exit 1
fi

echo "✅ Built $APP_NAME.app"

# 4. Create DMG staging directory
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"
cp -R "$APP_PATH" "$DMG_DIR/"

# Create symlink to /Applications
ln -s /Applications "$DMG_DIR/Applications"

# 5. Create DMG
echo "📦 Creating DMG..."
hdiutil create -volname "$VOLUME_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov -format UDZO \
    "$DMG_PATH"

# 6. Cleanup staging
rm -rf "$DMG_DIR"
rm -rf "$BUILD_DIR/DerivedData"
rm -rf "$BUILD_DIR/$APP_NAME.xcarchive"

# 7. Print result
DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ DMG created successfully!"
echo "   📁 $DMG_PATH"
echo "   📏 Size: $DMG_SIZE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
