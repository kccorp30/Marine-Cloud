import 'server-only';
import { createClient as createServiceClient } from '@/lib/supabase/service';
import { getEmailProvider } from '@/lib/email/resend';
import { getSiteUrl } from '@/lib/auth/site-url';
import { logger } from '@/lib/logger';

function escape(v: unknown) {
  return String(v ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function renderInternalAlertEmail({
  title,
  body,
  actionLabel,
  actionUrl,
  organizationName,
}: {
  title: string;
  body: string;
  actionLabel: string;
  actionUrl: string;
  organizationName: string;
}) {
  return `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head><body style="margin:0;background:#06111d;font-family:Arial,Helvetica,sans-serif"><table width="100%" cellpadding="0" cellspacing="0" role="presentation" style="background:#06111d;background-image:radial-gradient(circle at 78% 0%,rgba(51,136,230,.24),transparent 34%),radial-gradient(circle at 4% 100%,rgba(226,192,109,.13),transparent 28%)"><tr><td align="center" style="padding:30px 12px"><table width="600" cellpadding="0" cellspacing="0" role="presentation" style="max-width:600px;width:100%;background:#0a1a29;border:1px solid rgba(155,195,230,.2);border-radius:24px;overflow:hidden"><tr><td style="padding:30px;background:linear-gradient(145deg,#0b2238,#123d5e);border-bottom:2px solid #d9b96b"><p style="margin:0;color:#8ed6ff;font-size:11px;letter-spacing:2.8px">LUZ · KCC MARINE CLOUD</p><h1 style="margin:14px 0 0;color:#fff;font-size:28px;line-height:1.2">${escape(title)}</h1></td></tr><tr><td style="padding:30px;color:#dfeaf2"><p style="margin:0 0 8px;color:#84a1b7;font-size:11px;letter-spacing:1.8px;text-transform:uppercase">${escape(organizationName)}</p><p style="font-size:15px;line-height:1.75;margin:0;color:#e4eef6">${escape(body)}</p><div style="margin:24px 0;padding:16px 18px;border-radius:15px;background:rgba(226,192,109,.08);border:1px solid rgba(226,192,109,.22);color:#ead59d;font-size:13px;line-height:1.6">Luz detected an operational event that may require your attention. The complete record remains inside the secure workspace.</div><p style="text-align:center;margin:28px 0 14px"><a href="${escape(actionUrl)}" style="display:inline-block;background:linear-gradient(135deg,#e1bd68,#efd48c);color:#071522;text-decoration:none;font-weight:800;padding:16px 28px;border-radius:13px">${escape(actionLabel)} →</a></p><p style="margin:0;text-align:center;color:#7f9aaf;font-size:12px">Open Marine Cloud to review and continue the workflow.</p></td></tr><tr><td style="padding:18px 30px;background:#07131f;color:#6f899d;text-align:center;font-size:10px;letter-spacing:1.6px">KCC MARINE CLOUD · OPERATIONAL INTELLIGENCE</td></tr></table></td></tr></table></body></html>`;
}

const PLATFORM_FROM = () =>
  process.env.AUTH_FROM_EMAIL ||
  process.env.RESEND_FROM_EMAIL ||
  process.env.EMAIL_FROM_ADDRESS ||
  'KCC Marine Cloud <notifications@kccorpglobal.com>';

export async function emailCompanyOperationalAlert(input: {
  organizationId: string;
  eventKey: string;
  title: string;
  body: string;
  actionPath: string;
  actionLabel: string;
}) {
  const db = createServiceClient();
  const [{ data: org }, { data: memberships }] = await Promise.all([
    db.from('organizations').select('name').eq('id', input.organizationId).maybeSingle(),
    db
      .from('organization_memberships')
      .select('profile_id,role,profile:profiles(email,full_name,preferred_language)')
      .eq('organization_id', input.organizationId)
      .eq('status', 'active')
      .in('role', ['company_owner', 'company_admin', 'manager']),
  ]);
  const actionUrl = `${getSiteUrl()}${input.actionPath.startsWith('/') ? input.actionPath : `/${input.actionPath}`}`;
  const organizationName = org?.name ?? 'Marine Cloud';
  const provider = (() => {
    try { return getEmailProvider(); } catch { return null; }
  })();
  if (!provider) return { sent: 0, failed: (memberships ?? []).length };

  let sent = 0;
  let failed = 0;
  for (const row of memberships ?? []) {
    const profile = Array.isArray(row.profile) ? row.profile[0] : row.profile;
    if (!profile?.email) continue;
    const result = await provider.sendEmail({
      to: profile.email,
      from: PLATFORM_FROM(),
      subject: `Luz · ${input.title}`,
      text: `${input.title}\n\n${input.body}\n\n${input.actionLabel}: ${actionUrl}`,
      html: renderInternalAlertEmail({
        title: input.title,
        body: input.body,
        actionLabel: input.actionLabel,
        actionUrl,
        organizationName,
      }),
      idempotencyKey: `${input.eventKey}:${row.profile_id}`.slice(0, 240),
    });
    if (result.success) sent += 1;
    else {
      failed += 1;
      logger.warn('operational alert email failed', { eventKey: input.eventKey, recipient: row.profile_id, error: result.error });
    }
  }
  return { sent, failed };
}

export async function emailUserOperationalAlert(input: {
  userId: string;
  eventKey: string;
  title: string;
  body: string;
  actionPath: string;
  actionLabel: string;
}) {
  const db = createServiceClient();
  const { data: profile } = await db.from('profiles').select('email,full_name').eq('id', input.userId).maybeSingle();
  if (!profile?.email) return { sent: false };
  let provider;
  try { provider = getEmailProvider(); } catch { return { sent: false }; }
  const actionUrl = `${getSiteUrl()}${input.actionPath.startsWith('/') ? input.actionPath : `/${input.actionPath}`}`;
  const result = await provider.sendEmail({
    to: profile.email,
    from: PLATFORM_FROM(),
    subject: `Luz · ${input.title}`,
    text: `${input.title}\n\n${input.body}\n\n${input.actionLabel}: ${actionUrl}`,
    html: renderInternalAlertEmail({ title: input.title, body: input.body, actionLabel: input.actionLabel, actionUrl, organizationName: 'KCC Marine Cloud' }),
    idempotencyKey: `${input.eventKey}:${input.userId}`.slice(0, 240),
  });
  return { sent: result.success };
}
