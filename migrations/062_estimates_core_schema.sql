-- =========================================================
-- 062_estimates_core_schema.sql — Marine Cloud Phase 6
-- =========================================================
-- Hallazgo arquitectónico (paso 0 del brief, reportado): no existe
-- ningún ADR-007 en el repo ni en el sistema de archivos accesible —
-- se diseña este modelo desde cero, siguiendo la estructura
-- conceptual que el brief mismo detalla.
--
-- Hallazgo clave que SÍ reusa arquitectura existente: work_orders ya
-- tiene los estados 'estimate' y 'awaiting_approval' desde Phase 1,
-- con transiciones donde 'customer' es un rol permitido para
-- awaiting_approval -> scheduled (aprobar) y awaiting_approval ->
-- cancelled (rechazar). El flujo de aprobación de Phase 6 se apoya en
-- esto — transition_work_order() sigue siendo el único camino para
-- tocar current_status, nunca un UPDATE directo.
-- =========================================================

create table estimates (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  customer_id uuid not null,
  vessel_id uuid not null,
  work_order_id uuid references work_orders(id),
  service_request_id uuid references service_requests(id),
  estimate_number text not null,
  type text not null default 'estimate' check (type in ('estimate', 'change_order')),
  parent_estimate_id uuid references estimates(id),
  current_version_id uuid,
  status text not null default 'draft' check (status in ('draft', 'sent', 'viewed', 'approved', 'declined', 'expired', 'superseded', 'cancelled')),
  currency text not null,
  created_by uuid not null references profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint fk_estimates_customer_same_org foreign key (customer_id, organization_id) references customers(id, organization_id),
  constraint fk_estimates_vessel_same_org foreign key (vessel_id, organization_id) references vessels(id, organization_id),
  constraint uq_estimates_number unique (organization_id, estimate_number)
);

create index idx_estimates_org_status on estimates(organization_id, status, created_at desc);
create index idx_estimates_customer on estimates(customer_id, created_at desc);
create index idx_estimates_work_order on estimates(work_order_id);

create table estimate_versions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  estimate_id uuid not null references estimates(id),
  version_number int not null,
  status text not null default 'draft' check (status in ('draft', 'sent', 'viewed', 'approved', 'declined', 'expired', 'superseded')),
  title text,
  customer_message text,
  subtotal numeric(12,2) not null default 0,
  discount numeric(12,2) not null default 0,
  tax numeric(12,2) not null default 0,
  total numeric(12,2) not null default 0 check (total >= 0),
  currency text not null,
  valid_until date,
  created_by uuid not null references profiles(id),
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  superseded_at timestamptz,

  constraint uq_estimate_versions_number unique (estimate_id, version_number)
);

alter table estimates add constraint fk_estimates_current_version foreign key (current_version_id) references estimate_versions(id);

create index idx_estimate_versions_estimate on estimate_versions(estimate_id, version_number desc);

create table estimate_line_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  estimate_version_id uuid not null references estimate_versions(id) on delete cascade,
  service_catalog_id uuid references service_catalog(id),
  line_type text not null default 'service' check (line_type in ('labor', 'material', 'service', 'fee', 'discount', 'custom')),
  description text not null,
  quantity numeric(10,2) not null default 1 check (quantity > 0),
  unit_price numeric(12,2) not null default 0,
  line_total numeric(12,2) generated always as (round(quantity * unit_price, 2)) stored,
  sort_order int not null default 0,
  customer_visible boolean not null default true,
  created_at timestamptz not null default now()
);

create index idx_estimate_line_items_version on estimate_line_items(estimate_version_id, sort_order);

create table estimate_decisions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  estimate_id uuid not null references estimates(id),
  estimate_version_id uuid not null references estimate_versions(id),
  customer_id uuid not null,
  decision text not null check (decision in ('approved', 'declined')),
  decided_at timestamptz not null default now(),
  version_total_at_decision numeric(12,2) not null,
  customer_note text,

  constraint fk_estimate_decisions_customer_same_org foreign key (customer_id, organization_id) references customers(id, organization_id),
  constraint uq_estimate_decisions_version unique (estimate_version_id)
);

create table estimate_number_counters (
  organization_id uuid primary key references organizations(id),
  next_estimate_number int not null default 1,
  next_change_order_number int not null default 1
);

create or replace function generate_estimate_number(p_organization_id uuid, p_type text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_number int;
  v_prefix text;
begin
  insert into estimate_number_counters (organization_id) values (p_organization_id)
  on conflict (organization_id) do nothing;

  if p_type = 'change_order' then
    v_prefix := 'CO-';
    update estimate_number_counters set next_change_order_number = next_change_order_number + 1
    where organization_id = p_organization_id
    returning next_change_order_number - 1 into v_number;
  else
    v_prefix := 'EST-';
    update estimate_number_counters set next_estimate_number = next_estimate_number + 1
    where organization_id = p_organization_id
    returning next_estimate_number - 1 into v_number;
  end if;

  return v_prefix || lpad(v_number::text, 6, '0');
end;
$$;

revoke execute on function generate_estimate_number(uuid, text) from public, anon, authenticated;
