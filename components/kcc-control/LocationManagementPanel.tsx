'use client';

import { useState, useTransition } from 'react';
import { addLocationAction, editLocationAction, setPrimaryLocationAction, deactivateLocationAction } from '@/lib/kcc-control/location-actions';

interface LocationRow {
  id: string;
  name: string;
  address: string | null;
  isPrimary: boolean;
}

export function LocationManagementPanel({ organizationId, locations }: { organizationId: string; locations: LocationRow[] }) {
  const [pending, startTransition] = useTransition();
  const [open, setOpen] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  return (
    <div className="space-y-3">
      {locations.map((l) =>
        editingId === l.id ? (
          <form
            key={l.id}
            action={(formData) => {
              setError(null);
              startTransition(async () => {
                const res = await editLocationAction(formData);
                if (res?.error) {
                  setError(res.error);
                  return;
                }
                setEditingId(null);
              });
            }}
            className="space-y-2 bg-white/[0.03] border border-white/10 rounded-sm p-3"
          >
            <input type="hidden" name="organizationId" value={organizationId} />
            <input type="hidden" name="locationId" value={l.id} />
            <input name="name" defaultValue={l.name} placeholder="Location name" className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2" />
            <input name="address" defaultValue={l.address ?? ''} placeholder="Address" className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2" />
            <div className="flex gap-2">
              <button type="submit" disabled={pending} className="text-[9px] font-mono uppercase bg-gold text-navy px-3 py-1.5 rounded-sm">
                Save
              </button>
              <button type="button" onClick={() => setEditingId(null)} className="text-[9px] font-mono uppercase text-cool-gray px-3 py-1.5">
                Cancel
              </button>
            </div>
          </form>
        ) : (
          <div key={l.id} className="flex items-center justify-between text-sm">
            <div>
              <div>
                {l.name} {l.isPrimary && <span className="text-[9px] font-mono uppercase text-gold ml-1">Primary</span>}
              </div>
              {l.address && <div className="text-xs text-cool-gray">{l.address}</div>}
            </div>
            <div className="flex gap-2 items-center">
              <button type="button" onClick={() => setEditingId(l.id)} className="text-[9px] font-mono uppercase text-cool-gray">
                Edit
              </button>
              {!l.isPrimary && (
                <>
                  <button
                    type="button"
                    disabled={pending}
                    onClick={() => {
                      setError(null);
                      startTransition(async () => {
                        const res = await setPrimaryLocationAction(l.id, organizationId);
                        if (res?.error) setError(res.error);
                      });
                    }}
                    className="text-[9px] font-mono uppercase text-gold"
                  >
                    Set Primary
                  </button>
                  <button
                    type="button"
                    disabled={pending}
                    onClick={() => {
                      setError(null);
                      startTransition(async () => {
                        const res = await deactivateLocationAction(l.id, organizationId);
                        if (res?.error) setError(res.error);
                      });
                    }}
                    className="text-[9px] font-mono uppercase text-red-400"
                  >
                    Deactivate
                  </button>
                </>
              )}
            </div>
          </div>
        )
      )}
      {locations.length === 0 && <p className="text-sm text-cool-gray">No locations on file.</p>}
      {error && <p className="text-xs text-red-400">{error}</p>}

      {!open ? (
        <button type="button" onClick={() => setOpen(true)} className="text-[10px] font-mono uppercase border border-gold-dim text-gold px-3 py-1.5 rounded-sm">
          + Add Location
        </button>
      ) : (
        <form
          action={(formData) => {
            setError(null);
            startTransition(async () => {
              const res = await addLocationAction(formData);
              if (res?.error) {
                setError(res.error);
                return;
              }
              setOpen(false);
            });
          }}
          className="space-y-2"
        >
          <input type="hidden" name="organizationId" value={organizationId} />
          <input name="name" required placeholder="Location name" className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2" />
          <input name="address" placeholder="Address (optional)" className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2" />
          <div className="flex gap-2">
            <button type="submit" disabled={pending} className="text-[10px] font-mono uppercase bg-gold text-navy px-3 py-1.5 rounded-sm">
              Add
            </button>
            <button type="button" onClick={() => setOpen(false)} className="text-[10px] font-mono uppercase text-cool-gray px-3 py-1.5">
              Cancel
            </button>
          </div>
        </form>
      )}
    </div>
  );
}
