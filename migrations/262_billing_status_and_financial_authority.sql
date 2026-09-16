-- =========================================================
-- 262_billing_status_and_financial_authority.sql — Marine Cloud Phase 15
-- =========================================================
create or replace function calculate_charge_effective_status(p_status text, p_balance_due numeric, p_amount_paid numeric, p_total_amount numeric, p_due_at timestamptz)
returns text
language sql
stable
as $$
  select case
    when p_status = 'void' then 'void'
    when p_balance_due <= 0 then 'paid'
    when p_amount_paid > 0 and p_amount_paid < p_total_amount then
      case when now() > p_due_at then 'overdue' else 'partially_paid' end
    when p_amount_paid = 0 and now() > p_due_at then 'overdue'
    else 'open'
  end;
$$;

create or replace function organization_billing_is_current(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select not exists (
    select 1 from platform_billing_charges c
    where c.organization_id = p_organization_id
      and calculate_charge_effective_status(c.status, c.balance_due, c.amount_paid, c.total_amount, c.due_at) = 'overdue'
  );
$$;

revoke execute on function organization_billing_is_current(uuid) from public, anon;
grant execute on function organization_billing_is_current(uuid) to authenticated;

create or replace view platform_billing_charges_effective as
select c.*, calculate_charge_effective_status(c.status, c.balance_due, c.amount_paid, c.total_amount, c.due_at) as effective_status
from platform_billing_charges c;

alter view platform_billing_charges_effective set (security_invoker = true);
