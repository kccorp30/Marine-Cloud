-- =========================================================
-- 085_payments_core_schema.sql — Marine Cloud Phase 7
-- =========================================================
-- Pago de primera clase, independiente de Stripe. amount_paid/status
-- de la invoice se derivan SIEMPRE de los pagos reales (status
-- 'settled', nunca reversed/failed) vía trigger. void nunca se pisa.
-- Verificado con 3 pagos parciales de métodos distintos, exacto:
-- $700/$300/partially_paid, luego $1000/$0/paid.
-- =========================================================

create table payments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  customer_id uuid not null,
  invoice_id uuid not null references invoices(id),
  work_order_id uuid references work_orders(id),
  amount numeric(12,2) not null check (amount > 0),
  currency text not null,
  method text not null check (method in ('stripe_card', 'zelle', 'cash', 'bank_transfer', 'check', 'other_manual')),
  status text not null default 'settled' check (status in ('pending', 'settled', 'failed', 'reversed')),
  provider text not null default 'manual' check (provider in ('stripe', 'manual')),
  provider_payment_id text,
  provider_account_id text,
  reference text,
  received_at timestamptz not null default now(),
  recorded_by uuid references profiles(id),
  source text not null default 'staff' check (source in ('staff', 'customer', 'system')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint fk_payments_customer_same_org foreign key (customer_id, organization_id) references customers(id, organization_id),
  constraint fk_payments_invoice_same_org foreign key (invoice_id, organization_id) references invoices(id, organization_id)
);

alter table payments add constraint uq_payments_id_org unique (id, organization_id);
alter table payments add constraint fk_payments_work_order_same_org
  foreign key (work_order_id, organization_id) references work_orders(id, organization_id) not valid;
alter table payments validate constraint fk_payments_work_order_same_org;

create index idx_payments_invoice on payments(invoice_id);
create index idx_payments_org_status on payments(organization_id, status, created_at desc);

create unique index uq_payments_provider_payment_id on payments(provider, provider_payment_id) where provider_payment_id is not null;

alter table payments enable row level security;

create policy "read_payments" on payments for select
using (is_kcc_admin() or is_org_staff(organization_id) or is_own_customer_record(customer_id));

revoke all on payments from anon, authenticated;
grant select on payments to authenticated;

create or replace function recalculate_invoice_paid_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invoice_id uuid;
  v_paid numeric;
  v_invoice invoices%rowtype;
begin
  v_invoice_id := coalesce(new.invoice_id, old.invoice_id);
  select * into v_invoice from invoices where id = v_invoice_id for update;

  if v_invoice.status = 'void' then
    return coalesce(new, old);
  end if;

  select coalesce(sum(amount), 0) into v_paid from payments
  where invoice_id = v_invoice_id and status = 'settled';

  update invoices set
    amount_paid = v_paid,
    status = case
      when v_paid >= total and total > 0 then 'paid'
      when v_paid > 0 then 'partially_paid'
      else status
    end,
    paid_at = case when v_paid >= total and total > 0 and paid_at is null then now() else paid_at end,
    updated_at = now()
  where id = v_invoice_id;

  return coalesce(new, old);
end;
$$;

create trigger trg_recalculate_invoice_paid_status
  after insert or update or delete on payments
  for each row execute function recalculate_invoice_paid_status();

revoke execute on function recalculate_invoice_paid_status() from public, anon, authenticated;
