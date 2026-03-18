# Implementation Plan: whisper-cpp-capacitor

## Overview

This plan implements a native Capacitor plugin that embeds whisper.cpp for offline speech-to-text transcription across iOS, Android, and PWA platforms. Tasks already completed are marked accordingly based on existing code.

## Tasks

- [x] 1. Set up project structure and core TypeScript interfaces
  - [x] 1.1 Define TypeScript interfaces in src/definitions.ts
  - [x] 1.2 Set up package.json with Capacitor dependencies
  - [x] 1.3 Configure TypeScript (tsconfig.json) and build tools (rollup.config.mjs)
  - [x] 1.4 Create .gitignore and .npmignore files
  - [x] 1.5 Create typed error classes in src/errors.ts

- [x] 2. Implement TypeScript API layer
  - [x] 2.1 Create main plugin class in src/index.ts with context registry, validation, event system
  - [x] 2.2 Create web stub implementation in src/web.ts

- [x] 3. Integrate whisper.cpp C++ core
  - [x] 3.1 Create C++ wrapper layer (cpp/cap-whisper.cpp and cpp/cap-whisper.h)
  - [x] 3.2 Configure CMakeLists.txt for iOS and Android builds

- [x] 4. Implement iOS Swift bridge
  - [x] 4.1 Create WhisperCppPlugin.swift with all @objc plugin methods
  - [x] 4.2 Create WhisperCpp.swift with context management, transcription, audio loading
  - [x] 4.3 Create WhisperCppBridge.mm Objective-C++ bridge to C++ wrapper
  - [x] 4.4 Configure ios/CMakeLists.txt for Metal-enabled whisper.cpp build
  - [x] 4.5 Create build-native.sh for iOS framework builds

- [x] 5. Implement Android JNI bridge
  - [x] 5.1 Create WhisperCppPlugin.java with all @PluginMethod annotations
  - [x] 5.2 Create WhisperCpp.java with NativeBridge JNI wrapper and async execution
  - [x] 5.3 Create whisper-jni.cpp with JNI native methods for init, transcribe, release
  - [x] 5.4 Configure android CMakeLists.txt and build.gradle for NDK builds

- [x] 6. Improve Android implementation - parse params JSON and pass to whisper
  - [x] 6.1 Parse params JSON in whisper-jni.cpp initContext to honor use_gpu, n_threads, language, translate, etc.
  - [x] 6.2 Parse params JSON in whisper-jni.cpp transcribe to configure cap_whisper_full_params from caller settings
  - [x] 6.3 Add proper audio format decoding on Android (currently reads raw float32 only; add WAV header parsing at minimum)
  - [x] 6.4 Implement getSystemInfo with real device values (Runtime.maxMemory, Runtime.availableProcessors, GPU detection)

- [x] 7. Improve iOS implementation - streaming and progress callbacks
  - [x] 7.1 Implement transcribeRealtime in WhisperCpp.swift using AVAudioEngine for mic capture and chunked whisper_full calls
  - [x] 7.2 Implement stopTranscription to cancel active streaming session
  - [x] 7.3 Wire progress_callback in cap-whisper.cpp to emit progress events back through the bridge
  - [x] 7.4 Implement getModelInfo in WhisperCpp.swift to query a specific context's model info
  - [x] 7.5 Implement getAudioFormat using AVFoundation to inspect audio file metadata
  - [x] 7.6 Improve getSystemInfo to report actual memory_available_mb using os_proc_available_memory

- [x] 8. Implement Android streaming and progress callbacks
  - [x] 8.1 Implement transcribeRealtime in WhisperCppPlugin.java using AudioRecord for mic capture
  - [x] 8.2 Implement stopTranscription to cancel active streaming
  - [x] 8.3 Add JNI progress callback support to emit events during transcription
  - [x] 8.4 Implement getAudioFormat using MediaExtractor
  - [x] 8.5 Add proper audio decoding for WAV, MP3, OGG, M4A using MediaCodec/MediaExtractor

- [ ] 9. Write TypeScript unit tests
  - [ ] 9.1 Test parameter validation for initContext, transcribe, releaseContext
  - [ ] 9.2 Test event subscription (on/off) and emission
  - [ ] 9.3 Test context registry management (add, remove, clear)
  - [ ] 9.4 Test error classes (ModelLoadError, ContextNotFoundError, etc.)

- [ ] 10. Write property-based tests (fast-check)
  - [ ] 10.1 Property: context uniqueness - multiple initContext calls produce distinct contextIds
  - [ ] 10.2 Property: segment timestamps monotonically non-decreasing
  - [ ] 10.3 Property: segment text concatenation equals full text
  - [ ] 10.4 Property: language_prob always in [0.0, 1.0]

- [ ] 11. Documentation and README
  - [ ] 11.1 Write comprehensive README.md with installation, setup, API reference, and examples
  - [ ] 11.2 Add model download instructions and platform setup guides
  - [ ] 11.3 Document build process for iOS and Android native libraries

## Notes

- Tasks 1-5 are already implemented in the existing codebase
- Tasks 6-8 focus on completing and hardening the native implementations
- Tasks 9-10 add test coverage
- Task 11 provides user-facing documentation
- whisper.cpp is referenced from ref-code/whisper.cpp via CMake add_subdirectory
- Android currently uses Java (not Kotlin) for the plugin layer
- iOS uses dynamic framework loading via dlopen for the native library
