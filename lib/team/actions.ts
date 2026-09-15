'use server';

import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { getActiveOrganizationId } from '@/lib/auth/active-org';
import { getSessionContext } from '@/lib/auth/session';
import { logger } from '@/lib/logger';
import { deliverOrganizationInvitation } from '@/lib/auth/invitations';

// Cada acción de acá abajo es un pass-through a una función
// SECURITY DEFINER (migración 056/057/058) — la autorización real
// (jerarquía de roles, protección contra auto-promoción, protección
// del último owner) vive ahí, no acá. Este archivo nunca hace un
// UPDATE directo sobre organization_memberships.


export async function inviteTeamMember(formData: FormData) {
  const session = await getSessionContext();
  const explicitOrgId = formData.get('organizationId') as string | null;
  // Un kcc_admin invitando desde /companies/[organizationId] pasa el
  // id explícito de la compañía que está viendo — nunca el suyo
  // propio. El flujo de auto-servicio en /team no lo pasa, así que
  // cae al org activo del propio usuario como antes.
  const activeOrgId = explicitOrgId || (await getActiveOrganizationId(session.memberships));
  const fullName = (formData.get('fullName') as string)?.trim();
  const email = (formData.get('email') as string)?.trim().toLowerCase();
  const role = formData.get('role') as string;
  if (!activeOrgId || !email || !role) return { error: 'Missing fields.' };

  const supabase = await createClient();
  const { data, error } = await supabase.rpc('invite_team_member', {
    p_organization_id: activeOrgId,
    p_email: email,
    p_intended_role: role,
  });

  if (error) {
    logger.warn('inviteTeamMember failed', { message: error.message });
    return { error: error.message };
  }

  const rawToken = data?.[0]?.raw_token as string | undefined;
  const invitationId = data?.[0]?.invitation_id as string | undefined;
  if (!rawToken) {
    return { error: 'Invitation created but no token was returned — cannot send the invite email.' };
  }

  // Nombre real de la organización — nunca inventado. Si por algún
  // motivo no se puede leer, el template de Supabase cae solo al
  // wording genérico vía su propio {{ if }} (ver auth-templates.ts).
  const { data: org } = await supabase.from('organizations').select('name').eq('id', activeOrgId).maybeSingle();

  const emailResult = await deliverOrganizationInvitation({
    email,
    rawToken,
    fullName,
    organizationName: org?.name,
    role,
  });

  revalidatePath('/team');
  revalidatePath(`/companies/${activeOrgId}`);
  // El token crudo se devuelve por si el email falló y el admin necesita
  // compartir el link manualmente como respaldo — nunca es el camino
  // principal, solo la red de seguridad.
  return {
    invitationId,
    manualUrl: emailResult.success ? undefined : emailResult.fallbackUrl,
    emailSent: emailResult.success,
    emailError: emailResult.success ? undefined : emailResult.error,
    rateLimited: emailResult.rateLimited,
  };
}

export async function resendInvitation(invitationId: string) {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('reissue_invitation_token', { p_invitation_id: invitationId });
  if (error) {
    logger.warn('resendInvitation failed', { message: error.message });
    return { error: error.message };
  }
  const rawToken = data?.[0]?.raw_token as string | undefined;
  const email = data?.[0]?.email as string | undefined;
  if (!rawToken || !email) {
    return { error: 'Could not reissue an invitation token.' };
  }
  const { data: invitationRow } = await supabase.from('organization_invitations').select('organization_id, intended_role').eq('id', invitationId).maybeSingle();
  const { data: org } = invitationRow ? await supabase.from('organizations').select('name').eq('id', invitationRow.organization_id).maybeSingle() : { data: null };

  const emailResult = await deliverOrganizationInvitation({
    email,
    rawToken,
    organizationName: org?.name,
    role: invitationRow?.intended_role,
  });
  revalidatePath('/team');
  return { emailSent: emailResult.success, emailError: emailResult.success ? undefined : emailResult.error };
}

export async function resendInvitationAction(invitationId: string) {
  await resendInvitation(invitationId);
}

export async function revokeInvitation(invitationId: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('revoke_invitation', { p_invitation_id: invitationId });
  if (error) {
    logger.warn('revokeInvitation failed', { message: error.message });
    return;
  }
  revalidatePath('/team');
}

export async function changeMemberRole(formData: FormData) {
  const membershipId = formData.get('membershipId') as string;
  const newRole = formData.get('newRole') as string;
  const supabase = await createClient();
  const { error } = await supabase.rpc('change_member_role', { p_membership_id: membershipId, p_new_role: newRole });
  if (error) {
    logger.warn('changeMemberRole failed', { message: error.message });
    return {error:error.message};
  }
  revalidatePath('/team');
}

export async function deactivateTeamMember(membershipId: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('deactivate_team_member', { p_membership_id: membershipId });
  if (error) {
    logger.warn('deactivateTeamMember failed', { message: error.message });
    return {error:error.message};
  }
  revalidatePath('/team');
}
