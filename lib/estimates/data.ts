import 'server-only';
import { createClient } from '@/lib/supabase/server';

export interface EstimateListRow {
  id: string;
  estimateNumber: string;
  type: 'estimate' | 'change_order';
  status: string;
  total: number;
  currency: string;
  customerName: string | null;
  vesselName: string | null;
  workOrderId: string | null;
  createdAt: string;
}

export interface EstimateLineItemDTO {
  id: string;
  lineType: string;
  description: string;
  quantity: number;
  unitPrice: number;
  lineTotal: number;
  customerVisible: boolean;
}

export interface EstimateVersionDTO {
  id: string;
  versionNumber: number;
  status: string;
  title: string | null;
  customerMessage: string | null;
  subtotal: number;
  discount: number;
  tax: number;
  total: number;
  currency: string;
  validUntil: string | null;
  sentAt: string | null;
  lineItems: EstimateLineItemDTO[];
}

export interface EstimateDetailDTO {
  id: string;
  estimateNumber: string;
  type: 'estimate' | 'change_order';
  status: string;
  customerName: string | null;
  vesselName: string | null;
  workOrderId: string | null;
  serviceRequestId: string | null;
  currentVersionId: string | null;
  versions: EstimateVersionDTO[];
  authorizedTotal: number | null;
}

// Server-only — cada query pasa por RLS normal (staff ve todo el
// tenant, customer solo lo propio), esta capa no agrega autorización
// propia, solo arma el DTO tipado.
export async function getEstimateList(organizationId: string, filters?: { status?: string; type?: string }): Promise<EstimateListRow[]> {
  const supabase = await createClient();
  let query = supabase
    .from('estimates')
    .select(
      'id, estimate_number, type, status, work_order_id, created_at, customer:customers(first_name, last_name), vessel:vessels(name), current_version:estimate_versions!fk_estimates_current_version(total, currency)'
    )
    .eq('organization_id', organizationId)
    .order('created_at', { ascending: false });

  if (filters?.status) query = query.eq('status', filters.status);
  if (filters?.type) query = query.eq('type', filters.type);

  const { data } = await query;
  return (data ?? []).map((e: any) => {
    const customer = Array.isArray(e.customer) ? e.customer[0] : e.customer;
    const vessel = Array.isArray(e.vessel) ? e.vessel[0] : e.vessel;
    const version = Array.isArray(e.current_version) ? e.current_version[0] : e.current_version;
    return {
      id: e.id,
      estimateNumber: e.estimate_number,
      type: e.type,
      status: e.status,
      total: version?.total ?? 0,
      currency: version?.currency ?? 'USD',
      customerName: customer ? `${customer.first_name} ${customer.last_name}` : null,
      vesselName: vessel?.name ?? null,
      workOrderId: e.work_order_id,
      createdAt: e.created_at,
    };
  });
}

export async function getEstimateDetail(estimateId: string): Promise<EstimateDetailDTO | null> {
  const supabase = await createClient();

  const { data: estimate } = await supabase
    .from('estimates')
    .select('id, estimate_number, type, status, work_order_id, service_request_id, current_version_id, customer:customers(first_name, last_name), vessel:vessels(name)')
    .eq('id', estimateId)
    .maybeSingle();

  if (!estimate) return null;

  const { data: versions } = await supabase
    .from('estimate_versions')
    .select('id, version_number, status, title, customer_message, subtotal, discount, tax, total, currency, valid_until, sent_at')
    .eq('estimate_id', estimateId)
    .order('version_number', { ascending: false });

  const versionIds = (versions ?? []).map((v) => v.id);
  const { data: lineItems } =
    versionIds.length > 0
      ? await supabase
          .from('estimate_line_items')
          .select('id, estimate_version_id, line_type, description, quantity, unit_price, line_total, customer_visible, sort_order')
          .in('estimate_version_id', versionIds)
          .order('sort_order')
      : { data: [] };

  const linesByVersion = new Map<string, EstimateLineItemDTO[]>();
  for (const li of lineItems ?? []) {
    const list = linesByVersion.get(li.estimate_version_id) ?? [];
    list.push({
      id: li.id,
      lineType: li.line_type,
      description: li.description,
      quantity: Number(li.quantity),
      unitPrice: Number(li.unit_price),
      lineTotal: Number(li.line_total),
      customerVisible: li.customer_visible,
    });
    linesByVersion.set(li.estimate_version_id, list);
  }

  const customer = Array.isArray(estimate.customer) ? estimate.customer[0] : estimate.customer;
  const vessel = Array.isArray(estimate.vessel) ? estimate.vessel[0] : estimate.vessel;

  const authorizedTotal = estimate.work_order_id ? await getWorkOrderAuthorizedTotal(estimate.work_order_id) : null;

  return {
    id: estimate.id,
    estimateNumber: estimate.estimate_number,
    type: estimate.type,
    status: estimate.status,
    customerName: customer ? `${customer.first_name} ${customer.last_name}` : null,
    vesselName: vessel?.name ?? null,
    workOrderId: estimate.work_order_id,
    serviceRequestId: estimate.service_request_id,
    currentVersionId: estimate.current_version_id,
    versions: (versions ?? []).map((v) => ({
      id: v.id,
      versionNumber: v.version_number,
      status: v.status,
      title: v.title,
      customerMessage: v.customer_message,
      subtotal: Number(v.subtotal),
      discount: Number(v.discount),
      tax: Number(v.tax),
      total: Number(v.total),
      currency: v.currency,
      validUntil: v.valid_until,
      sentAt: v.sent_at,
      lineItems: linesByVersion.get(v.id) ?? [],
    })),
    authorizedTotal,
  };
}

async function getWorkOrderAuthorizedTotal(workOrderId: string): Promise<number> {
  const supabase = await createClient();
  const { data } = await supabase.rpc('get_work_order_authorized_total', { p_work_order_id: workOrderId });
  return Number(data ?? 0);
}
