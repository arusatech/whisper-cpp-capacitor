# Contributing to whisper-cpp-capacitor

## Development setup

1. Clone the repo and initialize the whisper.cpp submodule: `git submodule update --init`
2. Install dependencies: `npm install`
3. Build TypeScript: `npm run build`
4. Build native (iOS on macOS): `./build-native.sh`
5. Build WASM (requires Emscripten SDK): `./build-native-web.sh`

## Project layout

- `src/` – TypeScript API and definitions
- `ios/Sources/WhisperCppPlugin/` – Swift plugin and ObjC++ bridge
- `android/src/main/java/.../` – Java plugin; `android/src/main/cpp/` – JNI and CMake
- `cpp/` – C wrapper around whisper C API (`cap-whisper.h`, `cap-whisper.cpp`, `cap-whisper-wasm.cpp`)
- `wasm/` – CMake config for Emscripten WASM build
- `docs/` – Design, requirements, tasks

## Build

- **JS**: `npm run build` (tsc + rollup)
- **iOS**: From plugin root, `cd ios/build && cmake .. -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_OSX_ARCHITECTURES=arm64 && cmake --build .`
- **Android**: Build the app that depends on this plugin; CMake will build the native lib.
- **WASM**: `./build-native-web.sh` (requires `emcmake` in PATH; outputs `dist/wasm/whisper.js`)

## Tests

- Unit tests: `npm test` (Jest)

## Code style

- TypeScript: strict mode, match existing style in `src/`
- Swift/Java: follow existing patterns in `ios/` and `android/`
