/**
 * Web/WASM implementation of WhisperCppPlugin.
 *
 * Uses the Emscripten-compiled whisper.cpp module (dist/wasm/whisper.js).
 * The WASM module exposes: init, free_context, free_all, transcribe,
 * get_model_info, get_progress, wasm_malloc, wasm_free.
 *
 * Model files are stored in the Emscripten virtual filesystem (MEMFS)
 * and optionally cached in IndexedDB for persistence across sessions.
 */

import { registerPlugin } from '@capacitor/core';
import type {
  NativeWhisperContextParams,
  NativeWhisperContext,
  NativeTranscribeParams,
  NativeTranscriptionResult,
  StreamingTranscribeParams,
  AudioFormat,
  SystemInfo,
  WhisperCppPlugin,
  WhisperSegment,
  WhisperWord,
} from './definitions';

// The WASM module factory — loaded lazily
type WhisperWasmModule = {
  init(modelPath: string, useGpu: boolean, nThreads: number): string;
  free_context(contextId: number): boolean;
  free_all(): void;
  transcribe(
    contextId: number,
    samplesPtr: number, nSamples: number,
    nThreads: number, translate: boolean, language: string,
    detectLanguage: boolean, tokenTimestamps: boolean, tdrzEnable: boolean,
    beamSize: number, bestOf: number, temperature: number,
    initialPrompt: string, useProgressCallback: boolean,
  ): string;
  get_model_info(contextId: number): string;
  get_progress(): number;
  wasm_malloc(bytes: number): number;
  wasm_free(ptr: number): void;
  FS: {
    writeFile(path: string, data: Uint8Array): void;
    readFile(path: string): Uint8Array;
    unlink(path: string): void;
    mkdir(path: string): void;
    stat(path: string): unknown;
  };
  HEAPF32: Float32Array;
  HEAPU8: Uint8Array;
};

// IndexedDB cache for model files
const DB_NAME = 'whisper-cpp-models';
const DB_VERSION = 1;
const DB_STORE = 'models';

async function openModelDB(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION);
    req.onupgradeneeded = () => {
      req.result.createObjectStore(DB_STORE);
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

async function getCachedModel(key: string): Promise<Uint8Array | null> {
  try {
    const db = await openModelDB();
    return new Promise((resolve) => {
      const tx = db.transaction(DB_STORE, 'readonly');
      const rq = tx.objectStore(DB_STORE).get(key);
      rq.onsuccess = () => resolve(rq.result ?? null);
      rq.onerror = () => resolve(null);
    });
  } catch {
    return null;
  }
}

async function setCachedModel(key: string, data: Uint8Array): Promise<void> {
  try {
    const db = await openModelDB();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(DB_STORE, 'readwrite');
      const rq = tx.objectStore(DB_STORE).put(data, key);
      rq.onsuccess = () => resolve();
      rq.onerror = () => reject(rq.error);
    });
  } catch {
    // cache failure is non-fatal
  }
}

/**
 * Fetch a model file from a URL with progress reporting.
 * Checks IndexedDB cache first.
 */
async function fetchModelData(
  url: string,
  onProgress?: (pct: number) => void,
): Promise<Uint8Array> {
  // Check cache
  const cached = await getCachedModel(url);
  if (cached) return cached;

  const resp = await fetch(url);
  if (!resp.ok) throw new Error(`Failed to fetch model: ${resp.status} ${resp.statusText}`);

  const contentLength = parseInt(resp.headers.get('content-length') ?? '0', 10);
  const reader = resp.body?.getReader();
  if (!reader) throw new Error('ReadableStream not supported');

  const chunks: Uint8Array[] = [];
  let received = 0;

  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(value);
    received += value.length;
    if (contentLength > 0 && onProgress) {
      onProgress(Math.round((received / contentLength) * 100));
    }
  }

  const result = new Uint8Array(received);
  let offset = 0;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.length;
  }

  // Cache for next time
  await setCachedModel(url, result);
  return result;
}

/**
 * Decode audio from various formats to 16kHz mono Float32 PCM
 * using the Web Audio API (OfflineAudioContext).
 */
async function decodeAudioToFloat32(audioData: ArrayBuffer): Promise<Float32Array> {
  // Use a temporary AudioContext to decode
  const audioCtx = new (window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext)();
  const decoded = await audioCtx.decodeAudioData(audioData);
  await audioCtx.close();

  const targetSampleRate = 16000;
  const duration = decoded.duration;
  const outLength = Math.ceil(duration * targetSampleRate);

  // Use OfflineAudioContext to resample to 16kHz mono
  const offline = new OfflineAudioContext(1, outLength, targetSampleRate);
  const source = offline.createBufferSource();
  source.buffer = decoded;
  source.connect(offline.destination);
  source.start(0);

  const rendered = await offline.startRendering();
  return rendered.getChannelData(0);
}

