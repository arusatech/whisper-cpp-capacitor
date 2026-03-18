// Native parameter types matching whisper.cpp API (from design.md)

export interface NativeWhisperContextParams {
  model: string;
  is_model_asset?: boolean;
  use_progress_callback?: boolean;

  n_threads?: number;
  n_max_text_ctx?: number;
  offset_ms?: number;
  duration_ms?: number;

  translate?: boolean;
  no_context?: boolean;
  no_timestamps?: boolean;
  single_segment?: boolean;

  language?: string;
  detect_language?: boolean;

  split_on_word?: boolean;
  max_len?: number;
  max_tokens?: number;

  speed_up?: boolean;
  audio_ctx?: number;

  initial_prompt?: string;
  prompt_tokens?: number[];
  prompt_n_tokens?: number;

  temperature?: number;
  temperature_inc?: number;
  entropy_thold?: number;
  logprob_thold?: number;
  no_speech_thold?: number;

  beam_size?: number;
  best_of?: number;

  use_gpu?: boolean;

  tdrz_enable?: boolean;

  token_timestamps?: boolean;
  thold_pt?: number;
  thold_ptsum?: number;
  max_context?: number;
  max_initial_ts?: number;
}

export interface NativeTranscribeParams {
  contextId?: number;
  audio_data: string;
  is_audio_file?: boolean;
  params: NativeWhisperContextParams;
}

export interface WhisperSegment {
  start: number;
  end: number;
  text: string;
  tokens?: number[];
  speaker_id?: number;
  confidence?: number;
  no_speech_prob?: number;
}

export interface WhisperWord {
  word: string;
  start: number;
  end: number;
  confidence: number;
}

export interface NativeTranscriptionResult {
  text: string;
  segments: WhisperSegment[];
  words?: WhisperWord[];
  language: string;
  language_prob: number;
  duration_ms: number;
  processing_time_ms: number;
}

export interface NativeWhisperContext {
  contextId: number;
  model: {
    type: string;
    is_multilingual: boolean;
    vocab_size: number;
    n_audio_ctx: number;
    n_audio_state: number;
    n_audio_head: number;
    n_audio_layer: number;
    n_text_ctx: number;
    n_text_state: number;
    n_text_head: number;
    n_text_layer: number;
    n_mels: number;
    ftype: number;
  };
  gpu: boolean;
  reasonNoGPU: string;
}

export interface AudioFormat {
  sample_rate: number;
  channels: number;
  bits_per_sample: number;
  format: 'wav' | 'mp3' | 'ogg' | 'flac' | 'm4a' | 'webm';
}

export interface StreamingTranscribeParams {
  chunk_length_ms?: number;
  step_length_ms?: number;
  params: NativeWhisperContextParams;
}

export interface SystemInfo {
  platform: string;
  gpu_available: boolean;
  max_threads: number;
  memory_available_mb: number;
}

export interface WhisperCppPlugin {
  initContext(params: NativeWhisperContextParams): Promise<NativeWhisperContext>;
  releaseContext(options: { contextId: number }): Promise<void>;
  releaseAllContexts(): Promise<void>;

  transcribe(params: NativeTranscribeParams): Promise<NativeTranscriptionResult>;
  transcribeRealtime(params: StreamingTranscribeParams): Promise<void>;
  stopTranscription(): Promise<void>;

  loadModel(options: { path: string; is_asset?: boolean }): Promise<void>;
  unloadModel(): Promise<void>;
  getModelInfo(): Promise<NativeWhisperContext['model']>;

  getAudioFormat(options: { path: string }): Promise<AudioFormat>;
  convertAudio(options: {
    input: string;
    output: string;
    target_format: AudioFormat;
  }): Promise<void>;

  getSystemInfo(): Promise<SystemInfo>;
}
