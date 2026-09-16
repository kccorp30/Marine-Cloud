import 'server-only';
import { createClient } from '@/lib/supabase/server';

export interface KccAccountSummary {
  agreement: null | {
    id: string;
    compensation_type: 'percentage' | 'fixed';
    percentage_rate: number | null;
    fixed_amount: number | null;
    currency: string;
    effective_from: string;
    effective_until: string | null;
    notes: string | null;
  };
  subscription: null | {
    id: string;
    status: string;
    billing_cycle: string;
    currency: string;
    price_snapshot: number | null;
    current_period_ends_at: string | null;
    complimentary: boolean;
    custom_terms: string | null;
  };
  balance: {
    currency: string;
    open_balance: number;
    open_charges: number;
    overdue_charges: number;
    next_due_at: string | null;
  };
}

export async function getCompanyKccAccountSummary(organizationId: string): Promise<KccAccountSummary | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('get_company_kcc_account_summary', { p_org: organizationId });
  if (error || !data) return null;
  return data as KccAccountSummary;
}
