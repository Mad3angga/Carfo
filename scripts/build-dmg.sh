#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
cd "$PROJECT_ROOT"

APP_PATH="$PROJECT_ROOT/build/Carfo.app"
DMG_PATH="$PROJECT_ROOT/build/Carfo.dmg"
STAGING_DIR="$PROJECT_ROOT/build/dmg_staging"
DISTRIBUTION="${DISTRIBUTION:-0}"
DMG_COMPRESSION_LEVEL="${DMG_COMPRESSION_LEVEL:-6}"
[[ "$DMG_COMPRESSION_LEVEL" == [1-9] ]] || { print -u2 "DMG_COMPRESSION_LEVEL must be 1 through 9"; exit 1; }
MOUNT_DIR=""
cleanup() {
    if [[ -n "$MOUNT_DIR" ]]; then
        hdiutil detach "$MOUNT_DIR" -quiet || true
        rmdir "$MOUNT_DIR" 2>/dev/null || true
    fi
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

if [[ ! -d "$APP_PATH" ]]; then
    print "==> Error: $APP_PATH does not exist. Run scripts/build-app.sh first."
    exit 1
fi
codesign --verify --deep --strict "$APP_PATH"
if [[ "$DISTRIBUTION" == 1 ]]; then
    : "${SIGNING_IDENTITY:?Developer ID Application identity required}"
    : "${NOTARY_PROFILE:?notarytool keychain profile required}"
    [[ "$SIGNING_IDENTITY" == "Developer ID Application:"* ]] || exit 1
    xcrun stapler validate "$APP_PATH"
    spctl --assess --type execute --verbose=2 "$APP_PATH"
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
    -imagekey "zlib-level=$DMG_COMPRESSION_LEVEL" \
    "$DMG_PATH"
hdiutil verify "$DMG_PATH"
if [[ "$DISTRIBUTION" == 1 ]]; then
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG_PATH"
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
fi

print "==> 6. Cleaning up staging directory..."
rm -rf "$STAGING_DIR"

print "==> 7. Verifying DMG integrity..."
MOUNT_DIR=$(mktemp -d /tmp/carfo_verify_XXXXXX)
hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT_DIR" -nobrowse -quiet
if [[ -d "$MOUNT_DIR/Carfo.app" && -L "$MOUNT_DIR/Applications" && "$(readlink "$MOUNT_DIR/Applications")" == /Applications ]]; then
    print "==> DMG structure verified: Carfo.app and Applications symlink are present."
else
    print -u2 "DMG structure verification failed."
    exit 1
fi
codesign --verify --deep --strict "$MOUNT_DIR/Carfo.app"
"$MOUNT_DIR/Carfo.app/Contents/Resources/Python/bin/python3" -I -B scripts/smoke-startup.py "$MOUNT_DIR/Carfo.app" --output "$PROJECT_ROOT/build/dmg-startup-smoke.json"
if [[ "$DISTRIBUTION" == 1 ]]; then
    spctl --assess --type execute --verbose=2 "$MOUNT_DIR/Carfo.app"
fi
hdiutil detach "$MOUNT_DIR" -quiet
rmdir "$MOUNT_DIR"
MOUNT_DIR=""

print ""
print "==> SUCCESS: Carfo DMG created successfully!"
print "    Path:   $DMG_PATH"
print "    Size:   $(du -sh "$DMG_PATH" | cut -f1)"
print "    SHA256: $(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)"
