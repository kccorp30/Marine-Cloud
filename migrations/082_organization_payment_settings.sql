-- =========================================================
-- 082_organization_payment_settings.sql — Marine Cloud Phase 7
-- =========================================================
-- Depósito configurable (nunca hardcodeado 50/50), métodos aceptados
-- como array extensible, instrucciones manuales customer-facing.
-- =========================================================

create table organization_payment_settings (
  organization_id uuid primary key references organizations(id),

  deposit_required boolean not null default false,
  deposit_type text not null default 'percentage' check (deposit_type in ('percentage', 'fixed_amount')),
  deposit_value numeric(12,2) not null default 0 check (deposit_value >= 0),
  constraint chk_deposit_percentage_range check (deposit_type != 'percentage' or deposit_value <= 100),

  remaining_balance_due text not null default 'on_completion' check (remaining_balance_due in ('on_completion', 'before_delivery', 'custom_date')),
  require_deposit_before_start boolean not null default false,

  stripe_connect_enabled boolean not null default false,
  manual_payments_enabled boolean not null default true,
  accepted_payment_methods text[] not null default array['cash', 'zelle', 'bank_transfer', 'check']::text[],

  zelle_recipient_name text,
  zelle_contact text,
  zelle_instructions text,
  bank_transfer_instructions text,
  cash_instructions text,
  check_payable_to text,
  check_instructions text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table organization_payment_settings enable row level security;

create policy "read_payment_settings" on organization_payment_settings for select
using (is_kcc_admin() or is_org_member(organization_id));

revoke all on organization_payment_settings from anon, authenticated;
grant select on organization_payment_settings to authenticated;

create or replace function update_payment_settings(
  p_organization_id uuid,
  p_deposit_required boolean default null,
  p_deposit_type text default null,
  p_deposit_value numeric default null,
  p_remaining_balance_due text default null,
  p_require_deposit_before_start boolean default null,
  p_manual_payments_enabled boolean default null,
  p_accepted_payment_methods text[] default null,
  p_zelle_recipient_name text default null,
  p_zelle_contact text default null,
  p_zelle_instructions text default null,
  p_bank_transfer_instructions text default null,
  p_cash_instructions text default null,
  p_check_payable_to text default null,
  p_check_instructions text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (is_kcc_admin() or is_org_staff(p_organization_id)) then
    raise exception 'not authorized';
  end if;

  insert into organization_payment_settings (organization_id) values (p_organization_id)
  on conflict (organization_id) do nothing;

  update organization_payment_settings set
    deposit_required = coalesce(p_deposit_required, deposit_required),
    deposit_type = coalesce(p_deposit_type, deposit_type),
    deposit_value = coalesce(p_deposit_value, deposit_value),
    remaining_balance_due = coalesce(p_remaining_balance_due, remaining_balance_due),
    require_deposit_before_start = coalesce(p_require_deposit_before_start, require_deposit_before_start),
    manual_payments_enabled = coalesce(p_manual_payments_enabled, manual_payments_enabled),
    accepted_payment_methods = coalesce(p_accepted_payment_methods, accepted_payment_methods),
    zelle_recipient_name = coalesce(p_zelle_recipient_name, zelle_recipient_name),
    zelle_contact = coalesce(p_zelle_contact, zelle_contact),
    zelle_instructions = coalesce(p_zelle_instructions, zelle_instructions),
    bank_transfer_instructions = coalesce(p_bank_transfer_instructions, bank_transfer_instructions),
    cash_instructions = coalesce(p_cash_instructions, cash_instructions),
    check_payable_to = coalesce(p_check_payable_to, check_payable_to),
    check_instructions = coalesce(p_check_instructions, check_instructions),
    updated_at = now()
  where organization_id = p_organization_id;
end;
$$;

revoke execute on function update_payment_settings(uuid, boolean, text, numeric, text, boolean, boolean, text[], text, text, text, text, text, text, text) from public, anon;
grant execute on function update_payment_settings(uuid, boolean, text, numeric, text, boolean, boolean, text[], text, text, text, text, text, text, text) to authenticated;

create or replace function calculate_deposit_amount(p_authorized_total numeric, p_deposit_type text, p_deposit_value numeric)
returns numeric
language sql
immutable
as $$
  select case
    when p_deposit_type = 'percentage' then round(p_authorized_total * p_deposit_value / 100.0, 2)
    else least(p_deposit_value, p_authorized_total)
  end;
$$;
