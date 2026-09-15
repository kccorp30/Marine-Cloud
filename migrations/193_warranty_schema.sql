-- =========================================================
-- 193_warranty_schema.sql — Marine Cloud Phase 13
-- =========================================================
-- warranties es un registro de negocio REAL, independiente de
-- work_orders.current_status='warranty'. Términos siempre
-- snapshoteados en starts_at/ends_at concretos al activar — nunca
-- recalculados desde configuración editada después.
-- =========================================================

alter table service_catalog add column warranty_enabled boolean not null default false;
alter table service_catalog add column warranty_duration_days int;
alter table service_catalog add column warranty_coverage_notes text;

create table warranties (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  work_order_id uuid not null references work_orders(id),
  customer_id uuid not null references customers(id),
  vessel_id uuid not null references vessels(id),
  status text not null default 'draft' check (status in ('draft', 'active', 'expired', 'voided')),
  coverage_type text not null default 'workmanship',
  coverage_notes text,
  starts_at date,
  ends_at date,
  created_by uuid references profiles(id),
  activated_at timestamptz,
  expired_at timestamptz,
  voided_at timestamptz,
  void_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_warranties_work_order on warranties(work_order_id);
create index idx_warranties_customer on warranties(customer_id);
create index idx_warranties_vessel on warranties(vessel_id);
create index idx_warranties_org on warranties(organization_id);
create index idx_warranties_ends_at on warranties(ends_at);

create trigger trg_warranties_updated_at before update on warranties
  for each row execute function set_updated_at();

create table warranty_claims (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  warranty_id uuid not null references warranties(id),
  customer_id uuid not null references customers(id),
  vessel_id uuid not null references vessels(id),
  original_work_order_id uuid not null references work_orders(id),
  claim_work_order_id uuid references work_orders(id),
  status text not null default 'submitted' check (status in ('submitted', 'under_review', 'approved', 'rejected', 'in_progress', 'resolved', 'cancelled')),
  reason text not null,
  description text,
  submitted_at timestamptz not null default now(),
  reviewed_by uuid references profiles(id),
  reviewed_at timestamptz,
  decision_reason text,
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_warranty_claims_warranty on warranty_claims(warranty_id);
create index idx_warranty_claims_org on warranty_claims(organization_id);
create index idx_warranty_claims_customer on warranty_claims(customer_id);

create trigger trg_warranty_claims_updated_at before update on warranty_claims
  for each row execute function set_updated_at();
