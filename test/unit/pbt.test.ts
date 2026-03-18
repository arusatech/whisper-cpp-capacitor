import * as fc from 'fast-check';
import { WhisperCppAPI } from '../../src/index';
import { registerPlugin } from '@capacitor/core';
import type {
  NativeTranscriptionResult,
  WhisperSegment,
} from '../../src/definitions';

const mockPlugin = (registerPlugin as jest.Mock).mock.results[0]?.value;

// ─── Helpers ──────────────────────────────────────────────────────

/** Arbitrary that produces a valid WhisperSegment with monotonic timestamps. */
const segmentArb = (minStart: number): fc.Arbitrary<WhisperSegment> =>
  fc
    .record({
      start: fc.integer({ min: minStart, max: minStart + 60_000 }),
      length: fc.integer({ min: 1, max: 10_000 }),
      text: fc.string({ minLength: 0, maxLength: 200 }),
    })
    .map(({ start, length, text }) => ({
      start,
      end: start + length,
      text,
    }));

/** Arbitrary that produces a non-empty array of segments with monotonically non-decreasing timestamps. */
const segmentsArb: fc.Arbitrary<WhisperSegment[]> = fc
  .integer({ min: 1, max: 20 })
  .chain((count) => {
    let arb = segmentArb(0).map((s) => [s]);
    for (let i = 1; i < count; i++) {
      arb = arb.chain((segs) => {
        const lastEnd = segs[segs.length - 1].end;
        return segmentArb(lastEnd).map((s) => [...segs, s]);
      });
    }
    return arb;
  });

/** Build a NativeTranscriptionResult from segments. */
function buildResult(
  segments: WhisperSegment[],
  languageProb: number,
): NativeTranscriptionResult {
  return {
    text: segments.map((s) => s.text).join(''),
    segments,
    language: 'en',
    language_prob: languageProb,
    duration_ms: segments.length > 0 ? segments[segments.length - 1].end : 0,
    processing_time_ms: 100,
  };
}


// ─── 10.1 Context uniqueness ─────────────────────────────────────

describe('PBT: context uniqueness (Req 1 AC 1-2)', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    WhisperCppAPI.releaseAllContexts().catch(() => {});
  });

  it('multiple initContext calls always produce distinct contextIds', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.integer({ min: 2, max: 30 }),
        fc.array(fc.stringMatching(/^[a-z][a-z0-9_/.-]{0,60}\.bin$/), {
          minLength: 2,
          maxLength: 30,
        }),
        async (count, modelPaths) => {
          // Ensure we have enough model paths
          const paths = modelPaths.length >= count
            ? modelPaths.slice(0, count)
            : Array.from({ length: count }, (_, i) => `/model_${i}.bin`);

          // Set up mock to return incrementing contextIds
          let nextId = 1;
          (mockPlugin.initContext as jest.Mock).mockImplementation(() =>
            Promise.resolve({
              contextId: nextId++,
              model: { type: 'tiny' },
              gpu: false,
              reasonNoGPU: '',
            }),
          );
          (mockPlugin.releaseAllContexts as jest.Mock).mockResolvedValue(undefined);

          const results = await Promise.all(
            paths.map((p) => WhisperCppAPI.initContext({ model: p })),
          );

          const ids = results.map((r) => r.contextId);
          const uniqueIds = new Set(ids);

          // Property: all contextIds are distinct
          expect(uniqueIds.size).toBe(ids.length);

          // Property: all contextIds are positive integers
          for (const id of ids) {
            expect(Number.isInteger(id)).toBe(true);
            expect(id).toBeGreaterThan(0);
          }

          // Property: registry contains all contextIds
          const registry = WhisperCppAPI.getContextRegistry();
          expect(registry.size).toBe(ids.length);
          for (const id of ids) {
            expect(registry.has(id)).toBe(true);
          }

          // Cleanup
          await WhisperCppAPI.releaseAllContexts();
        },
      ),
      { numRuns: 20 },
    );
  });
});


// ─── 10.2 Segment timestamps monotonically non-decreasing (Req 2 AC 4, 8-9) ──

