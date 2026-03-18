# Implementation Plan: whisper-cpp-capacitor

## Overview

This plan implements a native Capacitor plugin that embeds whisper.cpp for offline speech-to-text transcription across iOS, Android, and PWA platforms. The implementation follows the proven architecture of llama-cpp-capacitor, adapting it for whisper.cpp's audio processing capabilities. The plugin provides a unified TypeScript API with support for batch and streaming transcription, language detection, translation, speaker diarization, word-level timestamps, and GPU acceleration.

## Tasks

- [ ] 1. Set up project structure and core TypeScript interfaces
  - Create directory structure (src/, ios/, android/, cpp/, test/)
  - Define TypeScript interfaces in src/definitions.ts (NativeWhisperContextParams, WhisperSegment, WhisperWord, NativeTranscriptionResult, NativeWhisperContext, AudioFormat, StreamingTranscribeParams, WhisperCppPlugin)
  - Set up package.json with Capacitor dependencies
  - Configure TypeScript (tsconfig.json) and build tools (rollup.config.mjs)
  - Create .gitignore and .npmignore files
  - _Requirements: 1.1, 2.1, 3.1, 4.1, 5.1, 6.1, 7.1, 8.1, 9.1, 10.1_

- [ ] 2. Implement TypeScript API layer
  - [ ] 2.1 Create main plugin class in src/index.ts
    - Implement WhisperCpp singleton class with getInstance()
    - Implement initContext() with parameter validation
    - Implement releaseContext() and releaseAllContexts()
    - Implement transcribe() with base64 and file path support
    - Implement transcribeRealtime() and stopTranscription()
    - Implement getSystemInfo() and getModelInfo()
    - Add context registry for tracking active contexts
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 2.1, 2.2, 3.1, 10.3_

  - [ ] 2.2 Write property test for context lifecycle
    - **Property 1: Context uniqueness - Multiple initContext calls produce distinct contextIds**
    - **Validates: Requirements 1.2**

  - [ ] 2.3 Implement event handling system
    - Create EventEmitter for progress, segment, and error events
    - Implement on() and off() methods for event subscription
    - Add event validation and type safety
    - _Requirements: 9.1, 9.2, 9.3, 9.4_

  - [ ] 2.4 Write unit tests for TypeScript API
    - Test parameter validation for all methods
    - Test event subscription and emission
    - Test error handling and propagation
    - Test context registry management
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 2.1, 9.4_

- [ ] 3. Integrate whisper.cpp C++ core
  - [ ] 3.1 Add whisper.cpp as submodule or vendored dependency
    - Clone whisper.cpp repository into cpp/ directory
    - Select stable version/commit for integration
    - Document whisper.cpp version in README
    - _Requirements: All (foundational)_

  - [ ] 3.2 Create C++ wrapper layer (cpp/cap-whisper.cpp and cpp/cap-whisper.h)
    - Define C++ wrapper functions for whisper_init_from_file, whisper_free, whisper_full
    - Implement audio sample conversion utilities (PCM float32 normalization)
    - Implement segment extraction (whisper_full_n_segments, whisper_full_get_segment_text, timestamps)
    - Implement language detection wrapper (whisper_full_lang_id, whisper_lang_str)
    - Add error handling and logging
    - _Requirements: 1.1, 2.1, 2.3, 2.4, 4.1, 4.2, 7.2_

  - [ ] 3.3 Write unit tests for C++ wrapper
    - Test model loading with valid and invalid paths
    - Test audio processing with known samples
    - Test segment extraction accuracy
    - Test language detection
    - _Requirements: 1.5, 2.1, 4.1, 7.5_

