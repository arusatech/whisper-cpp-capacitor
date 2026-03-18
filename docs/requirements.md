# Requirements Document

## Introduction

The whisper-cpp-capacitor plugin is a native Capacitor plugin that embeds whisper.cpp for offline, on-device speech-to-text transcription. It provides a unified TypeScript API across iOS (Swift/Metal), Android (Kotlin/JNI), and PWA (WebAssembly) platforms. The plugin supports model lifecycle management, batch and streaming transcription, language detection and translation, speaker diarization, word-level timestamps, multiple audio formats, and GPU acceleration.

## Glossary

- **Plugin**: The whisper-cpp-capacitor Capacitor plugin as a whole
- **Context**: A loaded whisper.cpp model instance identified by a unique contextId
- **Context_Manager**: The subsystem responsible for creating, tracking, and releasing Contexts
- **Transcriber**: The subsystem that processes audio and produces transcription results
- **Streamer**: The subsystem that handles real-time streaming transcription
- **Audio_Processor**: The subsystem that decodes and converts audio to the format required by whisper.cpp (16 kHz mono PCM float32)
- **Language_Detector**: The subsystem that identifies the spoken language in audio
- **Diarizer**: The subsystem that assigns speaker identities to transcription segments
- **Event_Emitter**: The subsystem that dispatches progress and segment events to the application layer
- **System_Info**: The subsystem that reports platform capabilities (GPU availability, thread count, memory)
- **contextId**: A unique positive integer identifying a loaded Context
- **WhisperSegment**: A time-bounded unit of transcribed text with optional speaker and confidence metadata
- **WhisperWord**: A single word with start/end timestamps and a confidence score
- **NativeTranscriptionResult**: The complete output of a transcription operation
- **ModelLoadError**: Error thrown when a model file cannot be loaded
- **AudioProcessingError**: Error thrown when audio cannot be decoded or converted
- **ContextNotFoundError**: Error thrown when an operation targets a contextId that does not exist
- **OutOfMemoryError**: Error thrown when insufficient memory is available for model or audio processing
- **TranscriptionTimeoutError**: Error thrown when a transcription exceeds its time limit

---

## Requirements

### Requirement 1: Context Initialization and Lifecycle

**User Story:** As a developer, I want to initialize a whisper.cpp context from a model file and release it when done, so that I can manage model memory explicitly across the application lifecycle.

#### Acceptance Criteria

1. WHEN `initContext` is called with a valid model path, THE Context_Manager SHALL load the model and return a NativeWhisperContext containing a unique positive integer contextId.
2. WHEN `initContext` is called multiple times, THE Context_Manager SHALL assign a distinct contextId to each resulting Context.
3. WHEN `releaseContext` is called with a valid contextId, THE Context_Manager SHALL free all resources associated with that Context.
4. WHEN `releaseAllContexts` is called, THE Context_Manager SHALL release every active Context and free all associated resources.
5. WHEN `initContext` is called with a model path that does not exist or is unreadable, THE Context_Manager SHALL throw a ModelLoadError with a descriptive message.
6. WHEN any operation is invoked with a contextId that has been released or never existed, THE Context_Manager SHALL throw a ContextNotFoundError containing the invalid contextId.
7. THE Context_Manager SHALL report whether GPU acceleration is active in the `gpu` field of the returned NativeWhisperContext.
8. WHEN GPU initialization fails, THE Context_Manager SHALL set `gpu` to false and populate `reasonNoGPU` with an explanation, then continue loading the Context using CPU.

---

### Requirement 2: Batch Audio Transcription

**User Story:** As a developer, I want to transcribe an audio file or base64-encoded audio data in a single call, so that I can convert recorded speech to text without managing streaming state.

#### Acceptance Criteria

1. WHEN `transcribe` is called with a valid base64-encoded audio payload, THE Transcriber SHALL decode the audio and return a NativeTranscriptionResult.
2. WHEN `transcribe` is called with a valid file path (`is_audio_file: true`), THE Transcriber SHALL read the file, decode the audio, and return a NativeTranscriptionResult.
3. THE Transcriber SHALL populate the `text` field of NativeTranscriptionResult with the full transcription (which may be an empty string for silent audio).
4. THE Transcriber SHALL populate the `segments` array with one or more WhisperSegments ordered by ascending start time.
5. FOR ALL NativeTranscriptionResults, the concatenation of all WhisperSegment `text` fields SHALL equal the top-level `text` field.
6. THE Transcriber SHALL set `language` to a valid ISO 639-1 language code and `language_prob` to a value in the range [0.0, 1.0].
7. THE Transcriber SHALL set `duration_ms` and `processing_time_ms` to non-negative values.
8. FOR ALL WhisperSegments in a NativeTranscriptionResult, `end` SHALL be greater than or equal to `start`, and both SHALL be non-negative.
9. FOR ALL consecutive WhisperSegments at index i and i+1, `segments[i+1].start` SHALL be greater than or equal to `segments[i].end`.

