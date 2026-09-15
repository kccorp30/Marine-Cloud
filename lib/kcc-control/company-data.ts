import 'server-only';
import { createClient } from '@/lib/supabase/server';

export interface CompanyListRow {
  id: string;
  name: string;
  status: string;
  primaryLocation: string | null;
  ownerName: string | null;
  activeTechnicianCount: number;
  activeWorkOrderCount: number;
  compensationType: string | null;
  createdAt: string;
}

export async function getCompanyNetwork(filter?: { status?: string; search?: string }): Promise<CompanyListRow[]> {
  const supabase = await createClient();

  let query = supabase
    .from('organizations')
    .select('id, name, status, created_at')
    .order('created_at', { ascending: false });

  if (filter?.status) query = query.eq('status', filter.status);
  if (filter?.search) query = query.ilike('name', `%${filter.search}%`);

  const { data: orgs } = await query;
  if (!orgs || orgs.length === 0) return [];

  const orgIds = orgs.map((o) => o.id);

  const [{ data: locations }, { data: memberships }, { data: workOrders }, { data: agreements }] = await Promise.all([
    supabase.from('organization_locations').select('organization_id, name, address').in('organization_id', orgIds).eq('is_primary', true),
    supabase.from('organization_memberships').select('organization_id, role, profile:profiles(full_name)').in('organization_id', orgIds).eq('status', 'active'),
    supabase.from('work_orders').select('organization_id, current_status').in('organization_id', orgIds),
    supabase.from('compensation_agreements').select('organization_id, compensation_type').in('organization_id', orgIds).eq('active', true),
  ]);

  const locationByOrg = new Map((locations ?? []).map((l) => [l.organization_id, l.name]));
  const agreementByOrg = new Map((agreements ?? []).map((a) => [a.organization_id, a.compensation_type]));

  const ownerByOrg = new Map<string, string>();
  const techCountByOrg = new Map<string, number>();
  for (const m of memberships ?? []) {
    const profile = Array.isArray(m.profile) ? m.profile[0] : m.profile;
    if (m.role === 'company_owner' && !ownerByOrg.has(m.organization_id)) {
      ownerByOrg.set(m.organization_id, profile?.full_name ?? '—');
    }
    if (m.role === 'technician') {
      techCountByOrg.set(m.organization_id, (techCountByOrg.get(m.organization_id) ?? 0) + 1);
    }
  }

  const activeWoCountByOrg = new Map<string, number>();
  for (const wo of workOrders ?? []) {
    if (wo.current_status !== 'completed' && wo.current_status !== 'cancelled') {
      activeWoCountByOrg.set(wo.organization_id, (activeWoCountByOrg.get(wo.organization_id) ?? 0) + 1);
    }
  }

  return orgs.map((o) => ({
    id: o.id,
    name: o.name,
    status: o.status,
    primaryLocation: locationByOrg.get(o.id) ?? null,
    ownerName: ownerByOrg.get(o.id) ?? null,
    activeTechnicianCount: techCountByOrg.get(o.id) ?? 0,
    activeWorkOrderCount: activeWoCountByOrg.get(o.id) ?? 0,
    compensationType: agreementByOrg.get(o.id) ?? null,
    createdAt: o.created_at,
  }));
}

export interface CompanyDetail {
  id: string;
  name: string;
  legalName: string | null;
  status: string;
  createdAt: string;
  settings: { timezone: string; currency: string; locale: string } | null;
  locations: { id: string; name: string; address: string | null; isPrimary: boolean }[];
  members: { id: string; profileId: string; fullName: string | null; role: string; status: string }[];
  activeWorkOrderCount: number;
  openInvoicesTotal: number;
  currentAgreement: CompensationAgreementRow | null;
  agreementHistory: CompensationAgreementRow[];
}

export interface CompensationAgreementRow {
  id: string;
  compensationType: string;
  percentageRate: number | null;
  fixedAmount: number | null;
  currency: string;
  effectiveFrom: string;
  effectiveUntil: string | null;
  active: boolean;
  notes: string | null;
}

