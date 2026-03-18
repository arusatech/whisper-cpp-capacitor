# whisper-cpp-capacitor

Native Capacitor plugin that embeds [whisper.cpp](https://github.com/ggerganov/whisper.cpp) for offline speech-to-text on iOS and Android.

## Features

- **Offline STT**: Run Whisper models entirely on-device (no network).
- **Unified API**: Same TypeScript API on iOS and Android.
- **Context lifecycle**: `initContext` / `releaseContext` / `releaseAllContexts`.
- **Batch transcription**: `transcribe(audio_data, params)` with base64 PCM or file path.
- **Streaming** (planned): `transcribeRealtime` / `stopTranscription`.
- **Language detection** and **translation** options via params.
- **Word-level timestamps** and **speaker diarization** when supported by the model.

## Requirements

- **Node** 18+, **Capacitor** 8+
- **iOS**: Xcode 14+, macOS for building the native framework
- **Android**: NDK (e.g. r25+), CMake 3.22+
- **ref-code/whisper.cpp**: Clone or copy [whisper.cpp](https://github.com/ggerganov/whisper.cpp) into `ref-code/whisper.cpp` before building native code.

## Installation

```bash
npm install whisper-cpp-capacitor
npx cap sync
```

## Native build

The plugin uses a native framework (iOS) and JNI library (Android) that wrap whisper.cpp. You must have `ref-code/whisper.cpp` available, then run:

```bash
# Build iOS framework (macOS only)
./build-native.sh
```

This produces `ios/Frameworks/WhisperCpp.framework`. Embed it in your app (e.g. Xcode: add to Frameworks, or use the CocoaPod).

For **Android**, the plugin’s `android` module builds whisper via CMake when you build your app; ensure `ref-code/whisper.cpp` is at `ref-code/whisper.cpp` relative to the plugin root.

## Quick start

```typescript
import { WhisperCpp } from 'whisper-cpp-capacitor';

// 1. Init context (load model)
const ctx = await WhisperCpp.initContext({
  model: '/path/to/ggml-base.en.bin',
  use_gpu: true,
  n_threads: 4,
  detect_language: true,
});
console.log('Context ID', ctx.contextId, 'GPU', ctx.gpu);

// 2. Transcribe (base64 PCM float32 or file path)
const result = await WhisperCpp.transcribe({
  contextId: ctx.contextId,
  audio_data: '<base64-encoded float32 PCM 16kHz mono>',
  is_audio_file: false,
  params: { n_threads: 4 },
});
console.log(result.text, result.language, result.segments);

// 3. Release
await WhisperCpp.releaseContext({ contextId: ctx.contextId });
```

## Model files

Use GGML Whisper models (e.g. from [whisper.cpp models](https://github.com/ggerganov/whisper.cpp#available-models)). Place them in your app’s assets or a path the app can read (e.g. app documents directory).

## API (summary)

- `initContext(params)` → `Promise<NativeWhisperContext>`
- `releaseContext({ contextId })` → `Promise<void>`
- `releaseAllContexts()` → `Promise<void>`
- `transcribe(params)` → `Promise<NativeTranscriptionResult>`
- `transcribeRealtime(params)` → `Promise<void>` (stub / planned)
- `stopTranscription()` → `Promise<void>`
- `getSystemInfo()` → `Promise<SystemInfo>`
- `getModelInfo()` → `Promise<ModelInfo>`

See `src/definitions.ts` for full types.

## License

MIT
