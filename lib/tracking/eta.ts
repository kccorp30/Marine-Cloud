// =========================================================
// lib/tracking/eta.ts — Marine Cloud Phase 12
// =========================================================
// ETA abstraction. No route-provider (Google Directions, Mapbox
// Directions, etc.) is configured in this phase — see
// docs/PHASE-12-REPORT.md for integration requirements. Rather than
// fabricate a straight-line-distance ETA and present it as accurate,
// this module:
//
//   1. Defines the interface a real provider would implement
//      (EtaProvider) — swapping one in later requires no caller
//      changes.
//   2. Ships a StraightLineEtaProvider fallback that computes a
//      distance-based rough estimate, but ALWAYS labels it
//      "Estimated" and returns confidence: 'low' — callers must
//      never present a low-confidence estimate as navigation-grade.
//
// If ROUTE_PROVIDER_API_KEY is not configured, getEta() falls back
// to the straight-line estimate. If distance/position data is
// insufficient, it returns null (omit ETA) rather than guess.
// =========================================================

export interface EtaResult {
  etaMinutes: number;
  confidence: 'high' | 'low';
  label: string; // e.g. "Estimated arrival" vs "Arriving" — UI-ready
}

export interface EtaProvider {
  getEta(from: { lat: number; lng: number }, to: { lat: number; lng: number }, speedMps?: number | null): Promise<EtaResult | null>;
}

/**
 * Rough, honestly-labeled fallback. Never claims navigation-grade
 * accuracy. Uses straight-line (haversine) distance and either the
 * technician's reported speed (if moving) or a conservative average
 * road speed assumption — always confidence: 'low'.
 */
export class StraightLineEtaProvider implements EtaProvider {
  private readonly fallbackSpeedMps = 11; // ~40 km/h conservative average road speed

  async getEta(from: { lat: number; lng: number }, to: { lat: number; lng: number }, speedMps?: number | null): Promise<EtaResult | null> {
    const distanceMeters = haversineMeters(from.lat, from.lng, to.lat, to.lng);
    if (!Number.isFinite(distanceMeters) || distanceMeters <= 0) return null;

    // A real road route is always longer than straight-line distance
    // — apply a conservative multiplier so this doesn't systematically
    // under-estimate.
    const roadDistanceEstimate = distanceMeters * 1.4;
    const speed = speedMps && speedMps > 1 ? speedMps : this.fallbackSpeedMps;
    const etaMinutes = Math.round(roadDistanceEstimate / speed / 60);

    if (etaMinutes < 1) return { etaMinutes: 1, confidence: 'low', label: 'Estimated arrival' };
    if (etaMinutes > 180) return null; // too far/unreliable to be a useful estimate

    return { etaMinutes, confidence: 'low', label: 'Estimated arrival' };
  }
}

function haversineMeters(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371000;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLon = ((lon2 - lon1) * Math.PI) / 180;
  const a = Math.sin(dLat / 2) ** 2 + Math.cos((lat1 * Math.PI) / 180) * Math.cos((lat2 * Math.PI) / 180) * Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

/**
 * Entry point callers should use. Chooses a real route-provider
 * implementation when ROUTE_PROVIDER_API_KEY is configured (not
 * implemented in this phase — see docs/PHASE-12-REPORT.md), otherwise
 * falls back to the honestly-labeled straight-line estimate.
 */
export function getEtaProvider(): EtaProvider {
  // Future: if (process.env.ROUTE_PROVIDER_API_KEY) return new GoogleDirectionsEtaProvider(...);
  return new StraightLineEtaProvider();
}
