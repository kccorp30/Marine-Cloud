import 'server-only';
import {renderEstimateEmail} from '@/lib/email/estimate-template';
import {getLocale} from '@/lib/i18n/server';
import {workspaceCopy} from '@/lib/i18n/workspace-copy';
import { createHash } from 'node:crypto';
import { createClient } from '@/lib/supabase/server';
import { getSessionContext } from '@/lib/auth/session';
import { getActiveOrganizationId } from '@/lib/auth/active-org';
import { getEstimateDetail } from './data';
import { renderOperationalEmail } from '@/lib/email/operational-template';
import { getSiteUrl } from '@/lib/auth/site-url';

export async function loadEstimatePreview(estimateId: string, intro: string) {
  const session = await getSessionContext();
  const orgId = await getActiveOrganizationId(session.memberships);
  const role = session.memberships.find(m => m.organization_id === orgId)?.role;
  if (!session.isKccAdmin && !['company_owner','company_admin','manager'].includes(role ?? '')) throw new Error('Not authorized');
  const db = await createClient();
  const {data: row, error} = await db.from('estimates').select('organization_id, customer:customers(first_name,email,profile_id), organization:organizations(name,branding_json)').eq('id', estimateId).eq('organization_id', orgId).maybeSingle();
  if(error || !row) throw new Error('Estimate not found');
  const detail = await getEstimateDetail(estimateId);
  const version = detail?.versions.find(v => v.id === detail.currentVersionId);
  if(!detail || !version) throw new Error('Estimate version not found');
  const customer = Array.isArray(row.customer) ? row.customer[0] : row.customer;
  const organization = Array.isArray(row.organization) ? row.organization[0] : row.organization;
  const {data: settings,error:settingsError} = await db.from('organization_email_settings').select('sender_email,sender_name,signature_text,enabled').eq('organization_id',orgId).maybeSingle();
  const label = detail.type === 'change_order' ? 'Change Order ' : 'Estimate ';
  // Mirrors the existing server-rendered commercial RPC. No client-supplied totals.
  const valid = version.validUntil ? new Date(`${version.validUntil}T12:00:00Z`).toLocaleDateString('en-US',{month:'long',day:'2-digit',year:'numeric',timeZone:'UTC'}) : '';
  const currency = String(version.currency || 'USD').toUpperCase();
  const amount = new Intl.NumberFormat('en-US',{style:'currency',currency,minimumFractionDigits:2,maximumFractionDigits:2}).format(Number(version.total));
  const body = (customer?.first_name != null ? `Hi ${customer.first_name},\n\n` : '') + (intro.trim() ? `${intro}\n\n` : '') + label + detail.estimateNumber + `\nTotal: ${amount}\n` + (valid ? `Valid until: ${valid}\n` : '') + '\nPlease log in to Marine Cloud to review and respond.\n\n' + (organization?.name ?? '');
 const destination=`/estimates/${estimateId}`;
 const portalUrl=`${getSiteUrl()}/login?next=${encodeURIComponent(destination)}`;
 const html = renderEstimateEmail({estimate:detail,version,company:organization?.name??'KCC Marine Cloud',logo:organization?.branding_json?.logo_url,intro,signature:settings?.signature_text,portalUrl});
  const fingerprint = createHash('sha256').update(JSON.stringify({id:detail.id, version, intro, recipient:customer?.email,settings})).digest('hex');
  const t=workspaceCopy[await getLocale()];
  const issues=[!customer?.email?t.missingEmail:null,settingsError?t.settingsUnavailable:!settings?.sender_email?t.missingSender:!settings.enabled?t.disabledSender:null,!process.env.RESEND_API_KEY?t.missingProvider:null].filter((v):v is string=>!!v);
  return {issues,html, fingerprint, recipient:customer?.email ?? null, subject:label+detail.estimateNumber+' Ready for Review', canSend:!!customer?.email && !!settings?.enabled && !!settings.sender_email && !!process.env.RESEND_API_KEY, version, detail, organization, organizationId: row.organization_id as string, settings, customerProfileId: customer?.profile_id ?? null};
}