---

### Requirement 3: Real-Time Streaming Transcription

**User Story:** As a developer, I want to receive transcription results incrementally as audio is captured, so that I can display live captions without waiting for the full audio to be processed.

#### Acceptance Criteria

1. WHEN `transcribeRealtime` is called, THE Streamer SHALL begin processing audio in chunks and emit a `segment` event via the Event_Emitter for each completed WhisperSegment.
2. WHEN `stopTranscription` is called during an active streaming session, THE Streamer SHALL cease processing and emit no further `segment` events.
3. FOR ALL `segment` events emitted during a streaming session, the WhisperSegment `start` time SHALL be greater than or equal to the `end` time of the previously emitted segment.
4. WHEN `transcribeRealtime` completes normally, THE Streamer SHALL emit a final result event containing the complete NativeTranscriptionResult.
5. WHEN `transcribeRealtime` is called while another streaming session is already active, THE Streamer SHALL throw an error indicating a session is already in progress.

---

### Requirement 4: Language Detection and Translation

**User Story:** As a developer, I want the plugin to automatically detect the spoken language and optionally translate it to English, so that I can build multilingual transcription features without managing language selection manually.

#### Acceptance Criteria

1. WHEN `detect_language` is set to true in NativeWhisperContextParams, THE Language_Detector SHALL identify the spoken language and populate the `language` field of NativeTranscriptionResult with the detected ISO 639-1 code.
2. WHEN `language` is explicitly set in NativeWhisperContextParams, THE Transcriber SHALL use that language for transcription without running language detection.
3. WHEN `translate` is set to true in NativeWhisperContextParams, THE Transcriber SHALL produce English-language output text regardless of the source language, while `language` SHALL reflect the detected or specified source language.
4. THE Language_Detector SHALL set `language_prob` to a value in the range [0.0, 1.0] representing confidence in the detected language.

---

### Requirement 5: Word-Level Timestamps and Confidence Scores

**User Story:** As a developer, I want word-level timestamps and confidence scores in the transcription output, so that I can build features like highlighted karaoke-style captions or filter low-confidence words.

#### Acceptance Criteria

1. WHEN `token_timestamps` is set to true in NativeWhisperContextParams, THE Transcriber SHALL populate the `words` array in NativeTranscriptionResult with one WhisperWord per recognized word.
2. FOR ALL WhisperWords in the `words` array, `start` SHALL be greater than or equal to the `start` of the containing WhisperSegment, and `end` SHALL be less than or equal to the `end` of the containing WhisperSegment.
3. FOR ALL WhisperWords, `confidence` SHALL be a value in the range [0.0, 1.0].
4. FOR ALL WhisperSegments that include a `confidence` field, the value SHALL be in the range [0.0, 1.0].
5. WHEN `token_timestamps` is false or not set, THE Transcriber SHALL omit the `words` array from NativeTranscriptionResult.

---

### Requirement 6: Speaker Diarization

**User Story:** As a developer, I want the plugin to identify different speakers in the audio, so that I can attribute transcribed text to individual participants in a conversation.

#### Acceptance Criteria

1. WHEN `tdrz_enable` is set to true in NativeWhisperContextParams, THE Diarizer SHALL assign a `speaker_id` to each WhisperSegment in the NativeTranscriptionResult.
2. FOR ALL WhisperSegments with a `speaker_id`, the value SHALL be a non-negative integer.
3. WHEN `tdrz_enable` is false or not set, THE Diarizer SHALL omit `speaker_id` from all WhisperSegments.

---

### Requirement 7: Audio Format Support

**User Story:** As a developer, I want to pass audio in common formats without pre-converting it, so that I can integrate the plugin into existing recording pipelines without additional processing steps.

#### Acceptance Criteria

1. THE Audio_Processor SHALL accept audio in wav, mp3, ogg, flac, m4a, and webm formats.
2. THE Audio_Processor SHALL convert all accepted audio formats to 16 kHz mono PCM float32 before passing samples to the whisper.cpp core.
3. WHEN audio at different sample rates or channel counts is provided for the same speech content, THE Audio_Processor SHALL produce equivalent transcription results after normalization.
4. WHEN audio in an unsupported format is provided, THE Audio_Processor SHALL throw an AudioProcessingError identifying the unsupported format.
5. WHEN audio data is corrupted or unreadable, THE Audio_Processor SHALL throw an AudioProcessingError with a descriptive message.

