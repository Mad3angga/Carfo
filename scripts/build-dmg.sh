#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
cd "$PROJECT_ROOT"

APP_PATH="$PROJECT_ROOT/build/Carfo.app"
DMG_PATH="$PROJECT_ROOT/build/Carfo.dmg"
STAGING_DIR="$PROJECT_ROOT/build/dmg_staging"

if [[ ! -d "$APP_PATH" ]]; then
    print "==> Error: $APP_PATH does not exist. Run scripts/build-app.sh first."
    exit 1
fi

print "==> 1. Preparing staging directory for DMG..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

print "==> 2. Cloning Carfo.app into staging..."
cp -Rc "$APP_PATH" "$STAGING_DIR/Carfo.app"

print "==> 3. Creating /Applications symlink..."
ln -s /Applications "$STAGING_DIR/Applications"

if [[ -f "$PROJECT_ROOT/Support/Carfo.icns" ]]; then
    print "==> 4. Setting custom volume icon..."
    cp "$PROJECT_ROOT/Support/Carfo.icns" "$STAGING_DIR/.VolumeIcon.icns"
    SetFile -c icnC "$STAGING_DIR/.VolumeIcon.icns" 2>/dev/null || true
    SetFile -a V "$STAGING_DIR/.VolumeIcon.icns" 2>/dev/null || true
    SetFile -a C "$STAGING_DIR" 2>/dev/null || true
fi

print "==> 5. Creating compressed DMG image (UDZO)..."
rm -f "$DMG_PATH"
hdiutil create \
    -volname "Carfo" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH"

print "==> 6. Cleaning up staging directory..."
rm -rf "$STAGING_DIR"

print "==> 7. Verifying DMG integrity..."
MOUNT_DIR=$(mktemp -d /tmp/carfo_verify_XXXXXX)
hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT_DIR" -nobrowse -quiet
if [[ -d "$MOUNT_DIR/Carfo.app" && -L "$MOUNT_DIR/Applications" ]]; then
    print "==> DMG structure verified: Carfo.app and Applications symlink are present."
else
    print "==> Warning: DMG structure verification encountered an issue."
fi
hdiutil detach "$MOUNT_DIR" -quiet || true
rm -rf "$MOUNT_DIR"

print ""
print "==> SUCCESS: Carfo DMG created successfully!"
print "    Path:   $DMG_PATH"
print "    Size:   $(du -sh "$DMG_PATH" | cut -f1)"
print "    SHA256: $(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)"