function mapAgreement(a: any): CompensationAgreementRow {
  return {
    id: a.id,
    compensationType: a.compensation_type,
    percentageRate: a.percentage_rate,
    fixedAmount: a.fixed_amount,
    currency: a.currency,
    effectiveFrom: a.effective_from,
    effectiveUntil: a.effective_until,
    active: a.active,
    notes: a.notes,
  };
}

export interface KccAttributionRow {
  id: string;
  workOrderId: string;
  workOrderTitle: string | null;
  compensationType: string;
  basisAmount: number;
  calculatedKccAmount: number;
  status: string;
  revokedAt: string | null;
  createdAt: string;
}

/** Nunca etiqueta un monto potencial como pagado — status siempre 'snapshot'/'revoked' hasta que exista un flujo real de settlement (fase futura). Una fila 'revoked' se muestra para auditoría pero nunca cuenta como ingreso potencial activo. */
export async function getKccAttributions(organizationId: string): Promise<KccAttributionRow[]> {
  const supabase = await createClient();
  const { data } = await supabase
    .from('kcc_revenue_attributions')
    .select('id, work_order_id, compensation_type, basis_amount, calculated_kcc_amount, status, revoked_at, created_at, work_order:work_orders(title)')
    .eq('organization_id', organizationId)
    .order('created_at', { ascending: false });

  return (data ?? []).map((a: any) => ({
    id: a.id,
    workOrderId: a.work_order_id,
    workOrderTitle: (Array.isArray(a.work_order) ? a.work_order[0] : a.work_order)?.title ?? null,
    compensationType: a.compensation_type,
    basisAmount: Number(a.basis_amount),
    calculatedKccAmount: Number(a.calculated_kcc_amount),
    status: a.status,
    revokedAt: a.revoked_at,
    createdAt: a.created_at,
  }));
}

export async function getCompanyDetail(organizationId: string): Promise<CompanyDetail | null> {
  const supabase = await createClient();

  const { data: org } = await supabase.from('organizations').select('id, name, legal_name, status, created_at').eq('id', organizationId).maybeSingle();
  if (!org) return null;

  const [{ data: settings }, { data: locations }, { data: members }, { data: workOrders }, { data: openInvoices }, { data: agreements }] = await Promise.all([
    supabase.from('organization_settings').select('timezone, currency, locale').eq('organization_id', organizationId).maybeSingle(),
    supabase.from('organization_locations').select('id, name, address, is_primary').eq('organization_id', organizationId).order('is_primary', { ascending: false }),
    supabase.from('organization_memberships').select('id, profile_id, role, status, profile:profiles(full_name)').eq('organization_id', organizationId),
    supabase.from('work_orders').select('current_status').eq('organization_id', organizationId),
    supabase.from('invoices').select('balance_due').eq('organization_id', organizationId).in('status', ['sent', 'partially_paid', 'overdue']),
    supabase.from('compensation_agreements').select('*').eq('organization_id', organizationId).order('effective_from', { ascending: false }),
  ]);

  const activeWorkOrderCount = (workOrders ?? []).filter((wo) => wo.current_status !== 'completed' && wo.current_status !== 'cancelled').length;
  const openInvoicesTotal = (openInvoices ?? []).reduce((sum, inv) => sum + Number(inv.balance_due ?? 0), 0);
  const allAgreements = (agreements ?? []).map(mapAgreement);
  const currentAgreement = allAgreements.find((a) => a.active) ?? null;

  return {
    id: org.id,
    name: org.name,
    legalName: org.legal_name,
    status: org.status,
    createdAt: org.created_at,
    settings: settings ? { timezone: settings.timezone, currency: settings.currency, locale: settings.locale } : null,
    locations: (locations ?? []).map((l) => ({ id: l.id, name: l.name, address: l.address, isPrimary: l.is_primary })),
    members: (members ?? []).map((m: any) => ({
      id: m.id,
      profileId: m.profile_id,
      fullName: (Array.isArray(m.profile) ? m.profile[0] : m.profile)?.full_name ?? null,
      role: m.role,
      status: m.status,
    })),
    activeWorkOrderCount,
    openInvoicesTotal,
    currentAgreement,
    agreementHistory: allAgreements,
  };
}
