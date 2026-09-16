'use server';

import { revalidatePath } from 'next/cache';
import { getSessionContext } from '@/lib/auth/session';
import { getActiveOrganizationId } from '@/lib/auth/active-org';
import { createClient } from '@/lib/supabase/server';
import { deliverOrganizationInvitation } from '@/lib/auth/invitations';
import { logger } from '@/lib/logger';

export async function inviteCustomerPortalAccess(customerId: string) {
  const session = await getSessionContext();
  const organizationId = await getActiveOrganizationId(session.memberships);
  if (!organizationId) return { error: 'Workspace unavailable.' };

  const membership = session.memberships.find((m) => m.organization_id === organizationId);
  if (!session.isKccAdmin && !['company_owner', 'company_admin', 'manager'].includes(membership?.role ?? '')) {
    return { error: 'You are not allowed to invite customer portal users.' };
  }

  const db = await createClient();
  const { data: customer, error: customerError } = await db
    .from('customers')
    .select('id,first_name,last_name,email,profile_id')
    .eq('id', customerId)
    .eq('organization_id', organizationId)
    .maybeSingle();

  if (customerError || !customer) return { error: 'Customer not found.' };
  const email = customer.email?.trim().toLowerCase();
  if (!email) return { error: 'Add an email address before enabling customer portal access.' };

  if (customer.profile_id) {
    return { success: true, alreadyActive: true };
  }

  const { data, error } = await db.rpc('invite_team_member', {
    p_organization_id: organizationId,
    p_email: email,
    p_intended_role: 'customer',
  });
  if (error) {
    logger.warn('inviteCustomerPortalAccess failed', { message: error.message });
    return { error: error.message };
  }

  const rawToken = data?.[0]?.raw_token as string | undefined;
  const invitationId = data?.[0]?.invitation_id as string | undefined;
  if (!rawToken) return { error: 'Customer invitation was created without a usable token.' };

  const { data: org } = await db.from('organizations').select('name').eq('id', organizationId).maybeSingle();
  const delivery = await deliverOrganizationInvitation({
    email,
    rawToken,
    fullName: [customer.first_name, customer.last_name].filter(Boolean).join(' ') || null,
    organizationName: org?.name,
    role: 'customer',
  });

  revalidatePath(`/customers/${customerId}`);
  return {
    success: delivery.success,
    invitationId,
    emailSent: delivery.success,
    emailError: delivery.success ? undefined : delivery.error,
    manualUrl: delivery.success ? undefined : delivery.fallbackUrl,
  };
}
