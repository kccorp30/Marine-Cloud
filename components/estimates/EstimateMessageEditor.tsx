'use client';

import { useState } from 'react';
import { LuzEstimateCopy } from './LuzEstimateCopy';

export function EstimateMessageEditor({
  defaultValue = '',
  customerName,
  vesselName,
  estimateNumber,
  services = [],
  language = 'en',
}: {
  defaultValue?: string;
  customerName?: string | null;
  vesselName?: string | null;
  estimateNumber?: string | null;
  services?: string[];
  language?: 'en' | 'es';
}) {
  const [value, setValue] = useState(defaultValue);
  return (
    <div>
      <textarea
        name="customerMessage"
        rows={4}
        value={value}
        onChange={(event) => setValue(event.target.value)}
        placeholder={language === 'es' ? 'Escribe una nota o deja que Luz prepare una usando el estimado…' : 'Write a note or let Luz prepare one from this estimate…'}
        className="mt-2 w-full rounded-xl border border-white/15 bg-white/5 p-3 leading-relaxed"
      />
      <LuzEstimateCopy
        value={value}
        onApply={setValue}
        context={{ customerName, vesselName, estimateNumber, services, language }}
      />
    </div>
  );
}
