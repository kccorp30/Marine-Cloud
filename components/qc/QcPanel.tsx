'use client';

import { useState, useTransition } from 'react';
import { startQcSubmissionAction, setQcItemResultAction, submitQcForReviewAction, passQcSubmissionAction, failQcSubmissionAction, attachQcEvidenceAction } from '@/lib/qc/actions';
import type { QcSubmissionRow, WorkOrderMediaOption } from '@/lib/qc/data';

const RESULT_LABEL: Record<string, string> = { pending: 'Pending', pass: 'Pass', fail: 'Fail', not_applicable: 'N/A' };
const RESULT_COLOR: Record<string, string> = { pending: 'text-cool-gray', pass: 'text-emerald-400', fail: 'text-red-400', not_applicable: 'text-cool-gray' };

export function QcPanel({
  workOrderId,
  submissions,
  canStart,
  canReview,
  availableMedia,
}: {
  workOrderId: string;
  submissions: QcSubmissionRow[];
  canStart: boolean;
  canReview: boolean;
  availableMedia: WorkOrderMediaOption[];
}) {
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [newItemLabels, setNewItemLabels] = useState<string[]>(['']);
  const [failReasonOpen, setFailReasonOpen] = useState(false);
  const [failReason, setFailReason] = useState('');

  const active = submissions.find((s) => s.status === 'draft' || s.status === 'submitted');
  const history = submissions.filter((s) => s.id !== active?.id);

  if (!active && !canStart) {
    return history.length === 0 ? (
      <p className="text-sm text-cool-gray">No QC activity yet.</p>
    ) : (
      <QcHistory history={history} />
    );
  }

  if (!active) {
    return (
      <div className="space-y-3">
        <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold">Start Quality Control</div>
        <div className="space-y-2">
          {newItemLabels.map((label, i) => (
            <input
              key={i}
              value={label}
              onChange={(e) => setNewItemLabels((prev) => prev.map((l, idx) => (idx === i ? e.target.value : l)))}
              placeholder={`Checklist item ${i + 1}`}
              className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2"
            />
          ))}
        </div>
        <button type="button" onClick={() => setNewItemLabels((prev) => [...prev, ''])} className="text-[10px] font-mono uppercase text-gold">
          + Add item
        </button>
        {error && <p className="text-xs text-red-400">{error}</p>}
        <button
          type="button"
          disabled={pending}
          onClick={() => {
            const items = newItemLabels.filter((l) => l.trim().length > 0).map((label) => ({ label, required: true }));
            if (items.length === 0) {
              setError('Add at least one checklist item.');
              return;
            }
            setError(null);
            startTransition(async () => {
              const res = await startQcSubmissionAction(workOrderId, items);
              if (res?.error) setError(res.error);
            });
          }}
          className="text-sm bg-gold text-navy px-4 py-2 rounded-sm block"
        >
          Start QC
        </button>
        {history.length > 0 && <QcHistory history={history} />}
      </div>
    );
  }

  const allRequiredResolved = active.items.every((i) => !i.required || i.result === 'pass' || i.result === 'not_applicable');
  const noneNotPending = active.items.every((i) => i.result !== 'pending');

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold">Quality Control</div>
        <span className="font-mono text-[9px] uppercase text-cool-gray">{active.status}</span>
      </div>

      <div className="space-y-2">
        {active.items.map((item) => (
          <div key={item.id} className="space-y-1">
            <div className="flex items-center justify-between text-sm">
              <span>
                {item.label} {item.required && <span className="text-cool-gray text-[9px]">*</span>}
              </span>
              {active.status === 'draft' ? (
                <div className="flex gap-1">
                  {(['pass', 'fail', 'not_applicable'] as const).map((r) => (
                    <button
                      key={r}
                      type="button"
                      disabled={pending}
                      onClick={() => {
                        startTransition(async () => {
                          await setQcItemResultAction(item.id, r, null, workOrderId);
                        });
                      }}
                      className={`text-[9px] font-mono uppercase px-2 py-1 rounded-sm border ${item.result === r ? 'border-gold text-gold' : 'border-white/10 text-cool-gray'}`}
                    >
                      {RESULT_LABEL[r]}
                    </button>
                  ))}
                </div>
              ) : (
                <span className={`font-mono text-[9px] uppercase ${RESULT_COLOR[item.result]}`}>{RESULT_LABEL[item.result]}</span>
              )}
            </div>

            {item.evidence.length > 0 && <div className="text-[9px] text-cool-gray">{item.evidence.length} photo(s) attached</div>}

            {active.status === 'draft' && availableMedia.length > 0 && (
              <select
                defaultValue=""
                disabled={pending}
                onChange={(e) => {
                  const mediaAssetId = e.target.value;
                  if (!mediaAssetId) return;
                  startTransition(async () => {
                    await attachQcEvidenceAction(item.id, mediaAssetId, workOrderId);
                  });
                  e.target.value = '';
                }}
                className="text-[9px] bg-white/[0.04] border border-white/10 rounded-sm px-2 py-1 text-cool-gray"
              >
                <option value="">+ Attach existing photo</option>
                {availableMedia
                  .filter((m) => !item.evidence.some((ev) => ev.mediaAssetId === m.id))
                  .map((m) => (
                    <option key={m.id} value={m.id}>
                      {m.category} — {m.storagePath.split('/').pop()}
                    </option>
                  ))}
              </select>
            )}
          </div>
        ))}
      </div>

      {error && <p className="text-xs text-red-400">{error}</p>}

      {active.status === 'draft' && (
        <button
          type="button"
          disabled={pending || !noneNotPending}
          onClick={() => {
            setError(null);
            startTransition(async () => {
              const res = await submitQcForReviewAction(active.id, workOrderId);
              if (res?.error) setError(res.error);
            });
          }}
          className="text-sm bg-gold text-navy px-4 py-2 rounded-sm disabled:opacity-40"
        >
          Submit for Review
        </button>
      )}

      {active.status === 'submitted' && canReview && (
        <div className="space-y-2">
          <div className="flex gap-2">
            <button
              type="button"
              disabled={pending || !allRequiredResolved}
              onClick={() => {
                setError(null);
                startTransition(async () => {
                  const res = await passQcSubmissionAction(active.id, null, workOrderId);
                  if (res?.error) setError(res.error);
                });
              }}
              className="text-sm bg-emerald-500/20 text-emerald-400 border border-emerald-500/40 px-4 py-2 rounded-sm disabled:opacity-40"
            >
              Pass
            </button>
            <button type="button" onClick={() => setFailReasonOpen(true)} className="text-sm bg-red-500/10 text-red-400 border border-red-500/30 px-4 py-2 rounded-sm">
              Fail
            </button>
          </div>
          {!allRequiredResolved && <p className="text-xs text-cool-gray">All required items must be Pass or N/A before this can pass.</p>}
          {failReasonOpen && (
            <div className="space-y-2">
              <input
                value={failReason}
                onChange={(e) => setFailReason(e.target.value)}
                placeholder="Reason for failure"
                className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2"
              />
              <button
                type="button"
                disabled={pending || !failReason.trim()}
                onClick={() => {
                  startTransition(async () => {
                    const res = await failQcSubmissionAction(active.id, failReason, null, workOrderId);
                    if (res?.error) setError(res.error);
                    else setFailReasonOpen(false);
                  });
                }}
                className="text-sm bg-red-500/20 text-red-400 px-4 py-2 rounded-sm"
              >
                Confirm Fail
              </button>
            </div>
          )}
        </div>
      )}

      {active.status === 'submitted' && !canReview && <p className="text-sm text-cool-gray">Awaiting review by an authorized reviewer.</p>}

      {history.length > 0 && <QcHistory history={history} />}
    </div>
  );
}

function QcHistory({ history }: { history: QcSubmissionRow[] }) {
  return (
    <div className="space-y-1 pt-2 border-t border-white/10">
      <div className="font-mono text-[9px] uppercase text-cool-gray">Prior attempts</div>
      {history.map((s) => (
        <div key={s.id} className="text-xs text-cool-gray">
          {new Date(s.createdAt).toLocaleDateString()} — <span className={s.status === 'failed' ? 'text-red-400' : ''}>{s.status}</span>
          {s.failureReason && <span> — {s.failureReason}</span>}
        </div>
      ))}
    </div>
  );
}
