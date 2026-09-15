'use client';

import { Suspense, useMemo, useState } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';
import { AuthExperienceShell } from '@/components/auth/AuthExperienceShell';

function ResetPasswordContent() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const nextPath = searchParams.get('next');
  const isWelcome = searchParams.get('welcome') === '1';
  const [password, setPassword] = useState('');
  const [confirm, setConfirm] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [done, setDone] = useState(false);

  const strength = useMemo(() => {
    let score = 0;
    if (password.length >= 8) score += 1;
    if (/[A-Z]/.test(password) && /[a-z]/.test(password)) score += 1;
    if (/\d/.test(password)) score += 1;
    if (/[^A-Za-z0-9]/.test(password)) score += 1;
    return score;
  }, [password]);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (password !== confirm) {
      setError('Passwords do not match.');
      return;
    }
    if (password.length < 8) {
      setError('Use at least 8 characters.');
      return;
    }
    setLoading(true);
    setError(null);

    const supabase = createClient();
    const { error: updateError } = await supabase.auth.updateUser({ password });
    if (updateError) {
      setLoading(false);
      setError(updateError.message);
      return;
    }

    const credentialState = await fetch('/api/auth/credential-state', { method: 'POST' });
    setLoading(false);
    if (!credentialState.ok) {
      setError('Your password was updated, but account activation could not be finalized. Please sign in again.');
      return;
    }

    setDone(true);
    setTimeout(() => {
      router.push(nextPath && nextPath.startsWith('/') && !nextPath.startsWith('//') ? nextPath : '/');
      router.refresh();
    }, 900);
  }

  return (
    <AuthExperienceShell
      eyebrow={isWelcome ? 'First-time activation' : 'Credential security'}
      title={done ? 'Access secured' : isWelcome ? 'Create your password' : 'Choose a new password'}
      description={done
        ? 'Your account is ready. We’re opening the workspace that belongs to your role.'
        : isWelcome
          ? 'This is the only time you’ll need the invitation link. From now on, use your email and password to enter Marine Cloud.'
          : 'Create a new password. Your existing workspaces, roles and data stay exactly where they are.'}
      steps={isWelcome ? [
        { label: 'Invitation', state: 'done' },
        { label: 'Password', state: done ? 'done' : 'active' },
        { label: 'Profile', state: done ? 'active' : 'upcoming' },
      ] : undefined}
    >
      {done ? (
        <div className="py-5 text-center animate-fade-up">
          <div className="mx-auto mb-4 grid h-16 w-16 place-items-center rounded-full border border-emerald-300/25 bg-emerald-300/[.08] text-2xl text-emerald-300 shadow-[0_0_35px_-12px_rgba(110,231,183,.7)]">✓</div>
          <p className="text-sm text-marine-white">Password saved</p>
          <p className="mt-2 text-xs text-cool-gray">Preparing your workspace…</p>
        </div>
      ) : (
        <form onSubmit={handleSubmit} className="space-y-5">
          <div className="auth-field-group">
            <label htmlFor="new-password" className="auth-field-label">New password</label>
            <div className="auth-input-shell">
              <span className="auth-input-icon">◆</span>
              <input id="new-password" type={showPassword ? 'text' : 'password'} required value={password} onChange={(e) => setPassword(e.target.value)} autoComplete="new-password" className="auth-input pr-20" placeholder="8+ characters" />
              <button type="button" className="auth-reveal-button" onClick={() => setShowPassword((v) => !v)}>{showPassword ? 'Hide' : 'Show'}</button>
            </div>
            <div className="grid grid-cols-4 gap-1.5 mt-1" aria-label="Password strength">
              {[0,1,2,3].map((index) => <span key={index} className={`h-1 rounded-full transition-all duration-300 ${index < strength ? 'bg-gold shadow-[0_0_10px_rgba(228,199,122,.35)]' : 'bg-white/10'}`} />)}
            </div>
          </div>

          <div className="auth-field-group">
            <label htmlFor="confirm-password" className="auth-field-label">Confirm password</label>
            <div className="auth-input-shell">
              <span className="auth-input-icon">✓</span>
              <input id="confirm-password" type={showPassword ? 'text' : 'password'} required value={confirm} onChange={(e) => setConfirm(e.target.value)} autoComplete="new-password" className="auth-input" placeholder="Repeat your password" />
            </div>
          </div>

          {error && <div className="auth-alert" role="alert"><span>!</span><p>{error}</p></div>}
          <button type="submit" disabled={loading} className="auth-primary-button">
            <span>{loading ? 'Securing account…' : isWelcome ? 'Create password & continue' : 'Update password'}</span>
            <span className="auth-button-arrow">→</span>
          </button>
        </form>
      )}
    </AuthExperienceShell>
  );
}

function ResetPasswordFallback() {
  return <AuthExperienceShell eyebrow="Secure access" title="Preparing your account" description="Verifying your secure session…"><div className="skeleton h-14 rounded-2xl" /></AuthExperienceShell>;
}

export default function ResetPasswordPage() {
  return <Suspense fallback={<ResetPasswordFallback />}><ResetPasswordContent /></Suspense>;
}
