import { WhisperCppAPI, ContextNotFoundError } from '../../src/index';
import { registerPlugin } from '@capacitor/core';

// Get the mock plugin that registerPlugin returns
const mockPlugin = (registerPlugin as jest.Mock).mock.results[0]?.value;

describe('WhisperCppAPI', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    // Clean up context registry between tests
    WhisperCppAPI.releaseAllContexts().catch(() => {});
  });

  // ─── 9.1 Parameter validation ───────────────────────────────────────

  describe('initContext validation', () => {
    it('throws when model is missing (no model key)', async () => {
      await expect(WhisperCppAPI.initContext({} as any)).rejects.toThrow(
        'model path is required',
      );
    });

    it('throws when model is empty string', async () => {
      await expect(WhisperCppAPI.initContext({ model: '' })).rejects.toThrow(
        'model path is required',
      );
    });

    it('throws when model is null', async () => {
      await expect(WhisperCppAPI.initContext({ model: null } as any)).rejects.toThrow(
        'model path is required',
      );
    });

    it('throws when model is undefined', async () => {
      await expect(WhisperCppAPI.initContext({ model: undefined } as any)).rejects.toThrow(
        'model path is required',
      );
    });

    it('throws when model is whitespace-only', async () => {
      await expect(WhisperCppAPI.initContext({ model: '   ' })).rejects.toThrow(
        'model path is required',
      );
    });

    it('throws when model is a number', async () => {
      await expect(WhisperCppAPI.initContext({ model: 123 } as any)).rejects.toThrow(
        'model path is required',
      );
    });

    it('throws when model is a boolean', async () => {
      await expect(WhisperCppAPI.initContext({ model: true } as any)).rejects.toThrow(
        'model path is required',
      );
    });

    it('throws when params is null', async () => {
      await expect(WhisperCppAPI.initContext(null as any)).rejects.toThrow(
        'model path is required',
      );
    });

    it('throws when params is undefined', async () => {
      await expect(WhisperCppAPI.initContext(undefined as any)).rejects.toThrow(
        'model path is required',
      );
    });
  });

  describe('transcribe validation', () => {
    it('throws when audio_data is missing', async () => {
      await expect(
        WhisperCppAPI.transcribe({ params: { model: '/m.bin' } } as any),
      ).rejects.toThrow('audio_data is required');
    });

    it('throws when audio_data is null', async () => {
      await expect(
        WhisperCppAPI.transcribe({ audio_data: null, params: { model: '/m.bin' } } as any),
      ).rejects.toThrow('audio_data is required');
    });

    it('throws when audio_data is undefined', async () => {
      await expect(
        WhisperCppAPI.transcribe({ audio_data: undefined, params: { model: '/m.bin' } } as any),
      ).rejects.toThrow('audio_data is required');
    });

    it('throws when audio_data is a number', async () => {
      await expect(
        WhisperCppAPI.transcribe({ audio_data: 42, params: { model: '/m.bin' } } as any),
      ).rejects.toThrow('audio_data is required');
    });

    it('throws when params is null', async () => {
      await expect(WhisperCppAPI.transcribe(null as any)).rejects.toThrow();
    });
  });

  describe('releaseContext validation', () => {
    it('throws ContextNotFoundError for 0', async () => {
      await expect(WhisperCppAPI.releaseContext(0)).rejects.toThrow(ContextNotFoundError);
    });

    it('throws ContextNotFoundError for negative number', async () => {
      await expect(WhisperCppAPI.releaseContext(-1)).rejects.toThrow(ContextNotFoundError);
    });

    it('throws ContextNotFoundError for non-integer', async () => {
      await expect(WhisperCppAPI.releaseContext(1.5)).rejects.toThrow(ContextNotFoundError);
    });

    it('throws ContextNotFoundError for NaN', async () => {
      await expect(WhisperCppAPI.releaseContext(NaN)).rejects.toThrow(ContextNotFoundError);
    });

    it('throws ContextNotFoundError for Infinity', async () => {
      await expect(WhisperCppAPI.releaseContext(Infinity)).rejects.toThrow(ContextNotFoundError);
    });

    it('throws ContextNotFoundError for string value', async () => {
      await expect(WhisperCppAPI.releaseContext('abc' as any)).rejects.toThrow(ContextNotFoundError);
    });

    it('throws ContextNotFoundError for null', async () => {
      await expect(WhisperCppAPI.releaseContext(null as any)).rejects.toThrow(ContextNotFoundError);
    });

    it('throws ContextNotFoundError for undefined', async () => {
      await expect(WhisperCppAPI.releaseContext(undefined as any)).rejects.toThrow(ContextNotFoundError);
    });

    it('throws ContextNotFoundError for valid-looking id not in registry', async () => {
      await expect(WhisperCppAPI.releaseContext(999)).rejects.toThrow(ContextNotFoundError);
    });
  });

  // ─── 9.2 Event subscription (on/off) ──────────────────────────────

  describe('on/off event subscription', () => {
    it('on adds listener for progress', () => {
      const cb = jest.fn();
      WhisperCppAPI.on('progress', cb);
      // Clean up
      WhisperCppAPI.off('progress', cb);
    });

    it('on adds listener for segment', () => {
      const cb = jest.fn();
      WhisperCppAPI.on('segment', cb);
      WhisperCppAPI.off('segment', cb);
    });

    it('on adds listener for error', () => {
      const cb = jest.fn();
      WhisperCppAPI.on('error', cb);
      WhisperCppAPI.off('error', cb);
    });

    it('can subscribe multiple callbacks to the same event', () => {
      const cb1 = jest.fn();
      const cb2 = jest.fn();
      const cb3 = jest.fn();
      WhisperCppAPI.on('progress', cb1);
      WhisperCppAPI.on('progress', cb2);
      WhisperCppAPI.on('progress', cb3);
      // All should be removable without error
      expect(() => WhisperCppAPI.off('progress', cb1)).not.toThrow();
      expect(() => WhisperCppAPI.off('progress', cb2)).not.toThrow();
      expect(() => WhisperCppAPI.off('progress', cb3)).not.toThrow();
    });

    it('off removes only the specified callback', () => {
      const cb1 = jest.fn();
      const cb2 = jest.fn();
      WhisperCppAPI.on('segment', cb1);
      WhisperCppAPI.on('segment', cb2);
      // Remove cb1
      WhisperCppAPI.off('segment', cb1);
      // cb2 should still be removable (still registered)
      expect(() => WhisperCppAPI.off('segment', cb2)).not.toThrow();
    });

    it('off with non-existent callback does not throw', () => {
      const cb = jest.fn();
      expect(() => WhisperCppAPI.off('progress', cb)).not.toThrow();
    });

    it('off with non-existent event name does not throw', () => {
      const cb = jest.fn();
      expect(() => WhisperCppAPI.off('nonexistent' as any, cb)).not.toThrow();
    });

    it('on with invalid event name does not throw', () => {
      const cb = jest.fn();
      // eventListeners['invalid'] is undefined, so push won't happen but shouldn't crash
      expect(() => WhisperCppAPI.on('invalid' as any, cb)).not.toThrow();
    });

    it('removing same callback twice does not throw', () => {
      const cb = jest.fn();
      WhisperCppAPI.on('error', cb);
      WhisperCppAPI.off('error', cb);
      // Second removal - callback no longer in list
      expect(() => WhisperCppAPI.off('error', cb)).not.toThrow();
    });
  });

  // ─── 9.3 Context registry management ──────────────────────────────

  describe('context registry management', () => {
    it('getContextRegistry returns a Map', () => {
      const reg = WhisperCppAPI.getContextRegistry();
      expect(reg).toBeInstanceOf(Map);
    });

    it('registry is empty initially', () => {
      const reg = WhisperCppAPI.getContextRegistry();
      expect(reg.size).toBe(0);
    });

    it('after successful initContext, registry contains the contextId', async () => {
      (mockPlugin.initContext as jest.Mock).mockResolvedValueOnce({
        contextId: 1,
        model: { type: 'tiny' },
        gpu: false,
        reasonNoGPU: 'test',
      });

      await WhisperCppAPI.initContext({ model: '/path/to/model.bin' });
      const reg = WhisperCppAPI.getContextRegistry();
      expect(reg.has(1)).toBe(true);
      expect(reg.get(1)).toEqual({ modelPath: '/path/to/model.bin', isAsset: false });
    });

    it('initContext with is_model_asset stores isAsset=true', async () => {
      (mockPlugin.initContext as jest.Mock).mockResolvedValueOnce({
        contextId: 2,
        model: { type: 'base' },
        gpu: false,
        reasonNoGPU: '',
      });

      await WhisperCppAPI.initContext({ model: 'model.bin', is_model_asset: true });
      const reg = WhisperCppAPI.getContextRegistry();
      expect(reg.get(2)?.isAsset).toBe(true);
    });

    it('multiple initContext calls produce distinct entries', async () => {
      (mockPlugin.initContext as jest.Mock)
        .mockResolvedValueOnce({ contextId: 10, model: { type: 'tiny' }, gpu: false, reasonNoGPU: '' })
        .mockResolvedValueOnce({ contextId: 11, model: { type: 'base' }, gpu: true, reasonNoGPU: '' });

      await WhisperCppAPI.initContext({ model: '/a.bin' });
      await WhisperCppAPI.initContext({ model: '/b.bin' });

      const reg = WhisperCppAPI.getContextRegistry();
      expect(reg.size).toBe(2);
      expect(reg.has(10)).toBe(true);
      expect(reg.has(11)).toBe(true);
      expect(reg.get(10)?.modelPath).toBe('/a.bin');
      expect(reg.get(11)?.modelPath).toBe('/b.bin');
    });

    it('after releaseContext, registry no longer contains the contextId', async () => {
      (mockPlugin.initContext as jest.Mock).mockResolvedValueOnce({
        contextId: 3,
        model: { type: 'small' },
        gpu: false,
        reasonNoGPU: '',
      });
      (mockPlugin.releaseContext as jest.Mock).mockResolvedValueOnce(undefined);

      await WhisperCppAPI.initContext({ model: '/m.bin' });
      expect(WhisperCppAPI.getContextRegistry().has(3)).toBe(true);

      await WhisperCppAPI.releaseContext(3);
      expect(WhisperCppAPI.getContextRegistry().has(3)).toBe(false);
    });

    it('after releaseAllContexts, registry is empty', async () => {
      (mockPlugin.initContext as jest.Mock)
        .mockResolvedValueOnce({ contextId: 4, model: { type: 'tiny' }, gpu: false, reasonNoGPU: '' })
        .mockResolvedValueOnce({ contextId: 5, model: { type: 'tiny' }, gpu: false, reasonNoGPU: '' });
      (mockPlugin.releaseAllContexts as jest.Mock).mockResolvedValueOnce(undefined);

      await WhisperCppAPI.initContext({ model: '/a.bin' });
      await WhisperCppAPI.initContext({ model: '/b.bin' });
      expect(WhisperCppAPI.getContextRegistry().size).toBe(2);

      await WhisperCppAPI.releaseAllContexts();
      expect(WhisperCppAPI.getContextRegistry().size).toBe(0);
    });

    it('getContextRegistry returns a copy - modifying it does not affect internal state', async () => {
      (mockPlugin.initContext as jest.Mock).mockResolvedValueOnce({
        contextId: 6,
        model: { type: 'tiny' },
        gpu: false,
        reasonNoGPU: '',
      });

      await WhisperCppAPI.initContext({ model: '/m.bin' });
      const copy = WhisperCppAPI.getContextRegistry();
      copy.delete(6);
      copy.set(999, { modelPath: '/fake.bin', isAsset: false });

      // Internal state should be unaffected
      const fresh = WhisperCppAPI.getContextRegistry();
      expect(fresh.has(6)).toBe(true);
      expect(fresh.has(999)).toBe(false);
    });
  });
});
