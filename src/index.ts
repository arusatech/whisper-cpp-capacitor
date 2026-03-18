import { registerPlugin } from '@capacitor/core';
import type {
  NativeWhisperContextParams,
  NativeWhisperContext,
  NativeTranscribeParams,
  NativeTranscriptionResult,
  StreamingTranscribeParams,
  SystemInfo,
  WhisperCppPlugin,
} from './definitions';
import { ContextNotFoundError } from './errors';

export * from './definitions';
export * from './errors';

const EVENT_PROGRESS = 'progress';
const EVENT_SEGMENT = 'segment';
const EVENT_ERROR = 'error';

const WhisperCpp = registerPlugin<WhisperCppPlugin>('WhisperCpp', {
  web: () => import('./web').then((m) => new m.WhisperCppWeb()),
});

type Listener = (...args: unknown[]) => void;
const eventListeners: Record<string, Listener[]> = {
  [EVENT_PROGRESS]: [],
  [EVENT_SEGMENT]: [],
  [EVENT_ERROR]: [],
};

function on(event: 'progress' | 'segment' | 'error', callback: Listener): void {
  if (eventListeners[event]) {
    eventListeners[event].push(callback);
  }
}

function off(event: string, callback: Listener): void {
  const list = eventListeners[event];
  if (list) {
    const i = list.indexOf(callback);
    if (i >= 0) list.splice(i, 1);
  }
}

const contextRegistry = new Map<number, { modelPath: string; isAsset: boolean }>();

function validateContextId(contextId: number): void {
  if (typeof contextId !== 'number' || contextId < 1 || !Number.isInteger(contextId)) {
    throw new ContextNotFoundError(`Invalid contextId: ${contextId}`, contextId);
  }
  if (!contextRegistry.has(contextId)) {
    throw new ContextNotFoundError(`Context ${contextId} not found or already released`, contextId);
  }
}

async function initContext(params: NativeWhisperContextParams): Promise<NativeWhisperContext> {
  if (!params?.model || typeof params.model !== 'string' || params.model.trim() === '') {
    throw new Error('initContext: model path is required and must be a non-empty string');
  }
  const result = await WhisperCpp.initContext(params);
  if (result?.contextId) {
    contextRegistry.set(result.contextId, {
      modelPath: params.model,
      isAsset: !!params.is_model_asset,
    });
  }
  return result;
}

async function releaseAllContexts(): Promise<void> {
  await WhisperCpp.releaseAllContexts();
  contextRegistry.clear();
}

async function transcribe(params: NativeTranscribeParams): Promise<NativeTranscriptionResult> {
  if (!params?.audio_data || typeof params.audio_data !== 'string') {
    throw new Error('transcribe: audio_data is required');
  }
  return WhisperCpp.transcribe(params);
}

async function transcribeRealtime(params: StreamingTranscribeParams): Promise<void> {
  return WhisperCpp.transcribeRealtime(params);
}

async function stopTranscription(): Promise<void> {
  return WhisperCpp.stopTranscription();
}

async function getSystemInfo(): Promise<SystemInfo> {
  return WhisperCpp.getSystemInfo();
}

export const WhisperCppAPI = {
  getInstance(): WhisperCppPlugin {
    return WhisperCpp;
  },

  on,
  off,

  async initContext(params: NativeWhisperContextParams): Promise<NativeWhisperContext> {
    return initContext(params);
  },

  async releaseContext(contextId: number): Promise<void> {
    validateContextId(contextId);
    await WhisperCpp.releaseContext({ contextId });
    contextRegistry.delete(contextId);
  },

  async releaseAllContexts(): Promise<void> {
    return releaseAllContexts();
  },

  async transcribe(params: NativeTranscribeParams): Promise<NativeTranscriptionResult> {
    return transcribe(params);
  },

  async transcribeRealtime(params: StreamingTranscribeParams): Promise<void> {
    return transcribeRealtime(params);
  },

  async stopTranscription(): Promise<void> {
    return stopTranscription();
  },

  async getSystemInfo(): Promise<SystemInfo> {
    return getSystemInfo();
  },

  async getModelInfo(): Promise<NativeWhisperContext['model']> {
    return WhisperCpp.getModelInfo();
  },

  async loadModel(options: { path: string; is_asset?: boolean }): Promise<void> {
    return WhisperCpp.loadModel(options);
  },

  async unloadModel(): Promise<void> {
    return WhisperCpp.unloadModel();
  },

  async getAudioFormat(options: { path: string }): Promise<import('./definitions').AudioFormat> {
    return WhisperCpp.getAudioFormat(options);
  },

  async convertAudio(options: {
    input: string;
    output: string;
    target_format: import('./definitions').AudioFormat;
  }): Promise<void> {
    return WhisperCpp.convertAudio(options);
  },

  getContextRegistry(): Map<number, { modelPath: string; isAsset: boolean }> {
    return new Map(contextRegistry);
  },
};

export { WhisperCpp };
