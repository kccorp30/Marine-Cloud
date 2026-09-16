-- =========================================================
-- 019_work_orders_and_related.sql — Marine Cloud Phase 1
-- =========================================================

-- ---------------------------------------------------------
-- work_orders
-- ---------------------------------------------------------
create table work_orders (
  id                 uuid primary key default gen_random_uuid(),
  organization_id    uuid not null references organizations(id),
  customer_id        uuid not null references customers(id),
  vessel_id          uuid not null references vessels(id),
  service_id         uuid references service_catalog(id),
  title              text not null,
  description        text,
  priority           text not null default 'normal' check (priority in ('low','normal','high','urgent')),
  current_status     text not null default 'request_received' check (current_status in (
    'request_received','triage','estimate','awaiting_approval','scheduled',
    'technician_assigned','en_route','checked_in','diagnosis','work_in_progress',
    'waiting_parts','waiting_customer_approval','quality_control','invoice',
    'payment','completed','warranty','cancelled'
  )),
  source             text not null default 'internal' check (source in ('internal','website','referral','kcc_generated','other')),
  kcc_generated      boolean not null default false,  -- atribución futura de comisión (Phase 6-8), preparado, no funcional aún
  website_lead_id    uuid,  -- futuro puente Phase 10 — sin FK todavía (leads vive en el dominio del sitio, no en Marine Cloud)
  created_by         uuid references profiles(id),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  closed_at          timestamptz
);

create index idx_work_orders_org on work_orders(organization_id);
create index idx_work_orders_customer on work_orders(customer_id);
create index idx_work_orders_vessel on work_orders(vessel_id);
create index idx_work_orders_status on work_orders(organization_id, current_status);

create trigger trg_work_orders_updated_at before update on work_orders for each row execute function set_updated_at();
alter table work_orders enable row level security;

-- Columna current_status/closed_at solo modificables por la función de
-- transición (SECURITY DEFINER) — ver 020_work_order_transition_function.sql.
revoke update (current_status, closed_at) on work_orders from authenticated;

-- ---------------------------------------------------------
-- work_order_status_history — inmutable
-- ---------------------------------------------------------
create table work_order_status_history (
  id                uuid primary key default gen_random_uuid(),
  work_order_id     uuid not null references work_orders(id),
  organization_id   uuid not null references organizations(id),
  from_status       text,
  to_status         text not null,
  actor_profile_id  uuid references profiles(id),
  occurred_at       timestamptz not null default now(),
  reason            text,
  metadata          jsonb not null default '{}'::jsonb
);

create index idx_wo_status_history_wo on work_order_status_history(work_order_id, occurred_at);
alter table work_order_status_history enable row level security;
-- Sin policy de INSERT/UPDATE/DELETE — se escribe únicamente desde
-- transition_work_order() (SECURITY DEFINER).

-- ---------------------------------------------------------
-- work_order_transition_rules — catálogo global (no por tenant, MVP)
-- ---------------------------------------------------------
create table work_order_transition_rules (
  id                 uuid primary key default gen_random_uuid(),
  from_status        text not null,
  to_status          text not null,
  allowed_roles      text[] not null,
  active             boolean not null default true,
  condition_metadata jsonb
);

create unique index uq_transition_rule on work_order_transition_rules(from_status, to_status);
alter table work_order_transition_rules enable row level security;
create policy "authenticated_read_transition_rules" on work_order_transition_rules for select
  using (auth.uid() is not null);

-- ---------------------------------------------------------
-- appointments — Work Order ≠ Appointment
-- ---------------------------------------------------------
create table appointments (
  id                uuid primary key default gen_random_uuid(),
  organization_id   uuid not null references organizations(id),
  work_order_id     uuid not null references work_orders(id),
  location_id       uuid references organization_locations(id),
  scheduled_start   timestamptz not null,
  scheduled_end     timestamptz,
  actual_start      timestamptz,
  actual_end        timestamptz,
  status            text not null default 'scheduled' check (status in ('scheduled','in_progress','completed','cancelled','rescheduled')),
  purpose           text,
  notes             text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index idx_appointments_org on appointments(organization_id);
create index idx_appointments_wo on appointments(work_order_id);
create index idx_appointments_schedule on appointments(organization_id, scheduled_start);

create trigger trg_appointments_updated_at before update on appointments for each row execute function set_updated_at();
alter table appointments enable row level security;

-- ---------------------------------------------------------
-- assignments — técnicos separados del work order, soporta múltiples
-- ---------------------------------------------------------
create table assignments (
  id                      uuid primary key default gen_random_uuid(),
  organization_id         uuid not null references organizations(id),
  work_order_id           uuid not null references work_orders(id),
  appointment_id          uuid references appointments(id),
  technician_profile_id   uuid not null references profiles(id),
  role_on_job             text,
  assigned_at             timestamptz not null default now(),
  removed_at              timestamptz,
  status                  text not null default 'active' check (status in ('active','removed')),
  assigned_by             uuid references profiles(id)
);

create index idx_assignments_org on assignments(organization_id);
create index idx_assignments_wo on assignments(work_order_id);
create index idx_assignments_technician on assignments(technician_profile_id, status);

alter table assignments enable row level security;
