import {
  ModelLoadError,
  AudioProcessingError,
  ContextNotFoundError,
  OutOfMemoryError,
  TranscriptionTimeoutError,
} from '../../src/errors';

describe('errors', () => {
  it('ModelLoadError has name and message', () => {
    const e = new ModelLoadError('file not found');
    expect(e.name).toBe('ModelLoadError');
    expect(e.message).toBe('file not found');
  });

  it('AudioProcessingError has name and message', () => {
    const e = new AudioProcessingError('unsupported codec');
    expect(e.name).toBe('AudioProcessingError');
    expect(e.message).toBe('unsupported codec');
  });

  it('ContextNotFoundError has contextId', () => {
    const e = new ContextNotFoundError('released', 42);
    expect(e.name).toBe('ContextNotFoundError');
    expect(e.contextId).toBe(42);
  });

  it('OutOfMemoryError has name and message', () => {
    const e = new OutOfMemoryError('need 2GB');
    expect(e.name).toBe('OutOfMemoryError');
    expect(e.message).toBe('need 2GB');
  });

  it('TranscriptionTimeoutError has partialSegments', () => {
    const partial = [{ start: 0, end: 1000, text: 'hello' }];
    const e = new TranscriptionTimeoutError('timeout', partial);
    expect(e.name).toBe('TranscriptionTimeoutError');
    expect(e.partialSegments).toEqual(partial);
  });
});