- [ ] 4. Implement iOS Swift bridge
  - [ ] 4.1 Create iOS plugin structure
    - Create ios/Sources/WhisperCppPlugin/ directory
    - Create WhisperCppPlugin.swift with @objc methods
    - Create WhisperCppPlugin.m for Capacitor registration
    - Configure WhisperCpp.podspec with dependencies
    - Set up CMakeLists.txt for whisper.cpp compilation
    - _Requirements: 1.1, 1.7, 8.1_

  - [ ] 4.2 Implement context management in Swift
    - Implement initContext() bridging to C++ whisper_init_from_file
    - Implement context registry with thread-safe access
    - Implement releaseContext() and releaseAllContexts()
    - Handle model file paths (bundle assets vs. file system)
    - Detect and initialize Metal GPU acceleration
    - Populate NativeWhisperContext with model metadata
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 8.1, 8.4, 8.5, 10.1, 10.2_

  - [ ] 4.3 Write property test for iOS context management
    - **Property 2: Context isolation - Operations on one context do not affect others**
    - **Validates: Requirements 1.2, 1.6**

  - [ ] 4.4 Implement batch transcription in Swift
    - Implement transcribe() method with base64 and file path support
    - Decode audio using AVFoundation (wav, mp3, m4a, etc.)
    - Convert audio to 16 kHz mono PCM float32
    - Call whisper_full() with configured parameters
    - Extract segments with timestamps and text
    - Build and return NativeTranscriptionResult
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9, 7.1, 7.2_

  - [ ] 4.5 Write property test for transcription consistency
    - **Property 3: Idempotency - Multiple transcriptions of same audio produce identical results**
    - **Validates: Requirements 2.1, 2.2, 2.3**

  - [ ] 4.6 Write property test for segment ordering
    - **Property 4: Monotonicity - Segment timestamps are strictly non-decreasing**
    - **Validates: Requirements 2.8, 2.9**

  - [ ] 4.7 Implement streaming transcription in Swift
    - Implement transcribeRealtime() with audio chunking
    - Create background queue for audio processing
    - Emit segment events via Capacitor event system
    - Implement stopTranscription() to cancel streaming
    - Handle chunk overlap and continuity
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_

  - [ ] 4.8 Write unit tests for iOS streaming
    - Test chunk processing and event emission
    - Test stopTranscription() cancellation
    - Test concurrent session prevention
    - _Requirements: 3.1, 3.2, 3.3, 3.5_

  - [ ] 4.9 Implement language detection and translation in Swift
    - Add language detection logic (detect_language parameter)
    - Add explicit language setting (language parameter)
    - Implement translation mode (translate parameter)
    - Populate language and language_prob in results
    - _Requirements: 4.1, 4.2, 4.3, 4.4_

  - [ ] 4.10 Implement word-level timestamps in Swift
    - Enable token_timestamps in whisper parameters
    - Extract word-level data from whisper.cpp
    - Build WhisperWord array with start, end, confidence
    - Validate word timestamps against segment boundaries
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5_

  - [ ] 4.11 Implement speaker diarization in Swift
    - Enable tdrz_enable parameter
    - Extract speaker_id from whisper.cpp segments
    - Populate speaker_id in WhisperSegment
    - _Requirements: 6.1, 6.2, 6.3_

  - [ ] 4.12 Implement progress callbacks in Swift
    - Add progress callback to model loading
    - Emit progress events during transcription
    - Emit error events on failures
    - _Requirements: 9.1, 9.3_

  - [ ] 4.13 Implement system info in Swift
    - Detect platform (iOS)
    - Check Metal GPU availability
    - Report CPU core count (max_threads)
    - Estimate available memory
    - _Requirements: 10.3_

  - [ ] 4.14 Write integration tests for iOS
    - Test full workflow: init → transcribe → release
    - Test Metal GPU acceleration
    - Test multiple audio formats
    - Test error scenarios (invalid model, bad audio)
    - _Requirements: 1.1, 1.5, 2.1, 7.1, 8.1, 11.1, 11.3_

- [ ] 5. Checkpoint - iOS implementation complete
  - Ensure all iOS tests pass, ask the user if questions arise.

