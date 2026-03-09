#!/bin/bash
# Build ham_net_manager as a Linux AppImage

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_ROOT/build"
LINUX_BUILD_DIR="$BUILD_DIR/linux/x64/release/bundle"
APPIMAGE_BUILD_DIR="$BUILD_DIR/appimage"
APPDIR="$APPIMAGE_BUILD_DIR/ham_net_manager.AppDir"
OUTPUT_DIR="$PROJECT_ROOT/dist"

# Version from pubspec.yaml
VERSION=$(grep "^version:" "$PROJECT_ROOT/pubspec.yaml" | awk '{print $2}' | cut -d'+' -f1)

echo "Building Ham Net Manager AppImage (v$VERSION)"
echo "=============================================="

# Step 0: Sync version constant into Dart source
echo "Step 0: Syncing version to lib/app_version.dart..."
APP_VERSION_DART="$PROJECT_ROOT/lib/app_version.dart"
sed -i "s/const kAppVersion = '.*'/const kAppVersion = '$VERSION'/" "$APP_VERSION_DART"

# Step 1: Build Flutter release for Linux
echo "Step 1: Building Flutter Linux release..."
flutter build linux --release

# Step 2: Create AppDir — mirror the Flutter bundle layout exactly at the root
# Flutter's engine resolves lib/ and data/ relative to the executable directory,
# so they must be siblings of the binary (not in a subdirectory).
echo "Step 2: Creating AppDir structure..."
rm -rf "$APPDIR"
mkdir -p "$APPDIR"
mkdir -p "$APPDIR/share/"{applications,"icons/hicolor/256x256/apps","icons/hicolor/512x512/apps"}

# Step 3: Copy entire Flutter bundle to AppDir root
echo "Step 3: Copying Flutter bundle..."
cp "$LINUX_BUILD_DIR/ham_net_manager" "$APPDIR/"
chmod +x "$APPDIR/ham_net_manager"

if [ -d "$LINUX_BUILD_DIR/lib" ]; then
    cp -r "$LINUX_BUILD_DIR/lib" "$APPDIR/"
fi

if [ -d "$LINUX_BUILD_DIR/data" ]; then
    cp -r "$LINUX_BUILD_DIR/data" "$APPDIR/"
fi

# Step 4: Desktop entry and icons
echo "Step 4: Creating desktop entry..."
cp "$PROJECT_ROOT/linux/com.hamnetmanager.desktop" "$APPDIR/share/applications/"
ln -sf share/applications/com.hamnetmanager.desktop "$APPDIR/com.hamnetmanager.desktop" 2>/dev/null || true

echo "Step 5: Copying icons..."
if [ -f "$PROJECT_ROOT/linux/icons/256.png" ]; then
    cp "$PROJECT_ROOT/linux/icons/256.png" \
        "$APPDIR/share/icons/hicolor/256x256/apps/com.hamnetmanager.png"
    cp "$PROJECT_ROOT/linux/icons/256.png" "$APPDIR/com.hamnetmanager.png"
fi
if [ -f "$PROJECT_ROOT/linux/icons/512.png" ]; then
    cp "$PROJECT_ROOT/linux/icons/512.png" \
        "$APPDIR/share/icons/hicolor/512x512/apps/com.hamnetmanager.png"
fi

# Step 6: AppRun
echo "Step 6: Creating AppRun script..."
cp "$PROJECT_ROOT/linux/AppRun" "$APPDIR/"
chmod +x "$APPDIR/AppRun"

# Step 7: Build AppImage
echo "Step 7: Building AppImage..."
if ! command -v appimagetool &> /dev/null; then
    echo "ERROR: appimagetool not found!"
    echo "Download it from: https://github.com/AppImage/appimagetool/releases/latest"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"
APPIMAGE_NAME="Ham_Net_Manager-$VERSION-x86_64.AppImage"
APPIMAGE_PATH="$OUTPUT_DIR/$APPIMAGE_NAME"

appimagetool "$APPDIR" "$APPIMAGE_PATH"
chmod +x "$APPIMAGE_PATH"

echo ""
echo "✓ AppImage created successfully!"
echo "  Location: $APPIMAGE_PATH"
echo ""
echo "To run: $APPIMAGE_PATH"