---

### Requirement 8: GPU Acceleration

**User Story:** As a developer, I want the plugin to use available GPU hardware automatically, so that transcription is as fast as possible on capable devices without manual configuration.

#### Acceptance Criteria

1. WHEN `use_gpu` is set to true and Metal is available on iOS, THE Plugin SHALL use Metal for GPU-accelerated inference.
2. WHEN `use_gpu` is set to true and OpenCL or Vulkan is available on Android, THE Plugin SHALL use the available GPU backend for accelerated inference.
3. WHEN `use_gpu` is set to true and WebGPU is available in the browser, THE Plugin SHALL use WebGPU for accelerated inference.
4. WHEN GPU acceleration is active, THE Context_Manager SHALL set `gpu` to true in the returned NativeWhisperContext.
5. WHEN GPU acceleration is requested but unavailable or fails to initialize, THE Plugin SHALL fall back to CPU inference, set `gpu` to false, and populate `reasonNoGPU` with an explanation.
6. THE Plugin SHALL complete transcription successfully regardless of whether GPU acceleration is available.

---

### Requirement 9: Event-Driven Progress Updates

**User Story:** As a developer, I want to receive progress events during model loading and transcription, so that I can display loading indicators and live feedback to users.

#### Acceptance Criteria

1. WHEN `use_progress_callback` is set to true in NativeWhisperContextParams, THE Event_Emitter SHALL emit at least one `progress` event during model loading containing a numeric progress value.
2. WHEN `transcribeRealtime` is active, THE Event_Emitter SHALL emit `segment` events as each WhisperSegment is completed.
3. WHEN an error occurs during transcription, THE Event_Emitter SHALL emit an `error` event containing a descriptive error message.
4. THE Plugin SHALL provide `addListener` and `removeAllListeners` methods for subscribing to and unsubscribing from named events.

---

### Requirement 10: Model Variants and System Information

**User Story:** As a developer, I want to query the loaded model type and system capabilities, so that I can select the appropriate model size and configure the plugin for the target device.

#### Acceptance Criteria

1. THE Context_Manager SHALL populate the `model.type` field of NativeWhisperContext with one of: `tiny`, `base`, `small`, `medium`, or `large`.
2. THE Context_Manager SHALL populate `model.is_multilingual`, `model.vocab_size`, `model.n_audio_ctx`, `model.n_audio_state`, `model.n_audio_head`, `model.n_audio_layer`, `model.n_text_ctx`, `model.n_text_state`, `model.n_text_head`, `model.n_text_layer`, `model.n_mels`, and `model.ftype` from the loaded model metadata.
3. WHEN `getSystemInfo` is called, THE System_Info subsystem SHALL return an object containing `platform` (string), `gpu_available` (boolean), `max_threads` (positive integer), and `memory_available_mb` (non-negative number).

---

### Requirement 11: Error Handling

**User Story:** As a developer, I want the plugin to throw typed, descriptive errors for all failure conditions, so that I can handle failures gracefully and provide meaningful feedback to users.

#### Acceptance Criteria

1. WHEN `initContext` is called with an invalid or missing model file, THE Context_Manager SHALL throw a ModelLoadError with a message describing the failure.
2. WHEN any plugin method is called with a contextId that does not correspond to an active Context, THE Context_Manager SHALL throw a ContextNotFoundError containing the invalid contextId.
3. WHEN audio cannot be decoded or converted, THE Audio_Processor SHALL throw an AudioProcessingError with a message identifying the cause.
4. WHEN a transcription operation exceeds its configured time limit, THE Transcriber SHALL throw a TranscriptionTimeoutError and SHALL include any partial WhisperSegments collected before the timeout.
5. IF insufficient memory is available to load a model or process audio, THEN THE Plugin SHALL throw an OutOfMemoryError with a message indicating the memory requirement.
6. WHEN GPU initialization fails, THE Plugin SHALL log a warning and continue with CPU inference rather than throwing an error.

---

### Requirement 12: Audio Privacy and On-Device Processing

**User Story:** As a developer, I want all audio processing to occur entirely on the device, so that sensitive speech data is never transmitted to external servers.

#### Acceptance Criteria

1. THE Plugin SHALL perform all audio decoding, model inference, and transcription entirely on the local device without transmitting audio data over any network.
2. WHEN a transcription operation completes, THE Audio_Processor SHALL clear all intermediate audio buffers from memory.
3. WHEN microphone access is required, THE Plugin SHALL request the appropriate platform permission (iOS microphone permission, Android RECORD_AUDIO permission) before accessing audio hardware.
4. IF a required permission is denied, THEN THE Plugin SHALL throw an error with a message indicating which permission is missing.
