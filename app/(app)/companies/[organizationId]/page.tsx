import {EmailSetup} from '@/components/launch/EmailSetup';
import {MonthlyCharges} from '@/components/launch/MonthlyCharges';
import {MonthlyFeeForm} from '@/components/launch/MonthlyFeeForm';
import { notFound, redirect } from 'next/navigation';
import { getSessionContext } from '@/lib/auth/session';
import { getCompanyDetail, getKccAttributions } from '@/lib/kcc-control/company-data';
import { createClient } from '@/lib/supabase/server';
import { OrganizationStatusControls } from '@/components/kcc-control/OrganizationStatusControls';
import { CompensationPanel } from '@/components/kcc-control/CompensationPanel';
import { MemberRoleSelect } from '@/components/kcc-control/MemberRoleSelect';
import { LocationManagementPanel } from '@/components/kcc-control/LocationManagementPanel';
import { Card } from '@/components/ui/primitives';
import { CommercialSection } from '@/components/kcc-control/CommercialSection';
import { getCurrentSubscription, getAllPlans } from '@/lib/subscriptions/data';
import { InviteForm } from '@/components/team/InviteForm';
import { revokeInvitation } from '@/lib/team/actions';
import { ResendInvitationButton } from '@/components/team/ResendInvitationButton';
import { CompanyDetailTabs } from '@/components/kcc-control/CompanyDetailTabs';

const STATUS_COLOR: Record<string, string> = {
  active: 'text-emerald-400 border-emerald-500/30 bg-emerald-500/[0.06]',
  inactive: 'text-cool-gray border-white/15 bg-white/[0.03]',
  suspended: 'text-red-400 border-red-500/30 bg-red-500/[0.06]',
  archived: 'text-red-400 border-red-500/30 bg-red-500/[0.06]',
};

const ROLE_LABEL: Record<string, string> = {
  company_owner: 'Owner',
  company_admin: 'Admin',
  manager: 'Manager',
  technician: 'Technician',
};

