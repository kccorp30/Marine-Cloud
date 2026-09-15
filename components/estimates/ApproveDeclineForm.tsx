"use client";
import { UiText } from "@/components/ui/UiText";

import { useState, useTransition } from "react";
import {
  approveEstimateAction,
  declineEstimateAction,
} from "@/lib/estimates/actions";

export function ApproveDeclineForm({
  estimateId,
  versionId,
}: {
  estimateId: string;
  versionId: string;
}) {
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [note, setNote] = useState("");
  const [showDecline, setShowDecline] = useState(false);

  function submit(action: typeof approveEstimateAction) {
    setError(null);
    const formData = new FormData();
    formData.set("estimateId", estimateId);
    formData.set("versionId", versionId);
    formData.set("note", note);
    startTransition(async () => {
      const res = await action(formData);
      if (res?.error) setError(res.error);
    });
  }

  return (
    <div className="space-y-3">
      {error && <p className="text-xs text-red-400">{error}</p>}
      {!showDecline ? (
        <div className="flex gap-3">
          <button
            type="button"
            disabled={pending}
            onClick={() => submit(approveEstimateAction)}
            className="flex-1 text-sm font-mono uppercase tracking-[0.06em] bg-gold text-navy px-4 py-2.5 rounded-sm"
          >
            {pending ? "Submitting…" : "Approve Estimate"}
          </button>
          <button
            type="button"
            disabled={pending}
            onClick={() => setShowDecline(true)}
            className="text-sm font-mono uppercase tracking-[0.06em] border border-white/15 text-cool-gray px-4 py-2.5 rounded-sm"
          >
            {" "}
            <UiText text="Decline" />{" "}
          </button>
        </div>
      ) : (
        <div className="space-y-2">
          <textarea
            value={note}
            onChange={(e) => setNote(e.target.value)}
            placeholder="Optional — let us know why"
            rows={3}
            className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2"
          />
          <div className="flex gap-3">
            <button
              type="button"
              disabled={pending}
              onClick={() => submit(declineEstimateAction)}
              className="text-sm font-mono uppercase tracking-[0.06em] border border-red-500/40 text-red-400 px-4 py-2.5 rounded-sm"
            >
              {pending ? "Submitting…" : "Confirm Decline"}
            </button>
            <button
              type="button"
              onClick={() => setShowDecline(false)}
              className="text-sm font-mono uppercase tracking-[0.06em] text-cool-gray px-4 py-2.5"
            >
              {" "}
              <UiText text="Cancel" />{" "}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
