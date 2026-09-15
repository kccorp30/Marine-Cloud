-- =========================================================
-- 080_invoices_core_schema.sql — Marine Cloud Phase 7
-- =========================================================
-- Paso 0 (reportado): no existe ningún invoice/payment/stripe/ledger
-- previo en el repo. Hallazgo real que SÍ reusa arquitectura
-- existente: work_orders ya tiene los estados 'invoice' y 'payment'
-- desde Phase 1, con 'customer' como rol permitido en
-- invoice -> payment — exactamente el mismo patrón de Phase 6
-- (awaiting_approval -> scheduled). El pago completo de una invoice
-- dispara esa transición vía transition_work_order(), nunca un
-- UPDATE directo.
--
-- Hardening aplicado desde el día uno (aprendido de Phase 4B/5/6):
-- ninguna mutación directa jamás — todo detrás de funciones, money
-- nunca negativo, FKs compuestas tenant-safe desde el inicio.
-- =========================================================

create table invoices (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  customer_id uuid not null,
  vessel_id uuid not null,
  work_order_id uuid references work_orders(id),
  estimate_id uuid references estimates(id),
  invoice_number text not null,
  invoice_type text not null default 'standalone' check (invoice_type in ('deposit', 'progress', 'final', 'standalone')),
  status text not null default 'draft' check (status in ('draft', 'issued', 'sent', 'partially_paid', 'paid', 'overdue', 'void')),
  currency text not null,
  issue_date date not null default current_date,
  due_date date,
  subtotal numeric(12,2) not null default 0,
  discount numeric(12,2) not null default 0,
  tax numeric(12,2) not null default 0 check (tax >= 0),
  total numeric(12,2) not null default 0 check (total >= 0),
  amount_paid numeric(12,2) not null default 0 check (amount_paid >= 0),
  created_by uuid not null references profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  sent_at timestamptz,
  paid_at timestamptz,
  voided_at timestamptz,
  voided_by uuid references profiles(id),
  void_reason text,

  constraint fk_invoices_customer_same_org foreign key (customer_id, organization_id) references customers(id, organization_id),
  constraint fk_invoices_vessel_same_org foreign key (vessel_id, organization_id) references vessels(id, organization_id),
  constraint uq_invoices_number unique (organization_id, invoice_number),
  constraint chk_amount_paid_not_exceed_total check (amount_paid <= total)
);

alter table invoices add column balance_due numeric(12,2) generated always as (greatest(total - amount_paid, 0)) stored;

create index idx_invoices_org_status on invoices(organization_id, status, created_at desc);
create index idx_invoices_customer on invoices(customer_id, created_at desc);
create index idx_invoices_work_order on invoices(work_order_id);

alter table invoices add constraint uq_invoices_id_org unique (id, organization_id);
alter table invoices add constraint fk_invoices_work_order_same_org
  foreign key (work_order_id, organization_id) references work_orders(id, organization_id) not valid;
alter table invoices add constraint fk_invoices_estimate_same_org
  foreign key (estimate_id, organization_id) references estimates(id, organization_id) not valid;
alter table invoices validate constraint fk_invoices_work_order_same_org;
alter table invoices validate constraint fk_invoices_estimate_same_org;

create table invoice_line_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  invoice_id uuid not null references invoices(id) on delete cascade,
  source_estimate_line_item_id uuid references estimate_line_items(id),
  source_change_order_id uuid references estimates(id),
  description text not null,
  quantity numeric(10,2) not null default 1 check (quantity > 0),
  unit_price numeric(12,2) not null default 0 check (unit_price >= 0),
  line_total numeric(12,2) generated always as (round(quantity * unit_price, 2)) stored,
  sort_order int not null default 0,
  line_type text not null default 'service' check (line_type in ('labor', 'material', 'service', 'fee', 'discount', 'custom')),
  customer_visible boolean not null default true,
  created_at timestamptz not null default now()
);

create index idx_invoice_line_items_invoice on invoice_line_items(invoice_id, sort_order);
alter table invoice_line_items add constraint fk_line_items_invoice_same_org
  foreign key (invoice_id, organization_id) references invoices(id, organization_id) not valid;
alter table invoice_line_items validate constraint fk_line_items_invoice_same_org;

create table invoice_number_counters (
  organization_id uuid primary key references organizations(id),
  next_invoice_number int not null default 1
);

create or replace function generate_invoice_number(p_organization_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_number int;
begin
  insert into invoice_number_counters (organization_id) values (p_organization_id)
  on conflict (organization_id) do nothing;

  update invoice_number_counters set next_invoice_number = next_invoice_number + 1
  where organization_id = p_organization_id
  returning next_invoice_number - 1 into v_number;

  return 'INV-' || lpad(v_number::text, 6, '0');
end;
$$;

revoke execute on function generate_invoice_number(uuid) from public, anon, authenticated;

alter table invoices enable row level security;
alter table invoice_line_items enable row level security;
alter table invoice_number_counters enable row level security;

create policy "read_invoices" on invoices for select
using (
  is_kcc_admin()
  or is_org_staff(organization_id)
  or (is_own_customer_record(customer_id) and status != 'draft')
);

revoke all on invoices from anon, authenticated;
grant select on invoices to authenticated;

create policy "read_invoice_line_items" on invoice_line_items for select
using (
  is_kcc_admin()
  or exists (select 1 from invoices i where i.id = invoice_line_items.invoice_id and is_org_staff(i.organization_id))
  or (
    customer_visible = true
    and exists (
      select 1 from invoices i
      where i.id = invoice_line_items.invoice_id and i.status != 'draft' and is_own_customer_record(i.customer_id)
    )
  )
);

revoke all on invoice_line_items from anon, authenticated;
grant select on invoice_line_items to authenticated;

revoke all on invoice_number_counters from anon, authenticated;
