#!/bin/bash
# Build whisper.cpp + cap-whisper as WebAssembly using Emscripten.
# Produces dist/wasm/whisper.js (single-file with embedded WASM).
#
# Prerequisites: Emscripten SDK (emsdk) activated in PATH.
#   https://emscripten.org/docs/getting_started/downloads.html
#
# Usage:
#   ./build-native-web.sh            # default: single-file, Release
#   ./build-native-web.sh --debug    # Debug build
#   ./build-native-web.sh --split    # separate .wasm file (smaller JS)

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
print_status() { echo -e "\033[0;34m[INFO]\033[0m $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WHISPER_ROOT="$SCRIPT_DIR/cpp/whisper.cpp"
CPP_DIR="$SCRIPT_DIR/cpp"
BUILD_DIR="$SCRIPT_DIR/build-wasm"
OUT_DIR="$SCRIPT_DIR/dist/wasm"

BUILD_TYPE="Release"
SINGLE_FILE="ON"

for arg in "$@"; do
  case "$arg" in
    --debug) BUILD_TYPE="Debug" ;;
    --split) SINGLE_FILE="OFF" ;;
  esac
done

# Verify prerequisites
if ! command -v emcmake &>/dev/null; then
  print_error "emcmake not found. Install and activate the Emscripten SDK first."
  print_error "  https://emscripten.org/docs/getting_started/downloads.html"
  exit 1
fi

if [ ! -f "$WHISPER_ROOT/CMakeLists.txt" ]; then
  print_error "whisper.cpp not found at $WHISPER_ROOT"
  print_error "Run: git submodule update --init"
  exit 1
fi

print_status "Building WASM ($BUILD_TYPE, SINGLE_FILE=$SINGLE_FILE)..."

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$OUT_DIR"

# Configure with Emscripten CMake wrapper
emcmake cmake -S "$SCRIPT_DIR/wasm" -B "$BUILD_DIR" \
  -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
  -DWHISPER_ROOT="$WHISPER_ROOT" \
  -DCPP_DIR="$CPP_DIR" \
  -DWASM_SINGLE_FILE="$SINGLE_FILE"

# Build
cmake --build "$BUILD_DIR" --config "$BUILD_TYPE" -- -j"$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)"

# Copy outputs
if [ "$SINGLE_FILE" = "ON" ]; then
  cp "$BUILD_DIR/whisper-cap.js" "$OUT_DIR/whisper.js"
  print_success "WASM built (single-file): dist/wasm/whisper.js"
else
  cp "$BUILD_DIR/whisper-cap.js" "$OUT_DIR/whisper.js"
  cp "$BUILD_DIR/whisper-cap.wasm" "$OUT_DIR/whisper.wasm"
  if [ -f "$BUILD_DIR/whisper-cap.worker.js" ]; then
    cp "$BUILD_DIR/whisper-cap.worker.js" "$OUT_DIR/whisper.worker.js"
  fi
  print_success "WASM built (split): dist/wasm/whisper.js + whisper.wasm"
fi

print_success "Web native build complete."