- [ ] 6. Implement Android Kotlin/JNI bridge
  - [ ] 6.1 Create Android plugin structure
    - Create android/src/main/java/com/getcapacitor/plugin/whispercpp/ directory
    - Create WhisperCppPlugin.kt with @PluginMethod annotations
    - Configure android/build.gradle with NDK and CMake
    - Set up CMakeLists.txt for whisper.cpp JNI compilation
    - _Requirements: 1.1, 1.7, 8.2_

  - [ ] 6.2 Implement JNI native methods
    - Create android/src/main/cpp/whisper-jni.cpp
    - Implement JNI wrappers for whisper_init_from_file, whisper_free, whisper_full
    - Implement JNI type conversions (Java ↔ C++)
    - Handle JNI exceptions and error propagation
    - _Requirements: 1.1, 2.1, 11.2_

  - [ ] 6.3 Implement context management in Kotlin
    - Implement initContext() calling JNI native methods
    - Implement context registry with thread-safe access
    - Implement releaseContext() and releaseAllContexts()
    - Handle model file paths (assets vs. file system)
    - Detect and initialize GPU acceleration (OpenCL/Vulkan)
    - Populate NativeWhisperContext with model metadata
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 8.2, 8.4, 8.5, 10.1, 10.2_

  - [ ] 6.4 Write property test for Android context management
    - **Property 5: Context cleanup - Released contexts free all native resources**
    - **Validates: Requirements 1.3, 1.4**

  - [ ] 6.5 Implement batch transcription in Kotlin
    - Implement transcribe() method with base64 and file path support
    - Decode audio using MediaCodec/MediaExtractor (wav, mp3, m4a, ogg, etc.)
    - Convert audio to 16 kHz mono PCM float32
    - Call JNI whisper_full() with configured parameters
    - Extract segments with timestamps and text via JNI
    - Build and return NativeTranscriptionResult
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9, 7.1, 7.2_

  - [ ] 6.6 Write property test for text consistency
    - **Property 6: Text concatenation - Segment texts concatenate to full text**
    - **Validates: Requirements 2.5**

  - [ ] 6.7 Implement streaming transcription in Kotlin
    - Implement transcribeRealtime() with audio chunking
    - Create background thread for audio processing
    - Emit segment events via Capacitor event system
    - Implement stopTranscription() to cancel streaming
    - Handle chunk overlap and continuity
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_

  - [ ] 6.8 Implement language detection and translation in Kotlin
    - Add language detection logic (detect_language parameter)
    - Add explicit language setting (language parameter)
    - Implement translation mode (translate parameter)
    - Populate language and language_prob in results
    - _Requirements: 4.1, 4.2, 4.3, 4.4_

  - [ ] 6.9 Implement word-level timestamps in Kotlin
    - Enable token_timestamps in whisper parameters
    - Extract word-level data from whisper.cpp via JNI
    - Build WhisperWord array with start, end, confidence
    - Validate word timestamps against segment boundaries
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5_

  - [ ] 6.10 Implement speaker diarization in Kotlin
    - Enable tdrz_enable parameter
    - Extract speaker_id from whisper.cpp segments via JNI
    - Populate speaker_id in WhisperSegment
    - _Requirements: 6.1, 6.2, 6.3_

  - [ ] 6.11 Implement progress callbacks in Kotlin
    - Add progress callback to model loading
    - Emit progress events during transcription
    - Emit error events on failures
    - _Requirements: 9.1, 9.3_

  - [ ] 6.12 Implement system info in Kotlin
    - Detect platform (Android)
    - Check GPU availability (OpenCL/Vulkan)
    - Report CPU core count (max_threads)
    - Estimate available memory
    - _Requirements: 10.3_

  - [ ] 6.13 Write integration tests for Android
    - Test full workflow: init → transcribe → release
    - Test GPU acceleration
    - Test multiple audio formats
    - Test error scenarios (invalid model, bad audio)
    - Test Android permissions (RECORD_AUDIO)
    - _Requirements: 1.1, 1.5, 2.1, 7.1, 8.2, 11.1, 11.3, 12.3, 12.4_

- [ ] 7. Checkpoint - Android implementation complete
  - Ensure all Android tests pass, ask the user if questions arise.

- [ ] 8. Implement Web/PWA WebAssembly implementation
  - [ ] 8.1 Create Web plugin structure
    - Create src/web.ts implementing WhisperCppPlugin interface
    - Extend WebPlugin base class from @capacitor/core
    - Set up Emscripten build configuration for whisper.cpp
    - _Requirements: 1.1, 8.3_

  - [ ] 8.2 Compile whisper.cpp to WebAssembly
    - Create Emscripten build script (build-wasm.sh)
    - Configure WASM exports for whisper API functions
    - Optimize WASM binary size (enable quantization, strip debug)
    - Generate TypeScript bindings for WASM module
    - _Requirements: 1.1, 8.3_

  - [ ] 8.3 Implement context management in Web
    - Implement initContext() loading WASM module
    - Implement WASM memory management (malloc/free)
    - Implement context registry
    - Implement releaseContext() and releaseAllContexts()
    - Handle model file loading (fetch from URL or IndexedDB)
    - Detect WebGPU availability
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.7, 1.8, 8.3, 8.4, 8.5_

  - [ ] 8.4 Implement batch transcription in Web
    - Implement transcribe() method with base64 and file support
    - Decode audio using Web Audio API
    - Convert audio to 16 kHz mono PCM float32
    - Copy audio samples to WASM memory
    - Call WASM whisper_full() function
    - Extract segments from WASM memory
    - Build and return NativeTranscriptionResult
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9, 7.1, 7.2_

  - [ ] 8.5 Write property test for WASM memory safety
    - **Property 7: Memory cleanup - WASM memory is freed after transcription**
    - **Validates: Requirements 1.3, 12.2**

  - [ ] 8.6 Implement streaming transcription in Web
    - Implement transcribeRealtime() with Web Workers
    - Create Worker for background audio processing
    - Emit segment events via postMessage
    - Implement stopTranscription() to terminate Worker
    - Handle chunk overlap and continuity
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_

  - [ ] 8.7 Implement language detection and translation in Web
    - Add language detection logic (detect_language parameter)
    - Add explicit language setting (language parameter)
    - Implement translation mode (translate parameter)
    - Populate language and language_prob in results
    - _Requirements: 4.1, 4.2, 4.3, 4.4_

  - [ ] 8.8 Implement word-level timestamps in Web
    - Enable token_timestamps in whisper parameters
    - Extract word-level data from WASM memory
    - Build WhisperWord array with start, end, confidence
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5_

  - [ ] 8.9 Implement speaker diarization in Web
    - Enable tdrz_enable parameter
    - Extract speaker_id from WASM memory
    - Populate speaker_id in WhisperSegment
    - _Requirements: 6.1, 6.2, 6.3_

  - [ ] 8.10 Implement progress callbacks in Web
    - Add progress callback to model loading
    - Emit progress events during transcription
    - Emit error events on failures
    - _Requirements: 9.1, 9.3_

  - [ ] 8.11 Implement system info in Web
    - Detect platform (browser user agent)
    - Check WebGPU availability
    - Report navigator.hardwareConcurrency (max_threads)
    - Estimate available memory (navigator.deviceMemory)
    - _Requirements: 10.3_

  - [ ] 8.12 Write integration tests for Web
    - Test full workflow: init → transcribe → release
    - Test WebGPU acceleration
    - Test multiple audio formats
    - Test error scenarios (invalid model, bad audio)
    - Test in Chrome, Firefox, Safari
    - _Requirements: 1.1, 1.5, 2.1, 7.1, 8.3, 11.1, 11.3_

