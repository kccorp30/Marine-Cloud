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
  deliveryProvider?: 'resend';
};

export type InvitationLinkResult = {
  confirmUrl: string;
  requiresPasswordSetup: boolean;
  existingAccount: boolean;
};

function isExistingUserError(error: { status?: number; message?: string } | null | undefined) {
  if (!error) return false;
  const message = error.message?.toLowerCase() ?? '';
  return (
    error.status === 422 ||
    message.includes('already') ||
    message.includes('registered') ||
    message.includes('exists')
  );
}

/**
 * Builds the secure Supabase confirmation URL using the SAME proven identity
 * strategy that shipped in V8:
 *
 * 1. Try an Auth `invite` link first.
 * 2. If Auth says the user already exists, use a `magiclink` only for this
 *    one-time invitation acceptance.
 * 3. Deliver the generated token ourselves through Resend.
 *
 * IMPORTANT: this intentionally has NO dependency on `profiles.password_set_at`
 * or any V9 database migration. An invitation must keep working even when the
 * auth UX migration has not yet been applied to production.
 *
 * A brand-new user is explicitly marked in Auth metadata as requiring password
 * setup. If delivery fails and the invite is later resent, the Auth user already
 * exists, but that metadata survives, so the resend still routes to password
 * creation instead of being mistaken for a legacy account.
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
  const acceptBase = `/accept-invite?token=${encodeURIComponent(input.rawToken)}`;
  const redirectTo = `${getSiteUrl()}${acceptBase}`;

  const metadata: Record<string, string | boolean> = {
    password_setup_required: true,
    password_setup_complete: false,
  };
  if (input.fullName) metadata.full_name = input.fullName;
  if (input.organizationName) metadata.organization_name = input.organizationName;
  if (input.role) metadata.role = input.role;

  let linkType: 'invite' | 'magiclink' = 'invite';
  let generated = await service.auth.admin.generateLink({
    type: 'invite',
    email,
    options: {
      data: metadata,
      redirectTo,
    },
  });

  if (generated.error) {
    if (!isExistingUserError(generated.error)) {
      logger.warn('auth.admin.generateLink(invite) failed', {
        message: generated.error.message,
        status: generated.error.status,
      });
      throw new Error(generated.error.message || 'Could not generate invitation identity link.');
    }

    linkType = 'magiclink';
    generated = await service.auth.admin.generateLink({
      type: 'magiclink',
      email,
      options: { redirectTo },
    });
  }

  if (generated.error || !generated.data?.properties?.hashed_token) {
    const message = generated.error?.message || 'Could not generate a secure authentication link.';
    logger.warn('auth.admin.generateLink failed', {
      message,
      status: generated.error?.status,
    });
    throw new Error(message);
  }

  // New identity: always require first-time password creation.
  // Existing identity: only require it if a previous Marine Cloud invitation
  // explicitly marked the account as unfinished. Legacy accounts have no such
  // flag and therefore are never forced through onboarding.
  const userMetadata = generated.data.user?.user_metadata ?? {};
  const requiresPasswordSetup =
    linkType === 'invite' ||
    (userMetadata.password_setup_required === true && userMetadata.password_setup_complete !== true);

  if (requiresPasswordSetup && generated.data.user?.id) {
    const update = await service.auth.admin.updateUserById(generated.data.user.id, {
      user_metadata: {
        ...userMetadata,
        password_setup_required: true,
        password_setup_complete: false,
      },
    });
    // Metadata improves the resend/onboarding experience, but a secondary
    // metadata write must never block email delivery after generateLink worked.
    if (update.error) {
      logger.warn('Could not persist invitation password-setup metadata', {
        message: update.error.message,
      });
    }
  }

  const acceptPath = `${acceptBase}${requiresPasswordSetup ? '&setup=1' : ''}`;
  const confirmUrl = `${getSiteUrl()}/auth/confirm?token_hash=${encodeURIComponent(
    generated.data.properties.hashed_token,
  )}&type=${encodeURIComponent(generated.data.properties.verification_type)}&next=${encodeURIComponent(acceptPath)}`;

  return {
    confirmUrl,
    requiresPasswordSetup,
    existingAccount: linkType === 'magiclink',
  };
}

/**
 * Organization invitation delivery.
 *
 * V9.3 deliberately restores V8's proven mail transport: Supabase generates
 * the identity token, Resend delivers the branded message. We do NOT silently
 * switch transports. If Resend is misconfigured/rejects the sender, the UI gets
 * the real provider error and a manual secure URL remains available.
 */
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

  const from =
    process.env.AUTH_FROM_EMAIL ||
    process.env.RESEND_FROM_EMAIL ||
    process.env.EMAIL_FROM_ADDRESS ||
    'KCC Marine Cloud <notifications@kccorpglobal.com>';

  const result = await provider.sendEmail({
    to: input.email.trim().toLowerCase(),
    from,
    subject: "You're invited to KCC Marine Cloud",
    text: `You've been invited to join${input.organizationName ? ` ${input.organizationName}` : ' a company workspace'} on KCC Marine Cloud.\n\nOpen your secure invitation:\n${link.confirmUrl}\n\n${
      link.requiresPasswordSetup
        ? 'After activation, you will create your password for future sign-ins.'
        : 'After accepting, continue using your existing email and password for future sign-ins.'
    }\n\nThis link is unique to you. Do not forward it.`,
    html: renderDirectInviteEmail(
      link.confirmUrl,
      input.organizationName ?? undefined,
      input.role ?? undefined,
      link.requiresPasswordSetup,
    ),
  });

  if (result.success) {
    return {
      success: true,
      requiresPasswordSetup: link.requiresPasswordSetup,
      existingAccount: link.existingAccount,
      deliveryProvider: 'resend',
    };
  }

  const error = result.error || 'Email delivery failed.';
  const rateLimited = /rate.?limit|too many requests|429/i.test(error);
  logger.warn('Resend invitation email failed', { message: error });

  return {
    success: false,
    error: rateLimited
      ? 'Email sending limit reached. Please wait before resending the invitation.'
      : error,
    rateLimited,
    requiresPasswordSetup: link.requiresPasswordSetup,
    existingAccount: link.existingAccount,
    fallbackUrl: link.confirmUrl,
  };
}
