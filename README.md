# whisper-cpp-capacitor

Native Capacitor plugin that embeds [whisper.cpp](https://github.com/ggerganov/whisper.cpp) for fully offline, on-device speech-to-text transcription on iOS and Android.

All audio processing happens locally — no data leaves the device.

## Features

- Offline speech-to-text powered by whisper.cpp
- Unified TypeScript API across iOS and Android
- Context lifecycle management (`initContext` / `releaseContext` / `releaseAllContexts`)
- Batch transcription from base64 audio or file paths
- Real-time streaming transcription with live segment events
- Automatic language detection and translation to English
- Word-level timestamps and confidence scores
- Speaker diarization (turn detection)
- Multiple audio format support (WAV, MP3, OGG, FLAC, M4A, WebM)
- GPU acceleration: Metal on iOS, OpenCL/Vulkan on Android
- Progress callbacks during model loading and transcription
- Typed error classes for structured error handling

## Requirements

| Dependency | Version |
|---|---|
| Node.js | 18+ |
| Capacitor | 8+ |
| TypeScript | 5+ |
| CMake | 3.20+ |
| iOS: Xcode | 14+ (Swift 5.7+, iOS 13+) |
| Android: NDK | r25+ (API 24+, Gradle 8+) |

## Installation

```bash
npm install whisper-cpp-capacitor
npx cap sync
```

### whisper.cpp Source

The plugin builds whisper.cpp from source. Clone or copy it into the plugin directory:

```bash
git clone https://github.com/ggerganov/whisper.cpp.git ref-code/whisper.cpp
```

The path `ref-code/whisper.cpp` must contain a valid `CMakeLists.txt`. Both iOS and Android CMake configs reference this location.

## Model Files

Download GGML-format Whisper models from the [whisper.cpp model repository](https://huggingface.co/ggerganov/whisper.cpp/tree/main):

| Model | Size | Notes |
|---|---|---|
| `ggml-tiny.bin` | ~75 MB | Fastest, lowest accuracy |
| `ggml-tiny.en.bin` | ~75 MB | English-only tiny |
| `ggml-base.bin` | ~142 MB | Good balance for mobile |
| `ggml-base.en.bin` | ~142 MB | English-only base |
| `ggml-small.bin` | ~466 MB | Higher accuracy |
| `ggml-medium.bin` | ~1.5 GB | High accuracy, needs more RAM |
| `ggml-large.bin` | ~3 GB | Best accuracy, desktop/high-end devices |

Quantized variants (Q4, Q5) are also supported and recommended for mobile to reduce memory usage.

### Placing Models

**iOS**: Add the model file to your Xcode project's assets or copy it to the app's Documents directory at runtime. Use `is_model_asset: true` if bundled as an asset.

**Android**: Place models in the app's `assets/` folder or download to internal storage. Use `is_model_asset: true` for bundled assets.

```bash
# Example: download base English model
curl -L -o models/ggml-base.en.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin
```

## Quick Start

```typescript
import { WhisperCpp } from 'whisper-cpp-capacitor';

// Load a model
const ctx = await WhisperCpp.initContext({
  model: '/path/to/ggml-base.en.bin',
  use_gpu: true,
  n_threads: 4,
});

// Transcribe audio from a file
const result = await WhisperCpp.transcribe({
  contextId: ctx.contextId,
  audio_data: '/path/to/audio.wav',
  is_audio_file: true,
  params: { n_threads: 4 },
});

console.log(result.text);
console.log(result.segments); // time-stamped segments
console.log(result.language); // detected language code

// Clean up
await WhisperCpp.releaseContext({ contextId: ctx.contextId });
```

## API Reference

### `initContext(params: NativeWhisperContextParams): Promise<NativeWhisperContext>`

Loads a whisper.cpp model and returns a context handle.

```typescript
const ctx = await WhisperCpp.initContext({
  model: '/path/to/ggml-base.en.bin',
  use_gpu: true,
  n_threads: 4,
  language: 'en',           // or omit for auto-detection
  detect_language: true,
  translate: false,          // set true to translate to English
  token_timestamps: true,    // enable word-level timestamps
  tdrz_enable: false,        // enable speaker diarization
  beam_size: 5,
  best_of: 5,
  temperature: 0.0,
  use_progress_callback: true,
});
// ctx.contextId: unique integer ID
// ctx.gpu: whether GPU acceleration is active
// ctx.reasonNoGPU: explanation if GPU unavailable
// ctx.model: model metadata (type, vocab_size, etc.)
```

### `releaseContext(options: { contextId: number }): Promise<void>`

Frees all resources for a specific context.

```typescript
await WhisperCpp.releaseContext({ contextId: ctx.contextId });
```

### `releaseAllContexts(): Promise<void>`

Releases every active context.

```typescript
await WhisperCpp.releaseAllContexts();
```

### `transcribe(params: NativeTranscribeParams): Promise<NativeTranscriptionResult>`

Transcribes audio in a single batch call. Accepts base64-encoded audio or a file path.

```typescript
// From file
const result = await WhisperCpp.transcribe({
  contextId: ctx.contextId,
  audio_data: '/path/to/recording.wav',
  is_audio_file: true,
  params: { n_threads: 4, language: 'en' },
});

// From base64 (16kHz mono PCM float32)
const result = await WhisperCpp.transcribe({
  contextId: ctx.contextId,
  audio_data: base64AudioString,
  is_audio_file: false,
  params: { n_threads: 4 },
});
```

**Result shape:**

```typescript
{
  text: string;              // full transcription
  segments: WhisperSegment[];// time-stamped segments
  words?: WhisperWord[];     // word-level timestamps (if token_timestamps enabled)
  language: string;          // ISO 639-1 code
  language_prob: number;     // confidence [0.0, 1.0]
  duration_ms: number;       // audio duration
  processing_time_ms: number;// inference time
}
```

### `transcribeRealtime(params: StreamingTranscribeParams): Promise<void>`

Starts real-time streaming transcription from the device microphone. Emits `segment` events as chunks are processed.

```typescript
import { WhisperCppAPI } from 'whisper-cpp-capacitor';

WhisperCppAPI.on('segment', (segment) => {
  console.log('Live:', segment.text);
});

await WhisperCpp.transcribeRealtime({
  chunk_length_ms: 3000,
  step_length_ms: 500,
  params: { model: '/path/to/model.bin', n_threads: 4 },
});
```

### `stopTranscription(): Promise<void>`

Stops an active streaming session.

```typescript
await WhisperCpp.stopTranscription();
```

### `getSystemInfo(): Promise<SystemInfo>`

Returns platform capabilities.

```typescript
const info = await WhisperCpp.getSystemInfo();
// { platform: 'ios', gpu_available: true, max_threads: 6, memory_available_mb: 2048 }
```

### `getModelInfo(): Promise<ModelInfo>`

Returns metadata about the currently loaded model.

```typescript
const model = await WhisperCpp.getModelInfo();
// { type: 'base', is_multilingual: false, vocab_size: 51864, ... }
```

### `getAudioFormat(options: { path: string }): Promise<AudioFormat>`

Inspects an audio file and returns its format metadata.

```typescript
const fmt = await WhisperCpp.getAudioFormat({ path: '/path/to/audio.wav' });
// { sample_rate: 44100, channels: 2, bits_per_sample: 16, format: 'wav' }
```

### `convertAudio(options): Promise<void>`

Converts audio between formats.

```typescript
await WhisperCpp.convertAudio({
  input: '/path/to/input.mp3',
  output: '/path/to/output.wav',
  target_format: { sample_rate: 16000, channels: 1, bits_per_sample: 16, format: 'wav' },
});
```

### `loadModel(options: { path: string; is_asset?: boolean }): Promise<void>`

Pre-loads a model file.

### `unloadModel(): Promise<void>`

Unloads the current model.

## Events

Subscribe to events using `WhisperCppAPI.on()` and `WhisperCppAPI.off()`:

```typescript
import { WhisperCppAPI } from 'whisper-cpp-capacitor';

// Progress during model loading
WhisperCppAPI.on('progress', (progress) => {
  console.log(`Loading: ${progress}%`);
});

// Live segments during streaming
WhisperCppAPI.on('segment', (segment) => {
  console.log(`[${segment.start}-${segment.end}] ${segment.text}`);
});

// Errors
WhisperCppAPI.on('error', (error) => {
  console.error('Whisper error:', error);
});
```

## Error Handling

The plugin provides typed error classes for structured error handling:

```typescript
import {
  ModelLoadError,
  AudioProcessingError,
  ContextNotFoundError,
  OutOfMemoryError,
  TranscriptionTimeoutError,
} from 'whisper-cpp-capacitor';

try {
  await WhisperCpp.initContext({ model: '/bad/path.bin' });
} catch (e) {
  if (e instanceof ModelLoadError) {
    console.error('Model failed to load:', e.message);
  }
}

try {
  await WhisperCpp.transcribe({ ... });
} catch (e) {
  if (e instanceof TranscriptionTimeoutError) {
    console.log('Partial results:', e.partialSegments);
  }
  if (e instanceof ContextNotFoundError) {
    console.error('Invalid context:', e.contextId);
  }
}
```

## Context Parameters Reference

| Parameter | Type | Default | Description |
|---|---|---|---|
| `model` | `string` | required | Path to GGML model file |
| `is_model_asset` | `boolean` | `false` | Model is bundled as app asset |
| `use_gpu` | `boolean` | `true` | Enable GPU acceleration |
| `n_threads` | `number` | auto | Number of CPU threads |
| `language` | `string` | auto | ISO 639-1 language code |
| `detect_language` | `boolean` | `false` | Auto-detect spoken language |
| `translate` | `boolean` | `false` | Translate output to English |
| `token_timestamps` | `boolean` | `false` | Enable word-level timestamps |
| `tdrz_enable` | `boolean` | `false` | Enable speaker diarization |
| `beam_size` | `number` | `5` | Beam search width |
| `best_of` | `number` | `5` | Best-of-N sampling |
| `temperature` | `number` | `0.0` | Sampling temperature |
| `temperature_inc` | `number` | `0.2` | Temperature increment on fallback |
| `initial_prompt` | `string` | none | Prompt to guide transcription style |
| `no_timestamps` | `boolean` | `false` | Disable timestamp generation |
| `single_segment` | `boolean` | `false` | Force single-segment output |
| `max_len` | `number` | `0` | Max segment length in characters |
| `max_tokens` | `number` | `0` | Max tokens per segment |
| `offset_ms` | `number` | `0` | Audio start offset |
| `duration_ms` | `number` | `0` | Audio duration to process (0 = all) |
| `entropy_thold` | `number` | `2.4` | Entropy threshold for fallback |
| `logprob_thold` | `number` | `-1.0` | Log probability threshold |
| `no_speech_thold` | `number` | `0.6` | No-speech probability threshold |
| `use_progress_callback` | `boolean` | `false` | Emit progress events |

## Building Native Libraries

### iOS

The iOS build produces a dynamic framework wrapping whisper.cpp with Metal GPU support.

**Prerequisites**: macOS, Xcode 14+, CMake 3.20+

```bash
# Ensure whisper.cpp source is available
ls ref-code/whisper.cpp/CMakeLists.txt

# Build the iOS framework
./build-native.sh
```

This runs CMake targeting `iphoneos` with `arm64` architecture and produces `ios/Frameworks/WhisperCpp.framework`.

The build:
1. Compiles whisper.cpp as a static library with Metal enabled (`GGML_METAL=ON`)
2. Builds `cap-whisper.cpp` (the C wrapper) into a shared framework
3. Links against the whisper static library
4. Copies the framework to `ios/Frameworks/`

The Swift bridge (`ios/Sources/WhisperCppPlugin/`) loads this framework via `dlopen` at runtime.

**Xcode integration**: The framework at `ios/Frameworks/WhisperCpp.framework` must be embedded in your app target. When using CocoaPods or Swift Package Manager, this is handled automatically.

### Android

Android builds whisper.cpp automatically via the NDK when your Capacitor app compiles.

**Prerequisites**: Android NDK r25+, CMake 3.22+

The build is configured in `android/src/main/cpp/CMakeLists.txt` and triggered by `android/build.gradle`:

1. Compiles whisper.cpp as a static library
2. Builds `cap-whisper.cpp` and `whisper-jni.cpp` into `libwhisper-jni.so`
3. Targets `arm64-v8a` by default

To add more ABIs, edit `build.gradle`:

```groovy
externalNativeBuild {
    cmake {
        cppFlags "-std=c++17"
        abiFilters "arm64-v8a", "armeabi-v7a", "x86_64"
    }
}
```

No manual build step is needed — `npx cap sync android` and building through Android Studio (or Gradle) handles everything.

### Build Scripts

```bash
# Build TypeScript + native
npm run build:all

# TypeScript only
npm run build

# Native only (iOS framework)
npm run build:native

# Clean build artifacts
npm run clean          # TypeScript dist/
npm run clean:native   # iOS/Android build dirs
```

## Project Structure

```
whisper-cpp-capacitor/
├── src/                    # TypeScript API layer
│   ├── definitions.ts      # All type definitions and plugin interface
│   ├── index.ts            # Main entry: context registry, validation, events
│   ├── errors.ts           # Typed error classes
│   └── web.ts              # Web stub (not yet implemented)
├── cpp/                    # C++ wrapper around whisper.cpp
│   ├── cap-whisper.cpp     # Implementation
│   └── cap-whisper.h       # Public C API
├── ios/
│   ├── CMakeLists.txt      # iOS framework build config
│   └── Sources/WhisperCppPlugin/
│       ├── WhisperCppPlugin.swift   # Capacitor plugin methods
│       ├── WhisperCpp.swift         # Context management, transcription
│       └── WhisperCppBridge.mm      # Obj-C++ bridge to C wrapper
├── android/
│   ├── build.gradle        # Android library config
│   └── src/main/
│       ├── cpp/
│       │   ├── CMakeLists.txt   # NDK build config
│       │   └── whisper-jni.cpp  # JNI native methods
│       └── java/com/.../
│           ├── WhisperCppPlugin.java  # Capacitor plugin methods
│           └── WhisperCpp.java        # Context management, JNI wrapper
├── ref-code/whisper.cpp    # whisper.cpp source (git clone)
├── build-native.sh         # iOS framework build script
├── Package.swift           # Swift Package Manager config
└── package.json
```

## Platform Notes

**iOS**: Uses Metal for GPU acceleration. The native library is loaded dynamically via `dlopen`. Requires iOS 13+.

**Android**: Uses Java (not Kotlin) for the plugin layer. JNI bridges to the C++ wrapper. Audio decoding supports WAV, MP3, OGG, and M4A via `MediaCodec`/`MediaExtractor`. Requires API 24+.

**Web**: Currently a stub. `initContext` and `transcribe` throw "not implemented" errors. `getSystemInfo` returns basic browser info. A future WebAssembly build is planned.

## License

MIT
