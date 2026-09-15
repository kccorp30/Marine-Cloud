'use client';

import { useState, useTransition } from 'react';
import Link from 'next/link';
import {
  acceptKccAssistanceAction,
  startKccAssistanceAction,
  resolveKccAssistanceAction,
  escalateKccAssistanceAction,
} from '@/lib/kcc-assistance/actions';
import type { AssistanceRequestDTO } from '@/lib/kcc-assistance/data';

const URGENCY_COLOR: Record<string, string> = {
  normal: 'text-cool-gray',
  high: 'text-gold',
  critical: 'text-red-400',
};

const STATUS_LABEL: Record<string, string> = {
  open: 'Open',
  accepted: 'Accepted',
  started: 'In Progress',
  resolved: 'Resolved',
  escalated: 'Escalated',
};

export function AssistanceRequestCard({ request, isAdmin }: { request: AssistanceRequestDTO; isAdmin: boolean }) {
  const [pending, startTransition] = useTransition();
  const [showResolve, setShowResolve] = useState(false);
  const [showEscalate, setShowEscalate] = useState(false);
  const [notes, setNotes] = useState('');
  const [success, setSuccess] = useState(false);
  const [expanded, setExpanded] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function run(action: () => Promise<{ error?: string }>) {
    setError(null); setSuccess(false);
    startTransition(async () => {
      try { const res = await action();
      if (res?.error) setError(res.error);
      else {setSuccess(true);setShowResolve(false);setShowEscalate(false);setNotes('');}
      } catch {setError('Could not save. Try again.');}
    });
  }

  return (
    <div className="premium-card rounded-2xl p-5 space-y-3">
      <div className="flex items-center justify-between">
        <span className={`font-mono text-[9px] uppercase ${URGENCY_COLOR[request.urgency] ?? 'text-cool-gray'}`}>{request.urgency} · {request.category}</span>
        <span className="font-mono text-[9px] uppercase text-cool-gray">{STATUS_LABEL[request.status]}</span>
      </div>
      {request.technicianAvatar && <img src={request.technicianAvatar} alt="" className="w-16 h-16 rounded-2xl object-cover"/>}
      <button type="button" aria-expanded={expanded} onClick={()=>setExpanded(!expanded)} className="block text-left text-base font-semibold w-full">
        {request.requestingTechnicianName ?? 'Technician'} — {request.vesselName ?? 'vessel'} <span className="text-gold">{expanded?'−':'+'}</span>
      </button>
      {expanded && <div className="space-y-3">
      <Link href={`/work-orders/${request.workOrderId}`} className="text-[10px] font-mono uppercase text-gold">
        View Work Order →
      </Link>
      {request.currentJobStatus && <p className="text-xs text-cool-gray">Job status at request: {request.currentJobStatus}</p>}
      {request.notes && <p className="text-sm">{request.notes}</p>}
      {request.acceptedByName && <p className="text-xs text-cool-gray">Accepted by {request.acceptedByName}</p>}
      {!isAdmin && request.status !== 'open' && (
        <p className="text-xs text-emerald-400 font-semibold">KCC accepted your assistance request</p>
      )}
      {request.resolutionNotes && <p className="text-xs text-cool-gray">Notes: {request.resolutionNotes}</p>}
      <p className="text-[10px] text-cool-gray">{new Date(request.createdAt).toLocaleString()}</p>

      {isAdmin && request.technicianPhone && <div className="flex flex-wrap gap-3"><a className="command-action" href={`tel:${request.technicianPhone.replace(/[^+0-9]/g,'')}`}>Call technician</a>{/^\+[1-9]\d{7,14}$/.test(request.technicianPhone.replace(/[ ()-]/g,'')) && <a className="command-action" target="_blank" rel="noopener noreferrer" href={`https://wa.me/${request.technicianPhone.replace(/\D/g,'')}`}>WhatsApp / video call ↗</a>}</div>}
      </div>}
      {success && <p role="status" className="text-emerald-300 text-sm">Saved successfully.</p>}
      {pending && <p role="status" className="text-sm">Saving…</p>}
      {error && <p className="text-xs text-red-400">{error}</p>}

      {isAdmin && request.status === 'open' && (
        <div className="flex gap-2 pt-2">
          <button
            type="button"
            disabled={pending}
            onClick={() => run(() => acceptKccAssistanceAction(request.id))}
            className="text-[10px] font-mono uppercase bg-gold text-navy px-3 py-1.5 rounded-sm"
          >
            Accept
          </button>
          <button type="button" onClick={() => setShowEscalate(true)} className="text-[10px] font-mono uppercase border border-red-500/30 text-red-400 px-3 py-1.5 rounded-sm">
            Escalate
          </button>
        </div>
      )}

      {isAdmin && request.status === 'accepted' && (
        <div className="flex gap-2 pt-2">
          <button
            type="button"
            disabled={pending}
            onClick={() => run(() => startKccAssistanceAction(request.id))}
            className="text-[10px] font-mono uppercase bg-gold text-navy px-3 py-1.5 rounded-sm"
          >
            Start
          </button>
          <button type="button" onClick={() => setShowResolve(true)} className="text-[10px] font-mono uppercase border border-gold-dim text-gold px-3 py-1.5 rounded-sm">
            Resolve
          </button>
          <button type="button" onClick={() => setShowEscalate(true)} className="text-[10px] font-mono uppercase border border-red-500/30 text-red-400 px-3 py-1.5 rounded-sm">
            Escalate
          </button>
        </div>
      )}

      {isAdmin && request.status === 'started' && (
        <div className="flex gap-2 pt-2">
          <button type="button" onClick={() => setShowResolve(true)} className="text-[10px] font-mono uppercase bg-gold text-navy px-3 py-1.5 rounded-sm">
            Resolve
          </button>
          <button type="button" onClick={() => setShowEscalate(true)} className="text-[10px] font-mono uppercase border border-red-500/30 text-red-400 px-3 py-1.5 rounded-sm">
            Escalate
          </button>
        </div>
      )}

      {(showResolve || showEscalate) && (
        <div className="pt-2 space-y-2">
          <textarea
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            rows={2}
            placeholder="Notes (optional)"
            className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2"
          />
          <div className="flex gap-2">
            <button
              type="button"
              disabled={pending}
              onClick={() => {
                const formData = new FormData();
                formData.set('requestId', request.id);
                formData.set('resolutionNotes', notes);
                run(() => (showResolve ? resolveKccAssistanceAction(formData) : escalateKccAssistanceAction(formData)));

              }}
              className="text-[10px] font-mono uppercase bg-gold text-navy px-3 py-1.5 rounded-sm"
            >
              Confirm {showResolve ? 'Resolve' : 'Escalate'}
            </button>
            <button type="button" onClick={() => { setShowResolve(false); setShowEscalate(false); }} className="text-[10px] font-mono uppercase text-cool-gray px-3 py-1.5">
              Cancel
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
