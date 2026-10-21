#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="${0:A:h:h}"
cd "$PROJECT_ROOT"
export CLANG_MODULE_CACHE_PATH="$PROJECT_ROOT/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_ROOT/.build/ModuleCache"

print "==> 1. Compiling Carfo (release mode)..."
swift build -c release --cache-path "$PROJECT_ROOT/.build/Cache" --config-path "$PROJECT_ROOT/.build/Configuration" --security-path "$PROJECT_ROOT/.build/Security" --disable-sandbox

APP_PATH="$PROJECT_ROOT/build/Carfo.app"
print "==> 2. Packaging application bundle: $APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$PROJECT_ROOT/.build/release/Carfo" "$APP_PATH/Contents/MacOS/Carfo"
cp "$PROJECT_ROOT/Support/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$PROJECT_ROOT/Support/Carfo.icns" "$APP_PATH/Contents/Resources/Carfo.icns"
cp -R "$PROJECT_ROOT/Sources/Carfo/Resources/Engine" "$APP_PATH/Contents/Resources/"
cp "$PROJECT_ROOT/Sources/Carfo/Resources/CarfoIcon.png" "$APP_PATH/Contents/Resources/" 2>/dev/null || true
cp "$PROJECT_ROOT/Sources/Carfo/Resources/CarfoMenuBarIcon.png" "$APP_PATH/Contents/Resources/" 2>/dev/null || true
if [[ -d "$PROJECT_ROOT/.build/release/Carfo_Carfo.bundle" ]]; then
    cp -R "$PROJECT_ROOT/.build/release/Carfo_Carfo.bundle" "$APP_PATH/Contents/Resources/"
fi

# Bundle AI Models (EmbeddingGemma 2 & Whisper)
MODEL_SRC="/Users/apple/.cache/huggingface/hub/models--mlx-community--embeddinggemma-2-bf16/snapshots/1a4ffddb7905d3f63486748deabe091a01fb6201"
WHISPER_SRC="/Users/apple/.cache/huggingface/hub/models--mlx-community--whisper-small-mlx/snapshots/45f3915923c7a79a5a5b5a7d909d39aeb0e5630e"

if [[ -d "$MODEL_SRC" ]]; then
    print "==> 3. Bundling EmbeddingGemma 2 Model into app..."
    mkdir -p "$APP_PATH/Contents/Resources/Model"
    cp -RL "$MODEL_SRC"/* "$APP_PATH/Contents/Resources/Model/"
fi

if [[ -d "$WHISPER_SRC" ]]; then
    print "==> 4. Bundling Whisper MLX Model into app..."
    mkdir -p "$APP_PATH/Contents/Resources/Whisper"
    cp -RL "$WHISPER_SRC"/* "$APP_PATH/Contents/Resources/Whisper/"
fi

# Bundle Standalone Relocatable Python & MLX Runtime
if [[ -d "$PROJECT_ROOT/scratch/test-python" ]]; then
    print "==> 5. Bundling Standalone Python & MLX Runtime..."
    mkdir -p "$APP_PATH/Contents/Resources/Python"
    cp -RL "$PROJECT_ROOT/scratch/test-python"/* "$APP_PATH/Contents/Resources/Python/"
fi

print "==> 6. Code signing application bundle..."
codesign --force --deep --sign - "$APP_PATH"
du -sh "$APP_PATH"
print "==> SUCCESS: Standalone Carfo.app is ready for public distribution at: $APP_PATH"
