'use client';

import { useState } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';
import type { Dictionary } from '@/lib/i18n/dictionary';

export function LoginForm({ t }: { t: Dictionary }) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const nextPath = searchParams.get('next');
  const authError = searchParams.get('auth_error');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [error, setError] = useState<string | null>(
    authError === 'invalid_or_expired_link' ? 'That secure link has expired. Sign in with your email and password, or reset your password.' : null,
  );
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError(null);

    const supabase = createClient();
    const { error: signInError } = await supabase.auth.signInWithPassword({ email: email.trim(), password });

    if (signInError) {
      setLoading(false);
      setError(t.common.invalidCredentials);
      return;
    }

    // A successful password authentication is already authoritative proof
    // that this account has a working password. Persist the convenience marker
    // best-effort, but NEVER sign a valid user back out if that secondary write
    // fails (for example during a rolling database migration).
    try {
      await fetch('/api/auth/credential-state', { method: 'POST' });
    } catch {
      // Non-blocking by design.
    }

    setLoading(false);
    const destination = nextPath && nextPath.startsWith('/') && !nextPath.startsWith('//') ? nextPath : '/';
    router.push(destination);
    router.refresh();
  }

  return (
    <form onSubmit={handleSubmit} className="flex flex-col gap-5">
      <div className="auth-field-group">
        <label htmlFor="login-email" className="auth-field-label">{t.common.email}</label>
        <div className="auth-input-shell">
          <span className="auth-input-icon" aria-hidden="true">@</span>
          <input
            id="login-email"
            type="email"
            required
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            autoComplete="username"
            placeholder="name@company.com"
            className="auth-input"
          />
        </div>
      </div>

      <div className="auth-field-group">
        <div className="flex items-center justify-between gap-3">
          <label htmlFor="login-password" className="auth-field-label">{t.common.password}</label>
          <a href="/forgot-password" className="auth-text-link">{t.common.forgotPassword}</a>
        </div>
        <div className="auth-input-shell">
          <span className="auth-input-icon" aria-hidden="true">◆</span>
          <input
            id="login-password"
            type={showPassword ? 'text' : 'password'}
            required
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            autoComplete="current-password"
            placeholder="••••••••"
            className="auth-input pr-20"
          />
          <button
            type="button"
            onClick={() => setShowPassword((value) => !value)}
            className="auth-reveal-button"
            aria-label={showPassword ? 'Hide password' : 'Show password'}
          >
            {showPassword ? 'Hide' : 'Show'}
          </button>
        </div>
      </div>

      {error && <div className="auth-alert" role="alert"><span>!</span><p>{error}</p></div>}

      <button type="submit" disabled={loading} className="auth-primary-button">
        <span>{loading ? t.common.signingIn : t.common.signIn}</span>
        <span className="auth-button-arrow" aria-hidden="true">→</span>
      </button>

      <div className="auth-security-note">
        <span className="auth-security-dot" />
        <span>Email + password access for every Marine Cloud workspace.</span>
      </div>
    </form>
  );
}
