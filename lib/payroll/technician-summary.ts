import 'server-only';
import { createClient } from '@/lib/supabase/server';

export interface TechnicianPaySnapshot {
  payType: 'hourly' | 'daily' | null;
  payRate: number | null;
  currency: string;
  payCycle: string | null;
  currentShift: null | { id: string; startedAt: string; pausedAt: string | null; breakSeconds: number };
  unpaidAmount: number;
  unpaidShifts: number;
  lastPaidAt: string | null;
}

export async function getTechnicianPaySnapshot(organizationId: string, profileId: string): Promise<TechnicianPaySnapshot> {
  const db = await createClient();
  const [{ data: terms }, { data: shifts }, { data: payments }] = await Promise.all([
    db.from('technician_pay_terms').select('pay_type,pay_rate,currency,pay_cycle').eq('organization_id', organizationId).eq('profile_id', profileId).maybeSingle(),
    db.from('technician_shifts').select('id,started_at,ended_at,paused_at,break_seconds,gross_amount,currency').eq('organization_id', organizationId).eq('profile_id', profileId).order('started_at', { ascending: false }).limit(90),
    db.from('technician_payments').select('shift_id,paid_at').eq('organization_id', organizationId).eq('profile_id', profileId).order('paid_at', { ascending: false }).limit(90),
  ]);
  const paid = new Set((payments ?? []).map((p) => p.shift_id));
  const unpaid = (shifts ?? []).filter((s) => s.ended_at && s.gross_amount != null && !paid.has(s.id));
  const open = (shifts ?? []).find((s) => !s.ended_at) ?? null;
  return {
    payType: (terms?.pay_type as 'hourly' | 'daily' | undefined) ?? null,
    payRate: terms?.pay_rate == null ? null : Number(terms.pay_rate),
    currency: terms?.currency ?? open?.currency ?? 'USD',
    payCycle: terms?.pay_cycle ?? null,
    currentShift: open ? { id: open.id, startedAt: open.started_at, pausedAt: open.paused_at, breakSeconds: Number(open.break_seconds ?? 0) } : null,
    unpaidAmount: unpaid.reduce((sum, s) => sum + Number(s.gross_amount ?? 0), 0),
    unpaidShifts: unpaid.length,
    lastPaidAt: payments?.[0]?.paid_at ?? null,
  };
}