export default async function CompanyDetailPage({ params }: { params: Promise<{ organizationId: string }> }) {
  const session = await getSessionContext();
  if (!session.isKccAdmin) redirect('/dashboard');

  const { organizationId } = await params;
  const company = await getCompanyDetail(organizationId);
  if (!company) notFound();
  const attributions = await getKccAttributions(organizationId);
  const subscription = await getCurrentSubscription(organizationId);
  const plans = await getAllPlans();

  const supabase = await createClient();
  const { data: invitations } = await supabase
    .from('organization_invitations')
    .select('id, email, intended_role, status, created_at')
    .eq('organization_id', organizationId)
    .eq('status', 'pending')
    .order('created_at', { ascending: false });

  const pendingCount = invitations?.length ?? 0;
  const memberCount = company.members.length;

  return (
    <div className="max-w-7xl space-y-6">
<MonthlyFeeForm organizationId={organizationId} amount={subscription?.billingCycle === "monthly" && subscription.currency === "USD" ? subscription.priceSnapshot : null}/>
<MonthlyCharges organizationId={organizationId} canManage/>
<EmailSetup organizationId={organizationId}/>
      {/* Hero */}
      <div className="relative overflow-hidden glass-strong rounded-xl p-7 animate-fade-up">
        <div className="absolute -top-20 -right-20 w-72 h-72 rounded-full bg-gold/[0.06] blur-3xl pointer-events-none" />
        <div className="relative flex flex-col lg:flex-row lg:items-end justify-between gap-4">
          <div>
            <div className="flex items-center gap-3 flex-wrap">
              <h1 className="font-display text-2xl lg:text-3xl font-semibold text-marine-white">{company.name}</h1>
              <span className={`font-mono text-[10px] uppercase px-2.5 py-1 rounded-full border ${STATUS_COLOR[company.status] ?? 'text-cool-gray border-white/15'}`}>
                {company.status}
              </span>
            </div>
            {company.legalName && <p className="text-xs text-cool-gray mt-1">{company.legalName}</p>}
            <p className="text-xs text-cool-gray/70 mt-0.5">Created {new Date(company.createdAt).toLocaleDateString()}</p>
          </div>

          <div className="flex gap-6">
            <div>
              <div className="text-xl font-display font-bold text-marine-white">{company.activeWorkOrderCount}</div>
              <div className="font-mono text-[9px] uppercase text-cool-gray">Active Work Orders</div>
            </div>
            <div>
              <div className="text-xl font-display font-bold text-marine-white">${company.openInvoicesTotal.toLocaleString()}</div>
              <div className="font-mono text-[9px] uppercase text-cool-gray">Open Balance</div>
            </div>
            <div>
              <div className="text-xl font-display font-bold text-marine-white">{memberCount}</div>
              <div className="font-mono text-[9px] uppercase text-cool-gray">Members</div>
            </div>
          </div>
        </div>
      </div>

      <CompanyDetailTabs
        tabs={[
          {
            id: 'overview',
            label: 'Overview',
            content: (
              <div className="grid lg:grid-cols-2 gap-5">
                <Card>
                  <div className="font-mono text-[10px] uppercase tracking-[0.15em] text-gold-dim mb-3">Status</div>
                  <OrganizationStatusControls organizationId={company.id} currentStatus={company.status} />
                </Card>
                <Card>
                  <div className="font-mono text-[10px] uppercase tracking-[0.15em] text-gold-dim mb-3">Operational Summary</div>
                  <div className="grid grid-cols-2 gap-y-2 text-sm">
                    <span className="text-cool-gray">Active work orders</span>
                    <span className="text-marine-white">{company.activeWorkOrderCount}</span>
                    <span className="text-cool-gray">Open invoice balance</span>
                    <span className="text-marine-white">${company.openInvoicesTotal.toLocaleString()}</span>
                    {company.settings && (
                      <>
                        <span className="text-cool-gray">Timezone / Currency</span>
                        <span className="text-marine-white">
                          {company.settings.timezone} · {company.settings.currency}
                        </span>
                      </>
                    )}
                  </div>
                </Card>
              </div>
            ),
          },
          {
            id: 'commercial',
            label: 'Commercial',
            content: (
              <Card>
                <CommercialSection organizationId={company.id} organizationStatus={company.status} subscription={subscription} plans={plans} />
              </Card>
            ),
          },
          {
            id: 'locations',
            label: 'Locations',
            badge: company.locations.length,
            content: (
              <Card>
                <div className="font-mono text-[10px] uppercase tracking-[0.15em] text-gold-dim mb-3">Locations</div>
                <LocationManagementPanel organizationId={company.id} locations={company.locations} />
              </Card>
            ),
          },
          {
            id: 'members',
            label: 'Members',
            badge: memberCount + pendingCount,
            content: (
              <div className="space-y-5">
                <Card>
                  <div className="font-mono text-[10px] uppercase tracking-[0.15em] text-gold-dim mb-3">Invite Member</div>
                  <InviteForm canInviteAdminLevel={true} organizationId={company.id} isKccAdmin={true} />
                </Card>

                {pendingCount > 0 && (
                  <Card>
                    <div className="font-mono text-[10px] uppercase tracking-[0.15em] text-gold-dim mb-3">Pending Invitations</div>
                    <div className="space-y-2">
                      {invitations!.map((inv) => (
                        <div key={inv.id} className="flex items-center justify-between text-sm bg-white/[0.02] border border-white/[0.06] rounded-md p-3">
                          <div>
                            <span className="text-marine-white">{inv.email}</span>
                            <span className="text-xs text-cool-gray ml-2">{ROLE_LABEL[inv.intended_role] ?? inv.intended_role}</span>
                            <span className="font-mono text-[9px] uppercase text-amber-400 ml-2 border border-amber-500/30 bg-amber-500/[0.06] px-1.5 py-0.5 rounded-full">
                              invited
                            </span>
                          </div>
                          <div className="flex items-center gap-3">
                            <ResendInvitationButton invitationId={inv.id} />
                            <form action={revokeInvitation.bind(null, inv.id)}>
                              <button type="submit" className="text-[10px] font-mono uppercase text-red-400 hover:underline">
                                Revoke
                              </button>
                            </form>
                          </div>
                        </div>
                      ))}
                    </div>
                  </Card>
                )}

                <Card>
                  <div className="font-mono text-[10px] uppercase tracking-[0.15em] text-gold-dim mb-3">Members</div>
                  <div className="grid sm:grid-cols-2 gap-2">
                    {company.members.map((m) => (
                      <div key={m.id} className="flex items-center justify-between text-sm bg-white/[0.02] border border-white/[0.06] rounded-md p-3">
                        <div>
                          <span className="text-marine-white">{m.fullName ?? '—'}</span>
                          <div className="font-mono text-[9px] uppercase text-cool-gray mt-0.5">{m.status}</div>
                        </div>
                        <MemberRoleSelect membershipId={m.id} organizationId={company.id} currentRole={m.role} />
                      </div>
                    ))}
                  </div>
                  {memberCount === 0 && pendingCount === 0 && (
                    <p className="text-sm text-cool-gray">No members yet. Invite the first member using the form above.</p>
                  )}
                  {memberCount === 0 && pendingCount > 0 && (
                    <p className="text-sm text-cool-gray">No active members yet — waiting on the pending invitation(s) above.</p>
                  )}
                </Card>
              </div>
            ),
          },
          {
            id: 'compensation',
            label: 'Compensation',
            content: (
              <Card>
                <div className="font-mono text-[10px] uppercase tracking-[0.15em] text-gold-dim mb-3">KCC Compensation</div>
                <CompensationPanel organizationId={company.id} currentAgreement={company.currentAgreement} history={company.agreementHistory} />
              </Card>
            ),
          },
          {
            id: 'attributed-work',
            label: 'Attributed Work',
            badge: attributions.length,
            content: (
              <Card>
                <div className="font-mono text-[10px] uppercase tracking-[0.15em] text-gold-dim mb-3">KCC-Attributed Work</div>
                <div className="grid lg:grid-cols-2 gap-2">
                  {attributions.map((a) => (
                    <div
                      key={a.id}
                      className={`text-sm flex items-center justify-between bg-white/[0.02] border border-white/[0.06] rounded-md p-3 ${a.status === 'revoked' ? 'opacity-50' : ''}`}
                    >
                      <div>
                        <div className="text-marine-white">{a.workOrderTitle ?? a.workOrderId}</div>
                        <div className="text-xs text-cool-gray">
                          Basis ${a.basisAmount.toLocaleString()} · {a.compensationType}
                        </div>
                      </div>
                      <div className="text-right">
                        <div className={a.status === 'revoked' ? 'text-cool-gray line-through' : 'text-gold'}>${a.calculatedKccAmount.toLocaleString()}</div>
                        <div className="font-mono text-[9px] uppercase text-cool-gray">
                          {a.status === 'snapshot' ? 'potential — not yet settled' : a.status === 'revoked' ? `revoked ${a.revokedAt ? new Date(a.revokedAt).toLocaleDateString() : ''}` : a.status}
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
                {attributions.length === 0 && <p className="text-sm text-cool-gray">No KCC-attributed work yet.</p>}
              </Card>
            ),
          },
        ]}
      />
    </div>
  );
}
