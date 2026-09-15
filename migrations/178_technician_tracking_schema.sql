-- =========================================================
-- 178_technician_tracking_schema.sql — Marine Cloud Phase 12
-- =========================================================
-- Tracking atado a assignment/work_order — nunca vigilancia general
-- de empleados. Sesión válida solo mientras current_status='en_route'
-- (según work_order_transition_rules existente). Al salir de en_route
-- la sesión se invalida automáticamente (ver 180).
-- =========================================================

create table technician_tracking_sessions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  technician_profile_id uuid not null references profiles(id),
  work_order_id uuid not null references work_orders(id),
  assignment_id uuid not null references assignments(id),
  status text not null default 'active' check (status in ('active', 'paused', 'stopped', 'expired')),
  started_at timestamptz not null default now(),
  stopped_at timestamptz,
  last_location_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index uq_tracking_session_active_per_wo
  on technician_tracking_sessions(technician_profile_id, work_order_id)
  where status in ('active', 'paused');

create index idx_tracking_sessions_work_order on technician_tracking_sessions(work_order_id);
create index idx_tracking_sessions_technician on technician_tracking_sessions(technician_profile_id);
create index idx_tracking_sessions_org on technician_tracking_sessions(organization_id);

create trigger trg_tracking_sessions_updated_at before update on technician_tracking_sessions
  for each row execute function set_updated_at();

create table technician_locations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  tracking_session_id uuid not null references technician_tracking_sessions(id),
  technician_profile_id uuid not null references profiles(id),
  work_order_id uuid not null references work_orders(id),
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  accuracy_meters double precision check (accuracy_meters >= 0),
  heading_degrees double precision check (heading_degrees >= 0 and heading_degrees <= 360),
  speed_mps double precision check (speed_mps >= 0 and speed_mps < 100),
  recorded_at timestamptz not null,
  received_at timestamptz not null default now(),
  source text not null default 'browser_gps',
  created_at timestamptz not null default now()
);

create index idx_technician_locations_session on technician_locations(tracking_session_id, recorded_at desc);
create index idx_technician_locations_work_order on technician_locations(work_order_id, recorded_at desc);
create index idx_technician_locations_technician on technician_locations(technician_profile_id, recorded_at desc);
create index idx_technician_locations_org on technician_locations(organization_id);
