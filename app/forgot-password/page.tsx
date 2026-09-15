'use client';

import { useState } from 'react';
import { AuthExperienceShell } from '@/components/auth/AuthExperienceShell';

export default function ForgotPasswordPage() {
  const [email, setEmail] = useState('');
  const [sent, setSent] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError(null);

    const response = await fetch('/api/auth/recovery', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email }),
    });
    const result = await response.json().catch(() => ({}));

    setLoading(false);
    if (!response.ok) {
      setError(result.error || 'Something went wrong. Please try again.');
      return;
    }
    setSent(true);
  }

  return (
    <AuthExperienceShell
      eyebrow="Account recovery"
      title={sent ? 'Check your inbox' : 'Recover access'}
      description={sent
        ? 'If this email belongs to a Marine Cloud account, a secure reset link is on its way.'
        : 'Enter the email you use for Marine Cloud. We’ll send a secure link to create a new password.'}
    >
      {sent ? (
        <div className="space-y-5 animate-fade-up">
          <div className="rounded-2xl border border-emerald-300/15 bg-emerald-300/[.06] p-5">
            <div className="flex items-center gap-3 text-emerald-200 text-sm">
              <span className="grid h-9 w-9 place-items-center rounded-full bg-emerald-300/10">✓</span>
              <div>
                <p className="font-medium">Recovery link requested</p>
                <p className="text-xs text-emerald-100/60 mt-1">{email}</p>
              </div>
            </div>
          </div>
          <a href="/login" className="auth-primary-button"><span>Back to sign in</span><span>→</span></a>
        </div>
      ) : (
        <form onSubmit={handleSubmit} className="space-y-5">
          <div className="auth-field-group">
            <label htmlFor="recovery-email" className="auth-field-label">Email</label>
            <div className="auth-input-shell">
              <span className="auth-input-icon" aria-hidden="true">@</span>
              <input
                id="recovery-email"
                type="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                autoComplete="email"
                placeholder="name@company.com"
                className="auth-input"
              />
            </div>
          </div>
          {error && <div className="auth-alert" role="alert"><span>!</span><p>{error}</p></div>}
          <button type="submit" disabled={loading} className="auth-primary-button">
            <span>{loading ? 'Sending secure link…' : 'Send reset link'}</span><span className="auth-button-arrow">→</span>
          </button>
          <a href="/login" className="block text-center auth-text-link">← Back to sign in</a>
        </form>
      )}
    </AuthExperienceShell>
  );
}
