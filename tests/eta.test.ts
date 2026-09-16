import { describe, test, expect } from 'vitest';
import { StraightLineEtaProvider } from '../lib/tracking/eta';

// =========================================================
// tests/eta.test.ts — Marine Cloud Phase 12
// =========================================================
// The fallback ETA provider must NEVER claim high confidence, must
// scale sensibly with reported speed, and must decline to guess
// (return null) when it has nothing reliable to go on.
// =========================================================

const miami = { lat: 25.7617, lng: -80.1918 };
const fortLauderdale = { lat: 26.1224, lng: -80.1373 };

describe('StraightLineEtaProvider', () => {
  test('fallback ETA is always low confidence, never claims navigation-grade accuracy', async () => {
    const provider = new StraightLineEtaProvider();
    const result = await provider.getEta(miami, fortLauderdale, null);
    expect(result).not.toBeNull();
    expect(result?.confidence).toBe('low');
    expect(result?.label).toBe('Estimated arrival');
  });

  test('a faster reported speed produces a shorter ETA than the conservative fallback speed', async () => {
    const provider = new StraightLineEtaProvider();
    const slow = await provider.getEta(miami, fortLauderdale, null);
    const fast = await provider.getEta(miami, fortLauderdale, 20);
    expect(slow).not.toBeNull();
    expect(fast).not.toBeNull();
    expect(fast!.etaMinutes).toBeLessThan(slow!.etaMinutes);
  });

  test('same origin and destination returns null rather than a fabricated zero/near-zero ETA', async () => {
    const provider = new StraightLineEtaProvider();
    const result = await provider.getEta(miami, miami, null);
    expect(result).toBeNull();
  });

  test('an implausibly distant destination returns null rather than an unreliable multi-hour estimate', async () => {
    const provider = new StraightLineEtaProvider();
    const farAway = { lat: 40.7128, lng: -74.006 };
    const result = await provider.getEta(miami, farAway, null);
    expect(result).toBeNull();
  });
});
