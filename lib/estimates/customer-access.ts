import 'server-only';

import { createClient } from '@/lib/supabase/server';
import { buildInvitationConfirmationLink } from '@/lib/auth/invitations';

/**
 * Creates/reuses the customer membership invitation used by an estimate CTA.
 * Customer accounts follow the same activation rule as every other panel:
 * one-time secure email activation, then durable email + password sign-in.
 */
export async function prepareCustomerPortalUrl(organizationId: string, email: string): Promise<string> {
  const db = await createClient();
  const normalized = email.trim().toLowerCase();

  const { data: existing } = await db
    .from('organization_invitations')
    .select('id')
    .eq('organization_id', organizationId)
    .eq('email', normalized)
    .eq('intended_role', 'customer')
    .eq('status', 'pending')
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  let rawToken: string | undefined;
  if (existing?.id) {
    const { data, error } = await db.rpc('reissue_invitation_token', { p_invitation_id: existing.id });
    if (error) throw new Error(`Could not refresh customer portal invitation: ${error.message}`);
    rawToken = data?.[0]?.raw_token as string | undefined;
  } else {
    const { data, error } = await db.rpc('invite_team_member', {
      p_organization_id: organizationId,
      p_email: normalized,
      p_intended_role: 'customer',
    });
    if (error) {
      if (error.message.includes('organization_invitations_intended_role_check')) {
        throw new Error('Customer portal access is not enabled in the production database yet. Apply the V9.4 customer invitation migration, then retry.');
      }
      throw new Error(`Could not create customer portal invitation: ${error.message}`);
    }
    rawToken = data?.[0]?.raw_token as string | undefined;
  }

  if (!rawToken) throw new Error('Customer portal invitation did not return a secure token.');

  const { data: org } = await db.from('organizations').select('name').eq('id', organizationId).maybeSingle();
  const link = await buildInvitationConfirmationLink({
    email: normalized,
    rawToken,
    organizationName: org?.name,
    role: 'customer',
  });

  return link.confirmUrl;
}
