#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="${0:A:h:h}"
cd "$PROJECT_ROOT"
export CLANG_MODULE_CACHE_PATH="$PROJECT_ROOT/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_ROOT/.build/ModuleCache"
swift build -c release --cache-path "$PROJECT_ROOT/.build/Cache" --config-path "$PROJECT_ROOT/.build/Configuration" --security-path "$PROJECT_ROOT/.build/Security" --disable-sandbox
APP_PATH="$PROJECT_ROOT/build/Carfo.app"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$PROJECT_ROOT/.build/release/Carfo" "$APP_PATH/Contents/MacOS/Carfo"
cp "$PROJECT_ROOT/Support/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$PROJECT_ROOT/Support/Carfo.icns" "$APP_PATH/Contents/Resources/Carfo.icns"
cp -R "$PROJECT_ROOT/Sources/Carfo/Resources/Engine" "$APP_PATH/Contents/Resources/"
if [[ -d "$PROJECT_ROOT/.build/release/Carfo_Carfo.bundle" ]]; then
    cp -R "$PROJECT_ROOT/.build/release/Carfo_Carfo.bundle" "$APP_PATH/Contents/Resources/"
fi
codesign --force --sign - "$APP_PATH"
du -sh "$APP_PATH"
print "App: $APP_PATH"
