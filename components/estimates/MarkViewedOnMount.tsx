'use client';

import { useEffect, useRef } from 'react';
import { markViewedAction } from '@/lib/estimates/actions';

export function MarkViewedOnMount({ versionId }: { versionId: string }) {
  const fired = useRef(false);
  useEffect(() => {
    if (fired.current) return;
    fired.current = true;
    markViewedAction(versionId);
  }, [versionId]);
  return null;
}
