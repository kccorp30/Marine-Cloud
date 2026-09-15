'use client';

import { useState, useTransition } from 'react';
import { updateTemplateAction } from '@/lib/communications/actions';
import type { TemplateRow } from '@/lib/communications/data';

export function TemplateEditForm({ template }: { template: TemplateRow }) {
  const [pending, startTransition] = useTransition();
  const [editing, setEditing] = useState(false);
  const [subject, setSubject] = useState(template.subject ?? '');
  const [body, setBody] = useState(template.body);
  const [error, setError] = useState<string | null>(null);

  function save() {
    setError(null);
    const formData = new FormData();
    formData.set('templateId', template.id);
    formData.set('subject', subject);
    formData.set('body', body);
    startTransition(async () => {
      const res = await updateTemplateAction(formData);
      if (res?.error) {
        setError(res.error);
        return;
      }
      setEditing(false);
    });
  }

  function toggleActive() {
    setError(null);
    const formData = new FormData();
    formData.set('templateId', template.id);
    formData.set('isActive', (!template.isActive).toString());
    startTransition(async () => {
      const res = await updateTemplateAction(formData);
      if (res?.error) setError(res.error);
    });
  }

  if (!editing) {
    return (
      <div className="flex gap-3 mt-2">
        <button type="button" onClick={() => setEditing(true)} className="text-[9px] font-mono uppercase text-gold">
          Edit
        </button>
        <button type="button" disabled={pending} onClick={toggleActive} className="text-[9px] font-mono uppercase text-cool-gray">
          {template.isActive ? 'Deactivate' : 'Activate'}
        </button>
        {error && <p className="text-xs text-red-400">{error}</p>}
      </div>
    );
  }

  return (
    <div className="mt-2 space-y-2">
      <input value={subject} onChange={(e) => setSubject(e.target.value)} placeholder="Subject" className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2" />
      <textarea value={body} onChange={(e) => setBody(e.target.value)} rows={4} className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2" />
      {error && <p className="text-xs text-red-400">{error}</p>}
      <div className="flex gap-3">
        <button type="button" disabled={pending} onClick={save} className="text-[9px] font-mono uppercase bg-gold text-navy px-3 py-1.5 rounded-sm">
          Save
        </button>
        <button type="button" onClick={() => setEditing(false)} className="text-[9px] font-mono uppercase text-cool-gray px-3 py-1.5">
          Cancel
        </button>
      </div>
    </div>
  );
}
