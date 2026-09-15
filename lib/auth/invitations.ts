import 'server-only';

import { createClient as createServiceClient } from '@/lib/supabase/service';
import { getEmailProvider } from '@/lib/email/resend';
import { renderDirectInviteEmail } from '@/lib/email/auth-templates';
import { getSiteUrl } from '@/lib/auth/site-url';
import { logger } from '@/lib/logger';

export type InvitationDeliveryResult = {
  success: boolean;
  error?: string;
  rateLimited?: boolean;
  requiresPasswordSetup?: boolean;
  existingAccount?: boolean;
  fallbackUrl?: string;
};

export type InvitationLinkResult = {
  confirmUrl: string;
  requiresPasswordSetup: boolean;
  existingAccount: boolean;
};

/**
 * Creates the Supabase identity link for an organization invitation.
 *
 * Password state is intentionally NOT inferred from email_confirmed_at.
 * Marine Cloud records a successful password setup/login in profiles.password_set_at.
 * A pre-existing Auth user created by an earlier invite can therefore still be
 * correctly routed through first-time password creation.
 */
export async function buildInvitationConfirmationLink(input: {
  email: string;
  rawToken: string;
  fullName?: string | null;
  organizationName?: string | null;
  role?: string | null;
}): Promise<InvitationLinkResult> {
  const email = input.email.trim().toLowerCase();
  const service = createServiceClient();

  const { data: profile, error: profileError } = await service
    .from('profiles')
    .select('id,password_set_at')
    .eq('email', email)
    .maybeSingle();

  if (profileError) {
    throw new Error(`Could not resolve account credential state: ${profileError.message}`);
  }

  const existingAccount = Boolean(profile?.id);
  const requiresPasswordSetup = !profile?.password_set_at;

  const metadata: Record<string, string> = {};
  if (input.fullName) metadata.full_name = input.fullName;
  if (input.organizationName) metadata.organization_name = input.organizationName;
  if (input.role) metadata.role = input.role;

  let generated = await service.auth.admin.generateLink({
    type: existingAccount ? 'magiclink' : 'invite',
    email,
    options: {
      data: !existingAccount && Object.keys(metadata).length > 0 ? metadata : undefined,
      redirectTo: `${getSiteUrl()}/accept-invite?token=${encodeURIComponent(input.rawToken)}`,
    },
  });

  // Handles a stale/inconsistent state where auth.users exists but profiles
  // was not found, without ever creating a duplicate user.
  if (generated.error && !existingAccount) {
    const message = generated.error.message?.toLowerCase() ?? '';
    const alreadyExists =
      generated.error.status === 422 ||
      message.includes('already') ||
      message.includes('registered') ||
      message.includes('exists');

    if (alreadyExists) {
      generated = await service.auth.admin.generateLink({
        type: 'magiclink',
        email,
        options: {
          redirectTo: `${getSiteUrl()}/accept-invite?token=${encodeURIComponent(input.rawToken)}`,
        },
      });
    }
  }

  if (generated.error || !generated.data?.properties?.hashed_token) {
    throw new Error(generated.error?.message || 'Could not generate a secure authentication link.');
  }

  const acceptPath = `/accept-invite?token=${encodeURIComponent(input.rawToken)}${requiresPasswordSetup ? '&setup=1' : ''}`;
  const confirmUrl = `${getSiteUrl()}/auth/confirm?token_hash=${encodeURIComponent(
    generated.data.properties.hashed_token,
  )}&type=${encodeURIComponent(generated.data.properties.verification_type)}&next=${encodeURIComponent(acceptPath)}`;

  return { confirmUrl, requiresPasswordSetup, existingAccount };
}

export async function deliverOrganizationInvitation(input: {
  email: string;
  rawToken: string;
  fullName?: string | null;
  organizationName?: string | null;
  role?: string | null;
}): Promise<InvitationDeliveryResult> {
  let link: InvitationLinkResult;
  try {
    link = await buildInvitationConfirmationLink(input);
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Could not generate a secure invitation link.';
    logger.warn('Invitation link generation failed', { message });
    return { success: false, error: message };
  }

  let provider;
  try {
    provider = getEmailProvider();
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Email provider is not configured.';
    logger.warn('Invitation email provider unavailable', { message });
    return {
      success: false,
      error: message,
      requiresPasswordSetup: link.requiresPasswordSetup,
      existingAccount: link.existingAccount,
      fallbackUrl: link.confirmUrl,
    };
  }

  const from = process.env.AUTH_FROM_EMAIL || 'KCC Marine Cloud <notifications@kccorpglobal.com>';
  const html = renderDirectInviteEmail(
    link.confirmUrl,
    input.organizationName ?? undefined,
    input.role ?? undefined,
    link.requiresPasswordSetup,
  );

  const result = await provider.sendEmail({
    to: input.email.trim().toLowerCase(),
    from,
    subject: "You're invited to KCC Marine Cloud",
    text: `You've been invited to join${input.organizationName ? ` ${input.organizationName}` : ' a company workspace'} on KCC Marine Cloud.\n\nOpen your secure invitation:\n${link.confirmUrl}\n\n${
      link.requiresPasswordSetup
        ? 'After activation, you will create your password for future sign-ins.'
        : 'After accepting, continue using your existing email and password for future sign-ins.'
    }\n\nThis link is unique to you. Do not forward it.`,
    html,
  });

  if (result.success) {
    return {
      success: true,
      requiresPasswordSetup: link.requiresPasswordSetup,
      existingAccount: link.existingAccount,
    };
  }

  const error = result.error || 'Email delivery failed.';
  const rateLimited = /rate.?limit|too many requests|429/i.test(error);
  logger.warn('Resend invitation email failed', { message: error });
  return {
    success: false,
    error: rateLimited ? 'Email sending limit reached. Please wait before resending the invitation.' : error,
    rateLimited,
    requiresPasswordSetup: link.requiresPasswordSetup,
    existingAccount: link.existingAccount,
    fallbackUrl: link.confirmUrl,
  };
}
