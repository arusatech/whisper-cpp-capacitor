import { WhisperCppAPI, ContextNotFoundError } from '../../src/index';

describe('WhisperCppAPI', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('on/off', () => {
    it('on adds listener for progress', () => {
      const cb = jest.fn();
      WhisperCppAPI.on('progress', cb);
      expect(() => WhisperCppAPI.off('progress', cb)).not.toThrow();
    });

    it('on adds listener for segment and error', () => {
      const cb = jest.fn();
      WhisperCppAPI.on('segment', cb);
      WhisperCppAPI.on('error', cb);
      WhisperCppAPI.off('segment', cb);
      WhisperCppAPI.off('error', cb);
    });
  });

  describe('initContext validation', () => {
    it('throws when model is missing', async () => {
      await expect(WhisperCppAPI.initContext({} as any)).rejects.toThrow(
        'model path is required'
      );
    });

    it('throws when model is empty string', async () => {
      await expect(WhisperCppAPI.initContext({ model: '' })).rejects.toThrow(
        'model path is required'
      );
    });
  });

  describe('releaseContext', () => {
    it('throws ContextNotFoundError for invalid contextId', async () => {
      await expect(WhisperCppAPI.releaseContext(0)).rejects.toThrow(ContextNotFoundError);
      await expect(WhisperCppAPI.releaseContext(-1)).rejects.toThrow(ContextNotFoundError);
      await expect(WhisperCppAPI.releaseContext(1.5)).rejects.toThrow(ContextNotFoundError);
      await expect(WhisperCppAPI.releaseContext(999)).rejects.toThrow(ContextNotFoundError);
    });
  });

  describe('transcribe validation', () => {
    it('throws when audio_data is missing', async () => {
      await expect(
        WhisperCppAPI.transcribe({ params: { model: '/m.bin' } } as any)
      ).rejects.toThrow('audio_data is required');
    });
  });

  describe('getContextRegistry', () => {
    it('returns a copy of the context registry', () => {
      const reg = WhisperCppAPI.getContextRegistry();
      expect(reg).toBeInstanceOf(Map);
      expect(reg.size).toBe(0);
    });
  });
});
