'use client';

import { useState } from 'react';
import { rescheduleAppointment } from '@/lib/work-orders/actions';

export function RescheduleControl({ appointmentId, currentStart }: { appointmentId: string; currentStart: string }) {
  const [open, setOpen] = useState(false);

  if (!open) {
    return (
      <button type="button" onClick={() => setOpen(true)} className="text-[10px] font-mono uppercase text-gold hover:underline">
        Reschedule
      </button>
    );
  }

  return (
    <form action={rescheduleAppointment} className="flex items-center gap-2">
      <input type="hidden" name="appointmentId" value={appointmentId} />
      <input
        name="scheduledStart"
        type="datetime-local"
        required
        defaultValue={new Date(currentStart).toISOString().slice(0, 16)}
        className="text-[11px] bg-white/[0.04] border border-white/10 px-2 py-1 rounded-sm"
      />
      <button type="submit" className="text-[10px] font-mono uppercase text-gold hover:underline">
        Save
      </button>
      <button type="button" onClick={() => setOpen(false)} className="text-[10px] font-mono uppercase text-cool-gray hover:underline">
        Cancel
      </button>
    </form>
  );
}