export class WhisperCppWeb implements WhisperCppPlugin {
  private module: WhisperWasmModule | null = null;
  private moduleLoading: Promise<WhisperWasmModule> | null = null;
  private contextParams = new Map<number, NativeWhisperContextParams>();
  private streamingActive = false;
  private streamingAbort = false;

  /**
   * Lazily load and initialize the WASM module.
   * Looks for the module at dist/wasm/whisper.js (relative to the app).
   */
  private async getModule(): Promise<WhisperWasmModule> {
    if (this.module) return this.module;
    if (this.moduleLoading) return this.moduleLoading;

    this.moduleLoading = (async () => {
      // Dynamic import of the Emscripten-generated module factory.
      // The build produces dist/wasm/whisper.js which exports WhisperModule.
      // In a bundled app this path may vary — users can override via window.WhisperModule.
      let factory: (opts?: Record<string, unknown>) => Promise<WhisperWasmModule>;

      if (typeof (globalThis as unknown as Record<string, unknown>).WhisperModule === 'function') {
        factory = (globalThis as unknown as Record<string, unknown>).WhisperModule as typeof factory;
      } else {
        // Try importing from the expected path
        try {
          // eslint-disable-next-line @typescript-eslint/no-implied-eval
          const importPath = './wasm/whisper.js';
          const mod = await (Function('p', 'return import(p)')(importPath) as Promise<Record<string, unknown>>);
          factory = (mod.default || mod.WhisperModule || mod) as typeof factory;
        } catch {
          throw new Error(
            'WhisperCpp WASM module not found. ' +
            'Run ./build-native-web.sh and ensure dist/wasm/whisper.js is available, ' +
            'or set window.WhisperModule to the factory function.',
          );
        }
      }

      const m = await factory({
        print: (text: string) => console.log('[whisper.wasm]', text),
        printErr: (text: string) => console.warn('[whisper.wasm]', text),
      });

      // Create /models directory in the virtual FS
      try { m.FS.mkdir('/models'); } catch { /* already exists */ }

      this.module = m;
      return m;
    })();

    return this.moduleLoading;
  }

  /**
   * Load a model file into the WASM virtual filesystem.
   * Supports URLs (http/https), data URIs, and pre-loaded paths.
   */
  private async loadModelToFS(
    m: WhisperWasmModule,
    modelPath: string,
    onProgress?: (pct: number) => void,
  ): Promise<string> {
    const fsPath = `/models/${modelPath.split('/').pop() ?? 'model.bin'}`;

    // Check if already loaded in FS
    try {
      m.FS.stat(fsPath);
      return fsPath;
    } catch { /* not loaded yet */ }

    let data: Uint8Array;

    if (modelPath.startsWith('http://') || modelPath.startsWith('https://')) {
      data = await fetchModelData(modelPath, onProgress);
    } else if (modelPath.startsWith('data:')) {
      // data URI — extract base64
      const b64 = modelPath.split(',')[1];
      const binary = atob(b64);
      data = new Uint8Array(binary.length);
      for (let i = 0; i < binary.length; i++) data[i] = binary.charCodeAt(i);
    } else {
      // Assume it's a relative URL
      data = await fetchModelData(modelPath, onProgress);
    }

    m.FS.writeFile(fsPath, data);
    return fsPath;
  }

  async initContext(params: NativeWhisperContextParams): Promise<NativeWhisperContext> {
    const m = await this.getModule();
    const nThreads = params.n_threads ?? Math.min(navigator.hardwareConcurrency ?? 4, 8);
    const fsPath = await this.loadModelToFS(m, params.model);

    const jsonStr = m.init(fsPath, false, nThreads);
    if (!jsonStr || jsonStr === '{}') {
      throw new Error('Failed to initialize whisper context from model: ' + params.model);
    }

    const result: NativeWhisperContext = JSON.parse(jsonStr);
    this.contextParams.set(result.contextId, params);
    return result;
  }

  async releaseContext(options: { contextId: number }): Promise<void> {
    const m = await this.getModule();
    m.free_context(options.contextId);
    this.contextParams.delete(options.contextId);
  }

  async releaseAllContexts(): Promise<void> {
    const m = await this.getModule();
    m.free_all();
    this.contextParams.clear();
  }

