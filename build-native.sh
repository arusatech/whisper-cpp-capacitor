#!/bin/bash
# Build native WhisperCpp framework for iOS and optionally Android.
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
print_status() { echo -e "\033[0;34m[INFO]\033[0m $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

WHISPER_ROOT="$(cd "$(dirname "$0")" && pwd)/ref-code/whisper.cpp"
if [ ! -f "$WHISPER_ROOT/CMakeLists.txt" ]; then
  print_error "ref-code/whisper.cpp not found. Clone or copy whisper.cpp to ref-code/whisper.cpp."
  exit 1
fi

# iOS
build_ios() {
  if [[ "$OSTYPE" != "darwin"* ]]; then
    print_status "Skipping iOS build (not macOS)"
    return 0
  fi
  print_status "Building iOS WhisperCpp framework..."
  rm -rf ios/build
  mkdir -p ios/build
  cd ios/build
  cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_SYSROOT=iphoneos \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
    -DCMAKE_XCODE_ATTRIBUTE_ENABLE_BITCODE=NO
  cmake --build . --config Release -- -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
  if [ -d "WhisperCpp.framework" ]; then
    rm -rf ../Frameworks/WhisperCpp.framework
    mkdir -p ../Frameworks
    cp -R WhisperCpp.framework ../Frameworks/
    print_success "iOS framework at ios/Frameworks/WhisperCpp.framework"
  else
    BIN="WhisperCpp.framework/Versions/A/WhisperCpp"
    if [ -f "$BIN" ]; then
      rm -rf ../Frameworks/WhisperCpp.framework
      mkdir -p ../Frameworks/WhisperCpp.framework
      cp "$BIN" ../Frameworks/WhisperCpp.framework/WhisperCpp
      [ -f WhisperCpp.framework/Info.plist ] && cp WhisperCpp.framework/Info.plist ../Frameworks/WhisperCpp.framework/
      print_success "iOS framework at ios/Frameworks/WhisperCpp.framework"
    else
      print_error "WhisperCpp.framework not found after build"
      cd ../..
      exit 1
    fi
  fi
  cd ../..
}

build_ios
print_success "Native build complete."
