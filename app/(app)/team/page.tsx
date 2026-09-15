import {DeactivateMember} from '@/components/team/DeactivateMember';
import {SmartProfile} from '@/components/smart/Profile';
import Link from 'next/link';
import {getLocale} from '@/lib/i18n/server';
import { createClient } from '@/lib/supabase/server';
import { getSessionContext } from '@/lib/auth/session';
import { getActiveOrganizationId } from '@/lib/auth/active-org';
import { deactivateTeamMember, revokeInvitation } from '@/lib/team/actions';
import { ResendInvitationButton } from '@/components/team/ResendInvitationButton';
import { InviteForm } from '@/components/team/InviteForm';
import { RoleSelect } from '@/components/team/RoleSelect';
import { Card, PageTitle } from '@/components/ui/primitives';

interface MemberRow {
  id: string;
  role: string;
  status: string;
  profile_id: string;
  profile: { full_name: string | null; avatar_url: string | null; phone: string | null } | { full_name: string | null; avatar_url: string | null; phone: string | null }[] | null;
}

interface InvitationRow {
  id: string;
  email: string;
  intended_role: string;
  status: string;
  created_at: string;
}

const ROLE_LABEL: Record<string, string> = {
  company_owner: 'Owner',
  company_admin: 'Admin',
  manager: 'Manager',
  technician: 'Technician',
};

export default async function TeamPage() {
  const locale = await getLocale(); const es = locale === 'es';
  const session = await getSessionContext();
  const activeOrgId = await getActiveOrganizationId(session.memberships);
  const actorRole = session.memberships.find((m) => m.organization_id === activeOrgId)?.role;
  const canManage = actorRole === 'company_owner' || actorRole === 'company_admin';
  const canInviteAdminLevel = actorRole === 'company_owner';

  const supabase = await createClient();
  const { data: members } = await supabase
    .from('organization_memberships')
    .select('id, role, status, profile_id, profile:profiles(full_name,avatar_url,phone)')
    .eq('organization_id', activeOrgId)
    .order('role')
    .returns<MemberRow[]>();

  const { data: invitations } = canManage
    ? await supabase
        .from('organization_invitations')
        .select('id, email, intended_role, status, created_at')
        .eq('organization_id', activeOrgId)
        .eq('status', 'pending')
        .order('created_at', { ascending: false })
        .returns<InvitationRow[]>()
    : { data: [] };

  return (
    <div className="max-w-6xl space-y-6">
      <PageTitle>{es?'Equipo y operación':'Team & operations'}</PageTitle>

      {canManage && (
        <details className="premium-card rounded-2xl p-5"><summary className="cursor-pointer text-gold font-semibold">{es?'+ Invitar a un miembro':'+ Invite team member'}</summary><div className="pt-4"><InviteForm canInviteAdminLevel={canInviteAdminLevel} /></div></details>
      )}

      {canManage && invitations && invitations.length > 0 && (
        <div>
          <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-3">Pending Invitations</div>
          <div className="space-y-2">
            {invitations.map((inv) => (
              <Card key={inv.id} className="flex items-center justify-between">
                <div><span className="text-sm">{inv.email}</span><span className="text-xs text-cool-gray ml-2">{ROLE_LABEL[inv.intended_role] ?? inv.intended_role}</span></div>
                <div className="flex items-center gap-3">
                  <ResendInvitationButton invitationId={inv.id} />
                  <form action={revokeInvitation.bind(null, inv.id)}>
                    <button type="submit" className="text-[10px] font-mono uppercase text-red-400 hover:underline">
                      Revoke
                    </button>
                  </form>
                </div>
              </Card>
            ))}
          </div>
        </div>
      )}

      <div>
        <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-3">Members</div>
        <div className="grid sm:grid-cols-2 xl:grid-cols-3 gap-4">
          {(members ?? []).map((m) => {
            const profile = Array.isArray(m.profile) ? m.profile[0] : m.profile;
            const isSelf = m.profile_id === session.userId;
            return (
              <Card key={m.id} className="flex flex-col items-stretch gap-4 !rounded-2xl !p-0 overflow-hidden">
                <SmartProfile name={profile?.full_name??'—'} photo={profile?.avatar_url} subtitle={ROLE_LABEL[m.role]??m.role} status={<span className="text-xs text-cool-gray">{m.status}</span>}/>
                {m.role === 'technician' && <Link className="text-gold text-sm" href={`/team/${m.profile_id}`}>{es?'Ver operación y remuneración →':'View operations & compensation →'}</Link>}
                {canManage && m.status === 'active' && m.role !== 'company_owner' && !isSelf && (
                  <div className="flex flex-wrap items-center gap-3 p-4">
                    <RoleSelect
                      membershipId={m.id}
                      currentRole={m.role}
                      options={canInviteAdminLevel ? ['company_admin', 'manager', 'technician'] : ['manager', 'technician']}
                    />
                    <DeactivateMember id={m.id}/>
                  </div>
                )}
              </Card>
            );
          })}
        </div>
      </div>
    </div>
  );
}
