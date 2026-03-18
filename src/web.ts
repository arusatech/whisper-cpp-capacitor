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
} from './definitions';

const WEB_UNSUPPORTED = 'WhisperCpp: not implemented on web. Use native (iOS/Android) or a future WASM build.';

export class WhisperCppWeb implements WhisperCppPlugin {
  async initContext(_params: NativeWhisperContextParams): Promise<NativeWhisperContext> {
    throw new Error(WEB_UNSUPPORTED);
  }

  async releaseContext(): Promise<void> {
    // no-op on web
  }

  async releaseAllContexts(): Promise<void> {
    // no-op on web
  }

  async transcribe(_params: NativeTranscribeParams): Promise<NativeTranscriptionResult> {
    throw new Error(WEB_UNSUPPORTED);
  }

  async transcribeRealtime(_params: StreamingTranscribeParams): Promise<void> {
    throw new Error(WEB_UNSUPPORTED);
  }

  async stopTranscription(): Promise<void> {
    // no-op on web
  }

  async loadModel(): Promise<void> {
    throw new Error(WEB_UNSUPPORTED);
  }

  async unloadModel(): Promise<void> {
    // no-op on web
  }

  async getModelInfo(): Promise<NativeWhisperContext['model']> {
    throw new Error(WEB_UNSUPPORTED);
  }

  async getAudioFormat(): Promise<AudioFormat> {
    throw new Error(WEB_UNSUPPORTED);
  }

  async convertAudio(): Promise<void> {
    throw new Error(WEB_UNSUPPORTED);
  }

  async getSystemInfo(): Promise<SystemInfo> {
    return {
      platform: 'web',
      gpu_available: false,
      max_threads: typeof navigator !== 'undefined' && navigator.hardwareConcurrency
        ? navigator.hardwareConcurrency
        : 1,
      memory_available_mb:
        typeof navigator !== 'undefined' &&
        (navigator as unknown as { deviceMemory?: number }).deviceMemory != null
          ? (navigator as unknown as { deviceMemory: number }).deviceMemory * 1024
          : 0,
    };
  }
}

const WhisperCpp = registerPlugin<WhisperCppPlugin>('WhisperCpp', {
  web: () => Promise.resolve(new WhisperCppWeb()),
});

export { WhisperCpp };
