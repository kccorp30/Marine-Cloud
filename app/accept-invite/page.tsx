import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';
import { getLocale } from '@/lib/i18n/server';
import { dictionary } from '@/lib/i18n/dictionary';
import { AuthExperienceShell } from '@/components/auth/AuthExperienceShell';
import { roleHome } from '@/lib/auth/role-home';

export default async function AcceptInvitePage({
  searchParams,
}: {
  searchParams: Promise<{ token?: string; setup?: string }>;
}) {
  const { token, setup } = await searchParams;
  const locale = await getLocale();
  const t = dictionary[locale];

  if (!token) {
    return (
      <InviteState
        title="Invitation link missing"
        description="Open the secure link from your invitation email. If it has expired, ask the company to resend it."
        tone="error"
      >
        <a href="/login" className="auth-primary-button"><span>{t.common.signIn}</span><span>→</span></a>
      </InviteState>
    );
  }

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect(`/login?next=${encodeURIComponent(`/accept-invite?token=${encodeURIComponent(token)}${setup === '1' ? '&setup=1' : ''}`)}`);
  }

  const { data: organizationId, error } = await supabase.rpc('accept_invitation', {
    p_token: token,
  });

  if (error || !organizationId) {
    return (
      <InviteState
        title="We couldn’t activate this invitation"
        description={error?.message || 'This invitation is invalid, expired or no longer available.'}
        tone="error"
      >
        <div className="space-y-3">
          <a href="/login" className="auth-primary-button"><span>Return to sign in</span><span>→</span></a>
          <p className="text-center text-[10px] text-cool-gray">A company administrator can resend a fresh invitation without creating another account.</p>
        </div>
      </InviteState>
    );
  }

  const { data: membership } = await supabase
    .from('organization_memberships')
    .select('role')
    .eq('profile_id', user.id)
    .eq('organization_id', organizationId)
    .maybeSingle();

  if (membership?.role === 'customer') {
    const linked = await supabase.rpc('link_customer_account', {
      p_organization_id: organizationId,
    });
    if (linked.error) {
      return (
        <InviteState
          title={locale === 'es' ? 'Acceso activado' : 'Access activated'}
          description={locale === 'es'
            ? 'Tu cuenta ya está segura. La compañía debe terminar de vincular tu registro de cliente antes de mostrar tu embarcación y servicios.'
            : 'Your account is secure. The company needs to finish linking your customer record before your vessel and services appear.'}
          tone="info"
        >
          <a
            className="auth-primary-button"
            href={setup === '1'
              ? `/reset-password?welcome=1&next=${encodeURIComponent(`/welcome?organization=${encodeURIComponent(organizationId)}`)}`
              : `/welcome?organization=${encodeURIComponent(organizationId)}`}
          >
            <span>{locale === 'es' ? 'Continuar configuración' : 'Continue setup'}</span><span>→</span>
          </a>
        </InviteState>
      );
    }
  }

  const destination = roleHome(membership?.role);

  if (setup === '1') {
    redirect(`/reset-password?welcome=1&next=${encodeURIComponent(`/welcome?organization=${encodeURIComponent(organizationId)}&next=${encodeURIComponent(destination)}`)}`);
  }

  redirect(`/welcome?organization=${encodeURIComponent(organizationId)}&next=${encodeURIComponent(destination)}`);
}

function InviteState({
  title,
  description,
  children,
  tone,
}: {
  title: string;
  description: string;
  children: React.ReactNode;
  tone: 'error' | 'info';
}) {
  return (
    <AuthExperienceShell eyebrow="Workspace invitation" title={title} description={description}>
      <div className="space-y-5">
        <div className={`rounded-2xl border p-4 text-xs ${tone === 'error' ? 'border-red-300/15 bg-red-300/[.05] text-red-200/80' : 'border-blue-300/15 bg-blue-300/[.05] text-blue-100/80'}`}>
          <div className="flex gap-3"><span className="text-base">{tone === 'error' ? '!' : '✓'}</span><span>Your identity and organization access are kept separate from the invitation link itself.</span></div>
        </div>
        {children}
      </div>
    </AuthExperienceShell>
  );
}
