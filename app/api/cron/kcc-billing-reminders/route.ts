import { NextRequest, NextResponse } from 'next/server';
import { timingSafeEqual } from 'node:crypto';
import { createClient } from '@/lib/supabase/service';
import { emailCompanyOperationalAlert } from '@/lib/notifications/operational-email';

function authorized(request: NextRequest) {
  const secret = process.env.CRON_SECRET;
  const incoming = request.headers.get('authorization') || '';
  const expected = `Bearer ${secret}`;
  return !!secret && Buffer.byteLength(incoming) === Buffer.byteLength(expected) && timingSafeEqual(Buffer.from(incoming), Buffer.from(expected));
}

function daysUntil(iso: string) {
  return Math.ceil((new Date(iso).getTime() - Date.now()) / 86_400_000);
}

export async function GET(request: NextRequest) {
  if (!authorized(request)) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  if (!process.env.RESEND_API_KEY) return NextResponse.json({ error: 'RESEND_API_KEY is missing' }, { status: 503 });

  const db = createClient();
  const horizon = new Date(Date.now() + 4 * 86_400_000).toISOString();
  const { data: charges, error } = await db
    .from('platform_billing_charges')
    .select('id,organization_id,due_at,currency,balance_due,status,description')
    .not('status', 'in', '(paid,void)')
    .gt('balance_due', 0)
    .lte('due_at', horizon)
    .order('due_at', { ascending: true })
    .limit(100);

  if (error) return NextResponse.json({ error: 'Could not load KCC billing reminders' }, { status: 500 });

  let emailed = 0;
  let inApp = 0;
  let skipped = 0;

  for (const charge of charges ?? []) {
    if (!charge.due_at) continue;
    const delta = daysUntil(charge.due_at);
    const stage = delta < 0 ? 'OVERDUE' : delta <= 0 ? 'DUE_TODAY' : delta <= 3 ? 'DUE_SOON' : null;
    if (!stage) continue;

    const eventType = `KCC_BILLING_${stage}`;
    const { data: existing } = await db
      .from('notifications')
      .select('id')
      .eq('organization_id', charge.organization_id)
      .eq('event_type', eventType)
      .eq('related_entity_type', 'platform_billing_charge')
      .eq('related_entity_id', charge.id)
      .limit(1);
    if (existing?.length) { skipped += 1; continue; }

    const [{ data: org }, { data: memberships }] = await Promise.all([
      db.from('organizations').select('name').eq('id', charge.organization_id).maybeSingle(),
      db.from('organization_memberships').select('profile_id,role').eq('organization_id', charge.organization_id).eq('status', 'active').in('role', ['company_owner', 'company_admin']),
    ]);

    const currency = charge.currency || 'USD';
    const amount = new Intl.NumberFormat('en-US', { style: 'currency', currency }).format(Number(charge.balance_due || 0));
    const title = stage === 'OVERDUE' ? 'KCC payment overdue' : stage === 'DUE_TODAY' ? 'KCC payment due today' : 'Upcoming KCC payment';
    const body = stage === 'OVERDUE'
      ? `${org?.name ?? 'Your company'} has an outstanding KCC balance of ${amount}. Open billing to review the agreement and payment details.`
      : `${org?.name ?? 'Your company'} has a KCC balance of ${amount} due ${new Date(charge.due_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}.`;

    const rows = (memberships ?? []).map((membership) => ({
      organization_id: charge.organization_id,
      recipient_user_id: membership.profile_id,
      event_type: eventType,
      severity: stage === 'OVERDUE' ? 'urgent' : 'action_required',
      title,
      body,
      related_entity_type: 'platform_billing_charge',
      related_entity_id: charge.id,
      acknowledgement_required: true,
      delivery_channels: ['in_app'],
      delivery_status: 'delivered',
    }));
    if (rows.length) {
      const { error: notifyError } = await db.from('notifications').insert(rows);
      if (!notifyError) inApp += rows.length;
    }

    const result = await emailCompanyOperationalAlert({
      organizationId: charge.organization_id,
      eventKey: `kcc-billing:${stage}:${charge.id}`,
      title,
      body,
      actionPath: '/billing',
      actionLabel: 'Review KCC account',
    });
    emailed += result.sent;
  }

  return NextResponse.json({ charges: charges?.length ?? 0, inApp, emailed, skipped });
}
