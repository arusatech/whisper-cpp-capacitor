// Typed errors for plugin (Requirements 11.1–11.5)

export class ModelLoadError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ModelLoadError';
    Object.setPrototypeOf(this, ModelLoadError.prototype);
  }
}

export class AudioProcessingError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'AudioProcessingError';
    Object.setPrototypeOf(this, AudioProcessingError.prototype);
  }
}

export class ContextNotFoundError extends Error {
  constructor(
    message: string,
    public readonly contextId: number
  ) {
    super(message);
    this.name = 'ContextNotFoundError';
    Object.setPrototypeOf(this, ContextNotFoundError.prototype);
  }
}

export class OutOfMemoryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'OutOfMemoryError';
    Object.setPrototypeOf(this, OutOfMemoryError.prototype);
  }
}

export class TranscriptionTimeoutError extends Error {
  constructor(
    message: string,
    public readonly partialSegments?: Array<{ start: number; end: number; text: string }>
  ) {
    super(message);
    this.name = 'TranscriptionTimeoutError';
    Object.setPrototypeOf(this, TranscriptionTimeoutError.prototype);
  }
}
