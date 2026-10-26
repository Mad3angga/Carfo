#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="${0:A:h:h}"
cd "$PROJECT_ROOT"
export CLANG_MODULE_CACHE_PATH="$PROJECT_ROOT/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_ROOT/.build/ModuleCache"
export PYTHONDONTWRITEBYTECODE=1
: "${MODEL_SRC:?Set MODEL_SRC to the embedding model snapshot}"
: "${WHISPER_SRC:?Set WHISPER_SRC to the Whisper model snapshot}"
: "${PYTHON_RUNTIME_SRC:?Set PYTHON_RUNTIME_SRC to a standalone Python runtime}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
DISTRIBUTION="${DISTRIBUTION:-0}"
if [[ "$DISTRIBUTION" == 1 ]]; then
    [[ "$SIGNING_IDENTITY" == "Developer ID Application:"* ]] || { print -u2 "Developer ID Application signing identity required"; exit 1; }
    : "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile}"
else
    print -u2 "Local test build: ad hoc signature; Developer ID and notarization are required for distribution."
fi
[[ -f "$MODEL_SRC/config.json" && -f "$WHISPER_SRC/config.json" ]] || { print -u2 "Both model configurations are required"; exit 1; }
[[ -f "$MODEL_SRC/model.safetensors" || -f "$MODEL_SRC/model.safetensors.index.json" ]] || { print -u2 "Embedding weights missing"; exit 1; }
[[ -f "$WHISPER_SRC/weights.npz" || -f "$WHISPER_SRC/weights.safetensors" ]] || { print -u2 "Whisper weights missing"; exit 1; }
[[ -x "$PYTHON_RUNTIME_SRC/bin/python3" ]] || { print -u2 "Standalone Python executable missing"; exit 1; }
"$PYTHON_RUNTIME_SRC/bin/python3" -I scripts/runtime-manifest.py verify Support/runtime-lock.json
swift build -c release --product Carfo --cache-path .build/Cache --config-path .build/Configuration --security-path .build/Security --disable-sandbox
mkdir -p build
STAGING=$(mktemp -d "$PROJECT_ROOT/build/package.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
APP_PATH="$STAGING/Carfo.app"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp .build/release/Carfo "$APP_PATH/Contents/MacOS/Carfo"
cp Support/Info.plist "$APP_PATH/Contents/Info.plist"
cp Support/Carfo.icns "$APP_PATH/Contents/Resources/Carfo.icns"
cp Support/Carfo.icns "$APP_PATH/Contents/Resources/Carfo"
cp -R Sources/Carfo/Resources/Engine "$APP_PATH/Contents/Resources/Engine"
cp Sources/Carfo/Resources/CarfoIcon.png Sources/Carfo/Resources/CarfoMenuBarIcon.png "$APP_PATH/Contents/Resources/"
cp -R .build/release/Carfo_Carfo.bundle "$APP_PATH/Contents/Resources/"
cp -RL "$MODEL_SRC" "$APP_PATH/Contents/Resources/Model"
cp -RL "$WHISPER_SRC" "$APP_PATH/Contents/Resources/Whisper"
cp -RL "$PYTHON_RUNTIME_SRC" "$APP_PATH/Contents/Resources/Python"
cp Support/runtime-lock.json "$APP_PATH/Contents/Resources/runtime-lock.json"
PYTHON="$APP_PATH/Contents/Resources/Python/bin/python3"
"$PYTHON" -I scripts/runtime-manifest.py verify "$APP_PATH/Contents/Resources/runtime-lock.json"
"$PYTHON" -I scripts/bundle-tools.py manifest "$APP_PATH"
"$PYTHON" -I scripts/bundle-tools.py sign "$APP_PATH" --identity "$SIGNING_IDENTITY"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
"$PYTHON" -I -B scripts/smoke-bundle.py "$APP_PATH" --output "$STAGING/offline-smoke.json"
"$PYTHON" -I -B scripts/smoke-startup.py "$APP_PATH" --output "$STAGING/startup-smoke.json"
if [[ "$DISTRIBUTION" == 1 ]]; then
    ditto -c -k --keepParent "$APP_PATH" "$STAGING/Carfo.zip"
    xcrun notarytool submit "$STAGING/Carfo.zip" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP_PATH"
    xcrun stapler validate "$APP_PATH"
    spctl --assess --type execute --verbose=2 "$APP_PATH"
fi
if [[ -d build/Carfo.app ]]; then
    mv build/Carfo.app "build/Carfo.previous.$(date +%Y%m%d%H%M%S).app"
fi
mv "$APP_PATH" build/Carfo.app
cp "$STAGING/offline-smoke.json" build/offline-smoke.json
cp "$STAGING/startup-smoke.json" build/startup-smoke.json
print "Bundle verified: $PROJECT_ROOT/build/Carfo.app (distribution=$DISTRIBUTION)"
