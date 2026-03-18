import {
  ModelLoadError,
  AudioProcessingError,
  ContextNotFoundError,
  OutOfMemoryError,
  TranscriptionTimeoutError,
} from '../../src/errors';

describe('Error classes', () => {
  // ─── ModelLoadError ─────────────────────────────────────────────

  describe('ModelLoadError', () => {
    it('has correct name and message', () => {
      const e = new ModelLoadError('file not found');
      expect(e.name).toBe('ModelLoadError');
      expect(e.message).toBe('file not found');
    });

    it('is instanceof Error', () => {
      const e = new ModelLoadError('bad model');
      expect(e).toBeInstanceOf(Error);
    });

    it('is instanceof ModelLoadError', () => {
      const e = new ModelLoadError('bad model');
      expect(e).toBeInstanceOf(ModelLoadError);
    });

    it('has a stack trace', () => {
      const e = new ModelLoadError('stack test');
      expect(e.stack).toBeDefined();
      expect(e.stack).toContain('ModelLoadError');
    });

    it('preserves message correctly', () => {
      const msg = 'Model /path/to/model.bin could not be loaded';
      const e = new ModelLoadError(msg);
      expect(e.message).toBe(msg);
    });
  });

  // ─── AudioProcessingError ───────────────────────────────────────

  describe('AudioProcessingError', () => {
    it('has correct name and message', () => {
      const e = new AudioProcessingError('unsupported codec');
      expect(e.name).toBe('AudioProcessingError');
      expect(e.message).toBe('unsupported codec');
    });

    it('is instanceof Error', () => {
      const e = new AudioProcessingError('bad audio');
      expect(e).toBeInstanceOf(Error);
    });

    it('is instanceof AudioProcessingError', () => {
      const e = new AudioProcessingError('bad audio');
      expect(e).toBeInstanceOf(AudioProcessingError);
    });

    it('has a stack trace', () => {
      const e = new AudioProcessingError('stack test');
      expect(e.stack).toBeDefined();
      expect(e.stack).toContain('AudioProcessingError');
    });
  });

  // ─── ContextNotFoundError ───────────────────────────────────────

  describe('ContextNotFoundError', () => {
    it('has correct name, message, and contextId', () => {
      const e = new ContextNotFoundError('released', 42);
      expect(e.name).toBe('ContextNotFoundError');
      expect(e.message).toBe('released');
      expect(e.contextId).toBe(42);
    });

    it('is instanceof Error', () => {
      const e = new ContextNotFoundError('gone', 1);
      expect(e).toBeInstanceOf(Error);
    });

    it('is instanceof ContextNotFoundError', () => {
      const e = new ContextNotFoundError('gone', 1);
      expect(e).toBeInstanceOf(ContextNotFoundError);
    });

    it('works with contextId 0', () => {
      const e = new ContextNotFoundError('invalid id', 0);
      expect(e.contextId).toBe(0);
      expect(e.message).toBe('invalid id');
    });

    it('has a stack trace', () => {
      const e = new ContextNotFoundError('stack test', 99);
      expect(e.stack).toBeDefined();
      expect(e.stack).toContain('ContextNotFoundError');
    });
  });

  // ─── OutOfMemoryError ──────────────────────────────────────────

  describe('OutOfMemoryError', () => {
    it('has correct name and message', () => {
      const e = new OutOfMemoryError('need 2GB');
      expect(e.name).toBe('OutOfMemoryError');
      expect(e.message).toBe('need 2GB');
    });

    it('is instanceof Error', () => {
      const e = new OutOfMemoryError('oom');
      expect(e).toBeInstanceOf(Error);
    });

    it('is instanceof OutOfMemoryError', () => {
      const e = new OutOfMemoryError('oom');
      expect(e).toBeInstanceOf(OutOfMemoryError);
    });

    it('has a stack trace', () => {
      const e = new OutOfMemoryError('stack test');
      expect(e.stack).toBeDefined();
      expect(e.stack).toContain('OutOfMemoryError');
    });
  });

  // ─── TranscriptionTimeoutError ─────────────────────────────────

  describe('TranscriptionTimeoutError', () => {
    it('has correct name, message, and partialSegments', () => {
      const partial = [{ start: 0, end: 1000, text: 'hello' }];
      const e = new TranscriptionTimeoutError('timeout', partial);
      expect(e.name).toBe('TranscriptionTimeoutError');
      expect(e.message).toBe('timeout');
      expect(e.partialSegments).toEqual(partial);
    });

    it('is instanceof Error', () => {
      const e = new TranscriptionTimeoutError('timeout');
      expect(e).toBeInstanceOf(Error);
    });

    it('is instanceof TranscriptionTimeoutError', () => {
      const e = new TranscriptionTimeoutError('timeout');
      expect(e).toBeInstanceOf(TranscriptionTimeoutError);
    });

    it('partialSegments is undefined when not provided', () => {
      const e = new TranscriptionTimeoutError('timeout');
      expect(e.partialSegments).toBeUndefined();
    });

    it('has a stack trace', () => {
      const e = new TranscriptionTimeoutError('stack test');
      expect(e.stack).toBeDefined();
      expect(e.stack).toContain('TranscriptionTimeoutError');
    });

    it('preserves multiple partial segments', () => {
      const partial = [
        { start: 0, end: 500, text: 'hello' },
        { start: 500, end: 1000, text: 'world' },
      ];
      const e = new TranscriptionTimeoutError('timed out', partial);
      expect(e.partialSegments).toHaveLength(2);
      expect(e.partialSegments![0].text).toBe('hello');
      expect(e.partialSegments![1].text).toBe('world');
    });
  });
});
