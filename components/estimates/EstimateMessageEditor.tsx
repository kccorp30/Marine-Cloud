'use client';

import { useState } from 'react';
import { LuzEstimateCopy } from './LuzEstimateCopy';

export function EstimateMessageEditor({ defaultValue = '' }: { defaultValue?: string }) {
  const [value, setValue] = useState(defaultValue);
  return (
    <div>
      <textarea name="customerMessage" rows={3} value={value} onChange={(event) => setValue(event.target.value)} className="mt-2 w-full rounded-xl border border-white/15 bg-white/5 p-3" />
      <LuzEstimateCopy value={value} onApply={setValue} />
    </div>
  );
}