  async transcribe(params: NativeTranscribeParams): Promise<NativeTranscriptionResult> {
    const m = await this.getModule();
    const p = params.params;
    const contextId = params.contextId ?? 0;

    // Decode audio to Float32 PCM at 16kHz mono
    let pcm: Float32Array;

    if (params.is_audio_file) {
      // audio_data is a URL/path — fetch and decode
      const resp = await fetch(params.audio_data);
      const buf = await resp.arrayBuffer();
      pcm = await decodeAudioToFloat32(buf);
    } else {
      // audio_data is base64-encoded raw float32 PCM
      const binary = atob(params.audio_data);
      const bytes = new Uint8Array(binary.length);
      for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);

      // Check if it looks like raw float32 (length divisible by 4)
      if (bytes.length % 4 === 0 && bytes.length > 44) {
        // Check for WAV header
        const header = String.fromCharCode(bytes[0], bytes[1], bytes[2], bytes[3]);
        if (header === 'RIFF') {
          // It's a WAV file encoded as base64 — decode via Web Audio API
          pcm = await decodeAudioToFloat32(bytes.buffer);
        } else {
          // Raw float32 PCM
          pcm = new Float32Array(bytes.buffer);
        }
      } else {
        // Try decoding as audio file
        pcm = await decodeAudioToFloat32(bytes.buffer);
      }
    }

    if (pcm.length === 0) {
      throw new Error('No audio samples after decoding');
    }

    // Copy PCM data to WASM heap
    const nSamples = pcm.length;
    const bytesNeeded = nSamples * 4;
    const ptr = m.wasm_malloc(bytesNeeded);
    if (!ptr) throw new Error('WASM malloc failed — out of memory');

