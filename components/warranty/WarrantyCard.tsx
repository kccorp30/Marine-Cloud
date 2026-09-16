'use client';

import { useState, useTransition } from 'react';
import { submitWarrantyClaimAction, reviewWarrantyClaimAction, createCorrectiveWorkOrderAction, markClaimUnderReviewAction, resolveClaimAction, cancelClaimAction } from '@/lib/warranty/actions';
import { getEffectiveWarrantyStatus } from '@/lib/warranty/effective-status';
import { formatCalendarDate } from '@/lib/warranty/format-calendar-date';
import type { WarrantyRow } from '@/lib/warranty/data';

const STATUS_LABEL: Record<string, string> = { draft: 'Draft', active: 'Active', expired: 'Expired', voided: 'Voided' };
const STATUS_COLOR: Record<string, string> = { draft: 'text-cool-gray', active: 'text-emerald-400', expired: 'text-cool-gray', voided: 'text-red-400' };

export function WarrantyCard({ warranty, isCustomer, canReview }: { warranty: WarrantyRow; isCustomer: boolean; canReview: boolean }) {
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [claiming, setClaiming] = useState(false);
  const [claimReason, setClaimReason] = useState('');
  const [claimDescription, setClaimDescription] = useState('');

  // Nunca el status crudo — siempre el estado efectivo derivado de la
  // fecha real, sin depender de un cron que no existe.
  const effectiveStatus = getEffectiveWarrantyStatus(warranty.status, warranty.endsAt);
  const isEligibleForClaim = effectiveStatus === 'active';

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <span className={`font-mono text-[10px] uppercase ${STATUS_COLOR[effectiveStatus]}`}>{STATUS_LABEL[effectiveStatus]} Warranty</span>
      </div>
      <div className="text-sm">
        <div>{warranty.coverageType.charAt(0).toUpperCase() + warranty.coverageType.slice(1)} coverage</div>
        {warranty.coverageNotes && <div className="text-xs text-cool-gray">{warranty.coverageNotes}</div>}
        {warranty.startsAt && warranty.endsAt && (
          <div className="text-xs text-cool-gray">
            {formatCalendarDate(warranty.startsAt)} – {formatCalendarDate(warranty.endsAt)}
          </div>
        )}
      </div>

      {isCustomer && isEligibleForClaim && !claiming && (
        <button type="button" onClick={() => setClaiming(true)} className="text-[10px] font-mono uppercase border border-gold-dim text-gold px-3 py-1.5 rounded-sm">
          Submit a Claim
        </button>
      )}

      {isCustomer && claiming && (
        <div className="space-y-2">
          <input
            value={claimReason}
            onChange={(e) => setClaimReason(e.target.value)}
            placeholder="What's the issue?"
            className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2"
          />
          <textarea
            value={claimDescription}
            onChange={(e) => setClaimDescription(e.target.value)}
            placeholder="Describe the issue (optional)"
            rows={3}
            className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2"
          />
          {error && <p className="text-xs text-red-400">{error}</p>}
          <div className="flex gap-2">
            <button
              type="button"
              disabled={pending || !claimReason.trim()}
              onClick={() => {
                setError(null);
                startTransition(async () => {
                  const res = await submitWarrantyClaimAction(warranty.id, claimReason, claimDescription || null, warranty.workOrderId);
                  if (res?.error) {
                    setError(res.error);
                    return;
                  }
                  setClaiming(false);
                });
              }}
              className="text-sm bg-gold text-navy px-4 py-2 rounded-sm"
            >
              Submit Claim
            </button>
            <button type="button" onClick={() => setClaiming(false)} className="text-sm text-cool-gray px-4 py-2">
              Cancel
            </button>
          </div>
        </div>
      )}

      {warranty.claims.length > 0 && (
        <div className="space-y-2 pt-2 border-t border-white/10">
          <div className="font-mono text-[9px] uppercase text-cool-gray">Claims</div>
          {warranty.claims.map((claim) => (
            <div key={claim.id} className="text-sm space-y-1">
              <div className="flex items-center justify-between">
                <span>{claim.reason}</span>
                <span className="font-mono text-[9px] uppercase text-cool-gray">{claim.status.replace('_', ' ')}</span>
              </div>
              {claim.decisionReason && <div className="text-xs text-cool-gray">{claim.decisionReason}</div>}

              {canReview && claim.status === 'submitted' && (
                <div className="flex gap-2">
                  <button
                    type="button"
                    disabled={pending}
                    onClick={() => {
                      setError(null);
                      startTransition(async () => {
                        const res = await markClaimUnderReviewAction(claim.id, warranty.workOrderId);
                        if (res?.error) setError(res.error);
                      });
                    }}
                    className="text-[9px] font-mono uppercase border border-gold-dim text-gold px-2 py-1 rounded-sm"
                  >
                    Start Review
                  </button>
                </div>
              )}

              {canReview && claim.status === 'under_review' && (
                <div className="flex gap-2">
                  <button
                    type="button"
                    disabled={pending}
                    onClick={() => {
                      setError(null);
                      startTransition(async () => {
                        const res = await reviewWarrantyClaimAction(claim.id, 'approved', null, warranty.workOrderId);
                        if (res?.error) setError(res.error);
                      });
                    }}
                    className="text-[9px] font-mono uppercase bg-emerald-500/20 text-emerald-400 px-2 py-1 rounded-sm"
                  >
                    Approve
                  </button>
                  <button
                    type="button"
                    disabled={pending}
                    onClick={() => {
                      setError(null);
                      startTransition(async () => {
                        const res = await reviewWarrantyClaimAction(claim.id, 'rejected', null, warranty.workOrderId);
                        if (res?.error) setError(res.error);
                      });
                    }}
                    className="text-[9px] font-mono uppercase bg-red-500/10 text-red-400 px-2 py-1 rounded-sm"
                  >
                    Reject
                  </button>
                </div>
              )}

              {canReview && claim.status === 'approved' && !claim.claimWorkOrderId && (
                <button
                  type="button"
                  disabled={pending}
                  onClick={() => {
                    setError(null);
                    startTransition(async () => {
                      const res = await createCorrectiveWorkOrderAction(claim.id, warranty.workOrderId);
                      if (res?.error) setError(res.error);
                    });
                  }}
                  className="text-[9px] font-mono uppercase text-gold"
                >
                  Create Corrective Work Order
                </button>
              )}

              {canReview && claim.status === 'in_progress' && (
                <button
                  type="button"
                  disabled={pending}
                  onClick={() => {
                    setError(null);
                    startTransition(async () => {
                      const res = await resolveClaimAction(claim.id, null, warranty.workOrderId);
                      if (res?.error) setError(res.error);
                    });
                  }}
                  className="text-[9px] font-mono uppercase bg-gold text-navy px-2 py-1 rounded-sm"
                >
                  Resolve Claim
                </button>
              )}

              {(claim.status === 'submitted' || claim.status === 'under_review') && (canReview || isCustomer) && (
                <button
                  type="button"
                  disabled={pending}
                  onClick={() => {
                    setError(null);
                    startTransition(async () => {
                      const res = await cancelClaimAction(claim.id, null, warranty.workOrderId);
                      if (res?.error) setError(res.error);
                    });
                  }}
                  className="text-[9px] font-mono uppercase text-cool-gray"
                >
                  Cancel Claim
                </button>
              )}
            </div>
          ))}
        {error && <p className="text-xs text-red-400">{error}</p>}
        </div>
      )}
    </div>
  );
}