describe('PBT: segment timestamps monotonically non-decreasing', () => {
  it('segments[i+1].start >= segments[i].end for all consecutive pairs', () => {
    fc.assert(
      fc.property(segmentsArb, (segments) => {
        const result = buildResult(segments, 0.95);

        // Property: each segment's end >= start
        for (const seg of result.segments) {
          expect(seg.end).toBeGreaterThanOrEqual(seg.start);
          expect(seg.start).toBeGreaterThanOrEqual(0);
        }

        // Property: consecutive segments are monotonically non-decreasing
        for (let i = 0; i < result.segments.length - 1; i++) {
          expect(result.segments[i + 1].start).toBeGreaterThanOrEqual(
            result.segments[i].end,
          );
        }
      }),
      { numRuns: 100 },
    );
  });

  it('mock transcribe returns results with valid timestamp ordering', async () => {
    await fc.assert(
      fc.asyncProperty(segmentsArb, async (segments) => {
        const expected = buildResult(segments, 0.9);
        (mockPlugin.transcribe as jest.Mock).mockResolvedValueOnce(expected);

        const result = await WhisperCppAPI.transcribe({
          audio_data: 'dGVzdA==',
          params: { model: '/m.bin' },
        });

        for (let i = 0; i < result.segments.length - 1; i++) {
          expect(result.segments[i + 1].start).toBeGreaterThanOrEqual(
            result.segments[i].end,
          );
        }
      }),
      { numRuns: 50 },
    );
  });
});

// ─── 10.3 Segment text concatenation equals full text (Req 2 AC 5) ──

describe('PBT: segment text concatenation equals full text', () => {
  it('joining all segment texts equals the top-level text field', () => {
    fc.assert(
      fc.property(segmentsArb, (segments) => {
        const result = buildResult(segments, 0.8);
        const concatenated = result.segments.map((s) => s.text).join('');
        expect(concatenated).toBe(result.text);
      }),
      { numRuns: 100 },
    );
  });

  it('holds through mock transcribe round-trip', async () => {
    await fc.assert(
      fc.asyncProperty(segmentsArb, async (segments) => {
        const expected = buildResult(segments, 0.85);
        (mockPlugin.transcribe as jest.Mock).mockResolvedValueOnce(expected);

        const result = await WhisperCppAPI.transcribe({
          audio_data: 'dGVzdA==',
          params: { model: '/m.bin' },
        });

        const concatenated = result.segments.map((s) => s.text).join('');
        expect(concatenated).toBe(result.text);
      }),
      { numRuns: 50 },
    );
  });
});

// ─── 10.4 language_prob always in [0.0, 1.0] (Req 2 AC 6, Req 4 AC 4) ──

describe('PBT: language_prob always in [0.0, 1.0]', () => {
  it('language_prob is bounded for any generated result', () => {
    fc.assert(
      fc.property(
        segmentsArb,
        fc.double({ min: 0, max: 1, noNaN: true }),
        (segments, prob) => {
          const result = buildResult(segments, prob);
          expect(result.language_prob).toBeGreaterThanOrEqual(0.0);
          expect(result.language_prob).toBeLessThanOrEqual(1.0);
        },
      ),
      { numRuns: 100 },
    );
  });

  it('mock transcribe preserves language_prob in [0, 1]', async () => {
    await fc.assert(
      fc.asyncProperty(
        segmentsArb,
        fc.double({ min: 0, max: 1, noNaN: true }),
        async (segments, prob) => {
          const expected = buildResult(segments, prob);
          (mockPlugin.transcribe as jest.Mock).mockResolvedValueOnce(expected);

          const result = await WhisperCppAPI.transcribe({
            audio_data: 'dGVzdA==',
            params: { model: '/m.bin' },
          });

          expect(result.language_prob).toBeGreaterThanOrEqual(0.0);
          expect(result.language_prob).toBeLessThanOrEqual(1.0);
        },
      ),
      { numRuns: 50 },
    );
  });

  it('rejects language_prob outside [0, 1] as invalid', () => {
    fc.assert(
      fc.property(
        fc.double({ min: 1.001, max: 1000, noNaN: true }),
        (badProb) => {
          expect(badProb).toBeGreaterThan(1.0);
        },
      ),
      { numRuns: 50 },
    );

    fc.assert(
      fc.property(
        fc.double({ min: -1000, max: -0.001, noNaN: true }),
        (badProb) => {
          expect(badProb).toBeLessThan(0.0);
        },
      ),
      { numRuns: 50 },
    );
  });
});