    try {
      // Write float32 samples into WASM memory
      const heapF32 = new Float32Array(m.HEAPU8.buffer, ptr, nSamples);
      heapF32.set(pcm);

      const jsonStr = m.transcribe(
        contextId,
        ptr,
        nSamples,
        p.n_threads ?? Math.min(navigator.hardwareConcurrency ?? 4, 8),
        p.translate ?? false,
        p.language ?? '',
        p.detect_language ?? !p.language,
        p.token_timestamps ?? false,
        p.tdrz_enable ?? false,
        p.beam_size ?? 1,
        p.best_of ?? 1,
        p.temperature ?? 0.0,
        p.initial_prompt ?? '',
        p.use_progress_callback ?? false,
      );

      if (!jsonStr || jsonStr === '{}') {
        throw new Error('Transcription failed');
      }

      const raw = JSON.parse(jsonStr);
      const result: NativeTranscriptionResult = {
        text: raw.text ?? '',
        segments: (raw.segments ?? []).map((s: Record<string, unknown>) => ({
          start: s.start as number,
          end: s.end as number,
          text: s.text as string,
          no_speech_prob: s.no_speech_prob as number,
          speaker_id: s.speaker_id as number,
        } as WhisperSegment)),
        words: (raw.words ?? []).map((w: Record<string, unknown>) => ({
          word: w.word as string,
          start: w.start as number,
          end: w.end as number,
          confidence: w.confidence as number,
        } as WhisperWord)),
        language: raw.language ?? 'en',
        language_prob: raw.language_prob ?? 0,
        duration_ms: raw.duration_ms ?? 0,
        processing_time_ms: raw.processing_time_ms ?? 0,
      };

      return result;
    } finally {
      // Always free WASM memory
      m.wasm_free(ptr);
    }
  }

  async transcribeRealtime(params: StreamingTranscribeParams): Promise<void> {
    if (this.streamingActive) {
      throw new Error('A streaming session is already active');
    }

    const m = await this.getModule();
    const p = params.params;
    const chunkLengthMs = params.chunk_length_ms ?? 3000;
    const sampleRate = 16000;
    const chunkSamples = Math.floor(sampleRate * chunkLengthMs / 1000);

    // Request microphone access
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    const audioCtx = new AudioContext({ sampleRate });
    const source = audioCtx.createMediaStreamSource(stream);

    // Use ScriptProcessorNode for broad compatibility (AudioWorklet would be better
    // but requires a separate file and HTTPS — ScriptProcessor works everywhere).
    const bufferSize = 4096;
    const processor = audioCtx.createScriptProcessor(bufferSize, 1, 1);

    let sampleBuffer: Float32Array[] = [];
    let totalBuffered = 0;

    this.streamingActive = true;
    this.streamingAbort = false;

    // Find contextId — use first available context or 0
    let contextId = 0;
    for (const [id] of this.contextParams) {
      contextId = id;
      break;
    }

    processor.onaudioprocess = (e) => {
      if (this.streamingAbort) return;
      const input = e.inputBuffer.getChannelData(0);

      // Resample if audioCtx.sampleRate !== 16000
      let samples: Float32Array;
      if (audioCtx.sampleRate !== sampleRate) {
        const ratio = sampleRate / audioCtx.sampleRate;
        const outLen = Math.floor(input.length * ratio);
        samples = new Float32Array(outLen);
        for (let i = 0; i < outLen; i++) {
          const srcIdx = i / ratio;
          const idx0 = Math.floor(srcIdx);
          const frac = srcIdx - idx0;
          const idx1 = Math.min(idx0 + 1, input.length - 1);
          samples[i] = input[idx0] * (1 - frac) + input[idx1] * frac;
        }
      } else {
        samples = new Float32Array(input);
      }

      sampleBuffer.push(samples);
      totalBuffered += samples.length;

      // Process when we have enough samples
      if (totalBuffered >= chunkSamples) {
        const chunk = new Float32Array(totalBuffered);
        let offset = 0;
        for (const buf of sampleBuffer) {
          chunk.set(buf, offset);
          offset += buf.length;
        }
        sampleBuffer = [];
        totalBuffered = 0;

        // Transcribe the chunk
        const nSamples = chunk.length;
        const ptr = m.wasm_malloc(nSamples * 4);
        if (ptr) {
          const heapF32 = new Float32Array(m.HEAPU8.buffer, ptr, nSamples);
          heapF32.set(chunk);

          try {
            const jsonStr = m.transcribe(
              contextId, ptr, nSamples,
              p.n_threads ?? Math.min(navigator.hardwareConcurrency ?? 4, 8),
              p.translate ?? false,
              p.language ?? '',
              p.detect_language ?? !p.language,
              false, false, 1, 1, 0.0, '', false,
            );

            if (jsonStr && jsonStr !== '{}') {
              const raw = JSON.parse(jsonStr);
              // Emit segment events via CustomEvent on window
              for (const seg of (raw.segments ?? [])) {
                window.dispatchEvent(new CustomEvent('whisper-segment', { detail: seg }));
              }
            }
          } catch (err) {
            window.dispatchEvent(new CustomEvent('whisper-error', {
              detail: { message: String(err) },
            }));
          } finally {
            m.wasm_free(ptr);
          }
        }
      }
    };

    source.connect(processor);
    processor.connect(audioCtx.destination);

    // Store cleanup references
    (this as unknown as Record<string, unknown>)._streamCleanup = () => {
      processor.disconnect();
      source.disconnect();
      audioCtx.close();
      stream.getTracks().forEach(t => t.stop());
      this.streamingActive = false;
    };
  }

  async stopTranscription(): Promise<void> {
    this.streamingAbort = true;
    const cleanup = (this as unknown as Record<string, unknown>)._streamCleanup as (() => void) | undefined;
    if (cleanup) {
      cleanup();
      (this as unknown as Record<string, unknown>)._streamCleanup = undefined;
    }
    this.streamingActive = false;
  }

  async loadModel(options: { path: string; is_asset?: boolean }): Promise<void> {
    const m = await this.getModule();
    await this.loadModelToFS(m, options.path);
  }

  async unloadModel(): Promise<void> {
    await this.releaseAllContexts();
  }

  async getModelInfo(): Promise<NativeWhisperContext['model']> {
    const m = await this.getModule();
    // Return info for the first available context
    for (const [id] of this.contextParams) {
      const jsonStr = m.get_model_info(id);
      if (jsonStr && jsonStr !== '{}') {
        return JSON.parse(jsonStr);
      }
    }
    throw new Error('No active context — call initContext first');
  }

  async getAudioFormat(options: { path: string }): Promise<AudioFormat> {
    // Determine format from file extension
    const ext = (options.path.split('.').pop() ?? '').toLowerCase();
    const formatMap: Record<string, AudioFormat['format']> = {
      wav: 'wav', mp3: 'mp3', ogg: 'ogg', flac: 'flac',
      m4a: 'm4a', aac: 'm4a', webm: 'webm',
    };
    const format = formatMap[ext] ?? 'wav';

    // Fetch and decode to get actual audio properties
    const resp = await fetch(options.path);
    const buf = await resp.arrayBuffer();
    const audioCtx = new (window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext)();
    const decoded = await audioCtx.decodeAudioData(buf);
    const result: AudioFormat = {
      sample_rate: decoded.sampleRate,
      channels: decoded.numberOfChannels,
      bits_per_sample: 32, // Web Audio API always decodes to float32
      format,
    };
    await audioCtx.close();
    return result;
  }

  async convertAudio(_options: {
    input: string;
    output: string;
    target_format: AudioFormat;
  }): Promise<void> {
    throw new Error('convertAudio is not supported on web');
  }

  async getSystemInfo(): Promise<SystemInfo> {
    const nav = typeof navigator !== 'undefined' ? navigator : null;
    return {
      platform: 'web',
      gpu_available: typeof (nav as unknown as Record<string, unknown>)?.gpu !== 'undefined',
      max_threads: nav?.hardwareConcurrency ?? 1,
      memory_available_mb:
        (nav as unknown as { deviceMemory?: number })?.deviceMemory != null
          ? (nav as unknown as { deviceMemory: number }).deviceMemory * 1024
          : 0,
    };
  }
}

const WhisperCpp = registerPlugin<WhisperCppPlugin>('WhisperCpp', {
  web: () => Promise.resolve(new WhisperCppWeb()),
});

export { WhisperCpp };
