import 'server-only';
import { createClient } from '@/lib/supabase/server';

export interface WebsiteLeadRow {
  id: string;
  referenceCode: string;
  customerName: string | null;
  phone: string | null;
  email: string | null;
  country: string | null;
  region: string | null;
  city: string | null;
  serviceType: string | null;
  vesselMake: string | null;
  vesselModel: string | null;
  status: string;
  conversionStatus: string | null;
  conversionError: string | null;
  assignedOrganizationId: string | null;
  assignedOrganizationName: string | null;
  attemptCount: number;
  mediaCount: number;
  utmSource: string | null;
  utmMedium: string | null;
  utmCampaign: string | null;
  marineCloudCustomerId: string | null;
  marineCloudVesselId: string | null;
  marineCloudServiceRequestId: string | null;
  marineCloudWorkOrderId: string | null;
  createdAt: string;
}

const SELECT_FIELDS = `
  id, reference_code, customer_name, phone, email, country, region, city,
  service_type, vessel_make, vessel_model, status, conversion_status, conversion_error,
  assigned_organization_id, attempt_count, media_count, utm_source, utm_medium, utm_campaign,
  marine_cloud_customer_id, marine_cloud_vessel_id, marine_cloud_service_request_id, marine_cloud_work_order_id,
  created_at,
  organization:organizations!leads_assigned_organization_id_fkey(name)
`;

function mapRow(r: any): WebsiteLeadRow {
  const org = Array.isArray(r.organization) ? r.organization[0] : r.organization;
  return {
    id: r.id,
    referenceCode: r.reference_code,
    customerName: r.customer_name,
    phone: r.phone,
    email: r.email,
    country: r.country,
    region: r.region,
    city: r.city,
    serviceType: r.service_type,
    vesselMake: r.vessel_make,
    vesselModel: r.vessel_model,
    status: r.status,
    conversionStatus: r.conversion_status,
    conversionError: r.conversion_error,
    assignedOrganizationId: r.assigned_organization_id,
    assignedOrganizationName: org?.name ?? null,
    attemptCount: r.attempt_count,
    mediaCount: r.media_count,
    utmSource: r.utm_source,
    utmMedium: r.utm_medium,
    utmCampaign: r.utm_campaign,
    marineCloudCustomerId: r.marine_cloud_customer_id,
    marineCloudVesselId: r.marine_cloud_vessel_id,
    marineCloudServiceRequestId: r.marine_cloud_service_request_id,
    marineCloudWorkOrderId: r.marine_cloud_work_order_id,
    createdAt: r.created_at,
  };
}

export async function getWebsiteLeads(filter?: { conversionStatus?: string; organizationId?: string }): Promise<WebsiteLeadRow[]> {
  const supabase = await createClient();
  let query = supabase.from('leads').select(SELECT_FIELDS).eq('ingestion_source', 'kcc_website').order('created_at', { ascending: false }).limit(100);

  if (filter?.conversionStatus) query = query.eq('conversion_status', filter.conversionStatus);
  if (filter?.organizationId) query = query.eq('assigned_organization_id', filter.organizationId);

  const { data } = await query;
  return (data ?? []).map(mapRow);
}

export async function getWebsiteLeadCounts(): Promise<Record<string, number>> {
  const supabase = await createClient();
  const { data } = await supabase.from('leads').select('conversion_status').eq('ingestion_source', 'kcc_website');
  const counts: Record<string, number> = {};
  for (const row of data ?? []) {
    const key = row.conversion_status ?? 'not_converted';
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return counts;
}

export async function getActiveOrganizationsForRouting(): Promise<{ id: string; name: string }[]> {
  const supabase = await createClient();
  const { data } = await supabase.from('organizations').select('id, name').eq('status', 'active').order('name');
  return data ?? [];
}
