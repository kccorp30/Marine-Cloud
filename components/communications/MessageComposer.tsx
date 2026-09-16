'use client';

import { useState, useTransition } from 'react';
import { translateDraftAction, sendMessageAction } from '@/lib/communications/actions';

const MODES: { value: string; label: string }[] = [
  { value: 'translate_only', label: 'Translate Only' },
  { value: 'professional', label: 'Professional' },
  { value: 'friendly', label: 'Friendly' },
  { value: 'concise', label: 'Concise' },
  { value: 'sales', label: 'Sales' },
  { value: 'technical', label: 'Technical' },
];

export function MessageComposer({ conversationId }: { conversationId: string }) {
  const [pending, startTransition] = useTransition();
  const [subject, setSubject] = useState('');
  const [body, setBody] = useState('');
  const [translated, setTranslated] = useState<string | null>(null);
  const [tokensBlocked, setTokensBlocked] = useState(false);
  const [tokenIssue, setTokenIssue] = useState<string | null>(null);
  const [targetLanguage, setTargetLanguage] = useState('en');
  const [mode, setMode] = useState('professional');
  const [error, setError] = useState<string | null>(null);
  const [sent, setSent] = useState(false);

  function handleTranslate() {
    setError(null);
    setTokenIssue(null);
    setTokensBlocked(false);
    const formData = new FormData();
    formData.set('sourceText', body);
    formData.set('targetLanguage', targetLanguage);
    formData.set('mode', mode);
    startTransition(async () => {
      const res = await translateDraftAction(formData);
      if (res.error) {
        setError(res.error);
        return;
      }
      if (res.result) {
        setTranslated(res.result.translatedText);
        if (!res.result.tokensPreserved) {
          setTokensBlocked(true);
          const parts: string[] = [];
          if (res.result.missingTokens.length > 0) parts.push(`missing: ${res.result.missingTokens.join(', ')}`);
          if (res.result.addedTokens.length > 0) parts.push(`unexpected addition: ${res.result.addedTokens.join(', ')}`);
          setTokenIssue(`The translation changed a number or identifier (${parts.join('; ')}). Fix it manually before sending.`);
        }
      }
    });
  }

  function handleSend(useTranslated: boolean) {
    setError(null);
    if (useTranslated && tokensBlocked) {
      setError('Cannot send: review the flagged numbers first.');
      return;
    }
    const formData = new FormData();
    formData.set('conversationId', conversationId);
    formData.set('channel', 'email');
    formData.set('subject', subject);
    formData.set('bodyOriginal', body);
    if (useTranslated && translated) {
      formData.set('bodyRendered', translated);
      formData.set('languageOriginal', targetLanguage === 'en' ? 'es' : 'en');
      formData.set('languageRendered', targetLanguage);
    }
    startTransition(async () => {
      const res = await sendMessageAction(formData);
      if (res?.error) {
        setError(res.error);
        return;
      }
      setSent(true);
      setSubject('');
      setBody('');
      setTranslated(null);
    });
  }

  if (sent) {
    return <p className="text-sm text-emerald-400">Message sent.</p>;
  }

  return (
    <div className="space-y-3">
      <input
        value={subject}
        onChange={(e) => setSubject(e.target.value)}
        placeholder="Subject"
        className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2"
      />
      <textarea
        value={body}
        onChange={(e) => setBody(e.target.value)}
        rows={5}
        placeholder="Write your message…"
        className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2"
      />

      <div className="flex gap-3 flex-wrap items-end">
        <div>
          <label className="text-[9px] font-mono uppercase text-cool-gray block mb-1">Translate to</label>
          <select value={targetLanguage} onChange={(e) => setTargetLanguage(e.target.value)} className="text-xs bg-white/[0.04] border border-white/10 rounded-sm px-2 py-1.5">
            <option value="en" className="bg-navy">English</option>
            <option value="es" className="bg-navy">Spanish</option>
          </select>
        </div>
        <div>
          <label className="text-[9px] font-mono uppercase text-cool-gray block mb-1">Mode</label>
          <select value={mode} onChange={(e) => setMode(e.target.value)} className="text-xs bg-white/[0.04] border border-white/10 rounded-sm px-2 py-1.5">
            {MODES.map((m) => (
              <option key={m.value} value={m.value} className="bg-navy">
                {m.label}
              </option>
            ))}
          </select>
        </div>
        <button
          type="button"
          disabled={pending || !body.trim()}
          onClick={handleTranslate}
          className="text-[10px] font-mono uppercase border border-gold-dim text-gold px-3 py-1.5 rounded-sm"
        >
          {pending ? 'Working…' : 'Translate / Improve'}
        </button>
      </div>

      {error && <p className="text-xs text-red-400">{error}</p>}

      {translated && (
        <div className={`border rounded-sm p-3 space-y-2 ${tokensBlocked ? 'border-red-500/40' : 'border-gold-dim'}`}>
          <div className="font-mono text-[9px] uppercase tracking-[0.08em] text-gold">Preview — edit before sending</div>
          <textarea
            value={translated}
            onChange={(e) => {
              setTranslated(e.target.value);
              setTokensBlocked(false);
              setTokenIssue(null);
            }}
            rows={5}
            className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2"
          />
          {tokenIssue && <p className="text-xs text-red-400">{tokenIssue}</p>}
          <button
            type="button"
            disabled={pending || tokensBlocked}
            onClick={() => handleSend(true)}
            className="text-[10px] font-mono uppercase bg-gold text-navy px-3 py-1.5 rounded-sm disabled:opacity-40 disabled:cursor-not-allowed"
          >
            {tokensBlocked ? 'Fix flagged numbers to send' : 'Use Translation & Send'}
          </button>
        </div>
      )}

      <button
        type="button"
        disabled={pending || !body.trim()}
        onClick={() => handleSend(false)}
        className="text-[10px] font-mono uppercase border border-white/15 text-cool-gray px-3 py-1.5 rounded-sm"
      >
        Send As Written
      </button>
    </div>
  );
}