- [ ] 9. Checkpoint - Web implementation complete
  - Ensure all Web tests pass, ask the user if questions arise.

- [ ] 10. Implement audio format support and conversion
  - [ ] 10.1 Implement audio decoder utilities
    - Create audio-utils.ts with format detection
    - Implement WAV decoder (PCM, ADPCM)
    - Implement MP3 decoder (platform-specific or Web Audio API)
    - Implement OGG/Vorbis decoder
    - Implement FLAC decoder
    - Implement M4A/AAC decoder
    - Implement WebM/Opus decoder
    - _Requirements: 7.1, 7.2_

  - [ ] 10.2 Write property test for audio normalization
    - **Property 8: Format equivalence - Same speech in different formats produces equivalent transcriptions**
    - **Validates: Requirements 7.3**

  - [ ] 10.3 Implement audio resampling and channel conversion
    - Implement resampling to 16 kHz (linear interpolation or FFT-based)
    - Implement stereo to mono conversion (average channels)
    - Implement bit depth conversion to float32
    - _Requirements: 7.2, 7.3_

  - [ ] 10.4 Write unit tests for audio processing
    - Test format detection for all supported formats
    - Test resampling accuracy
    - Test channel conversion
    - Test error handling for unsupported formats
    - _Requirements: 7.1, 7.2, 7.4, 7.5_

- [ ] 11. Implement error handling and validation
  - [ ] 11.1 Create typed error classes
    - Create ModelLoadError class
    - Create AudioProcessingError class
    - Create ContextNotFoundError class
    - Create OutOfMemoryError class
    - Create TranscriptionTimeoutError class
    - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.5_

  - [ ] 11.2 Add parameter validation
    - Validate contextId is positive integer
    - Validate model paths are non-empty strings
    - Validate audio_data is valid base64 or file path
    - Validate numeric parameters are in valid ranges
    - Validate language codes are valid ISO 639-1
    - _Requirements: 1.5, 2.1, 4.2, 11.1, 11.2, 11.3_

  - [ ] 11.3 Implement error recovery mechanisms
    - Implement GPU fallback to CPU on initialization failure
    - Implement partial result return on timeout
    - Implement context cleanup on errors
    - Implement audio buffer clearing on completion
    - _Requirements: 1.8, 8.5, 8.6, 11.4, 11.6, 12.2_

  - [ ] 11.4 Write unit tests for error handling
    - Test all error classes are thrown correctly
    - Test parameter validation rejects invalid inputs
    - Test GPU fallback behavior
    - Test partial results on timeout
    - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.5, 11.6_

- [ ] 12. Implement privacy and security features
  - [ ] 12.1 Implement on-device processing guarantees
    - Verify no network calls in transcription path
    - Add documentation about offline operation
    - _Requirements: 12.1_

  - [ ] 12.2 Implement audio buffer cleanup
    - Clear audio buffers after transcription
    - Clear intermediate processing buffers
    - Implement secure memory wiping for sensitive audio
    - _Requirements: 12.2_

  - [ ] 12.3 Implement permission handling
    - Request iOS microphone permission when needed
    - Request Android RECORD_AUDIO permission when needed
    - Handle permission denial gracefully
    - _Requirements: 12.3, 12.4_

  - [ ] 12.4 Write unit tests for privacy features
    - Test audio buffer cleanup
    - Test permission request flows
    - Test error handling for denied permissions
    - _Requirements: 12.2, 12.3, 12.4_

- [ ] 13. Create build scripts and configuration
  - [ ] 13.1 Create iOS build scripts
    - Create build-ios-arm64.sh for device builds
    - Create build-ios-x86_64.sh for simulator builds
    - Configure CMakeLists.txt for Metal support
    - Update WhisperCpp.podspec with build settings
    - _Requirements: 1.1, 8.1_

  - [ ] 13.2 Create Android build scripts
    - Create build-android.sh for all architectures (arm64-v8a, armeabi-v7a, x86_64, x86)
    - Configure CMakeLists.txt for NDK
    - Update android/build.gradle with NDK settings
    - _Requirements: 1.1, 8.2_

  - [ ] 13.3 Create Web build scripts
    - Create build-wasm.sh using Emscripten
    - Configure WASM optimization flags
    - Create post-build script to copy WASM files
    - _Requirements: 1.1, 8.3_

  - [ ] 13.4 Create unified build script
    - Create build-all.sh to build all platforms
    - Add platform detection and conditional builds
    - Add build verification and testing
    - _Requirements: 1.1_

- [ ] 14. Create documentation and examples
  - [ ] 14.1 Write API documentation
    - Document all TypeScript interfaces and types
    - Document all plugin methods with examples
    - Document error types and handling
    - Document platform-specific considerations
    - _Requirements: All_

  - [ ] 14.2 Create usage examples
    - Create example for basic batch transcription
    - Create example for streaming transcription
    - Create example for language detection
    - Create example for word-level timestamps
    - Create example for speaker diarization
    - _Requirements: 2.1, 3.1, 4.1, 5.1, 6.1_

  - [ ] 14.3 Write README.md
    - Add installation instructions
    - Add quick start guide
    - Add platform setup instructions (iOS, Android, Web)
    - Add model download instructions
    - Add troubleshooting section
    - _Requirements: All_

  - [ ] 14.4 Create CONTRIBUTING.md
    - Add development setup instructions
    - Add build instructions
    - Add testing instructions
    - Add code style guidelines
    - _Requirements: All_

- [ ] 15. Create package configuration and publish setup
  - [ ] 15.1 Configure package.json
    - Set package name, version, description
    - Add Capacitor peer dependencies
    - Add build scripts (build, test, lint)
    - Configure exports and types
    - _Requirements: All_

  - [ ] 15.2 Configure TypeScript and bundler
    - Configure tsconfig.json for strict mode
    - Configure rollup.config.mjs for bundling
    - Add source maps for debugging
    - _Requirements: All_

  - [ ] 15.3 Create npm publish workflow
    - Create .npmignore to exclude unnecessary files
    - Add pre-publish build verification
    - Document npm publish process
    - _Requirements: All_

- [ ] 16. Final integration testing and validation
  - [ ] 16.1 Run cross-platform integration tests
    - Test on iOS physical device and simulator
    - Test on Android physical device and emulator
    - Test on Chrome, Firefox, Safari browsers
    - Test with tiny, base, and small models
    - Test with various audio formats and lengths
    - _Requirements: All_

  - [ ] 16.2 Run performance benchmarks
    - Measure transcription speed on each platform
    - Measure memory usage with different models
    - Compare CPU vs GPU performance
    - Document performance characteristics
    - _Requirements: 8.1, 8.2, 8.3_

  - [ ] 16.3 Run security and privacy validation
    - Verify no network calls during transcription
    - Verify audio buffer cleanup
    - Verify permission handling
    - Run static analysis for security issues
    - _Requirements: 12.1, 12.2, 12.3, 12.4_

- [ ] 17. Final checkpoint - Complete implementation
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- The implementation follows the proven llama-cpp-capacitor architecture
- whisper.cpp integration requires careful memory management across language boundaries
- Audio processing is platform-specific but must produce consistent 16 kHz mono PCM float32 output
- GPU acceleration is optional and should gracefully fall back to CPU
- All audio processing must occur on-device for privacy
- Property tests validate universal correctness properties across platforms
- Unit tests validate specific examples and edge cases
- Integration tests verify end-to-end workflows on real devices
