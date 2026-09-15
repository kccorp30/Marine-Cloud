-- =========================================================
-- 029_phase2_field_operations_tables.sql — Marine Cloud Phase 2
-- =========================================================
-- Nota: vessel_systems necesitó una unique constraint adicional
-- (uq_vessel_systems_id_vessel) aplicada como parte de esta migración
-- para poder ser referenciada por FK compuesta desde measurements.

alter table vessel_systems add constraint uq_vessel_systems_id_vessel unique (id, vessel_id);

create table time_entries (
  id                    uuid primary key default gen_random_uuid(),
  organization_id       uuid not null references organizations(id),
  work_order_id         uuid not null,
  appointment_id        uuid,
  technician_profile_id uuid not null references profiles(id),
  start_time            timestamptz not null default now(),
  end_time              timestamptz,
  entry_type            text not null default 'work' check (entry_type in ('work','travel','other')),
  notes                 text,
  status                text not null default 'active' check (status in ('active','completed','voided')),
  client_generated_id   uuid,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  foreign key (work_order_id, organization_id) references work_orders(id, organization_id),
  foreign key (appointment_id, organization_id) references appointments(id, organization_id)
);
create unique index uq_time_entries_client_id on time_entries(work_order_id, client_generated_id) where client_generated_id is not null;
create index idx_time_entries_wo on time_entries(work_order_id);
create index idx_time_entries_tech_active on time_entries(technician_profile_id) where status = 'active';
create trigger trg_time_entries_updated_at before update on time_entries for each row execute function set_updated_at();
alter table time_entries enable row level security;

create table media_assets (
  id                uuid primary key default gen_random_uuid(),
  organization_id   uuid not null references organizations(id),
  vessel_id         uuid not null,
  work_order_id     uuid not null,
  appointment_id    uuid,
  uploaded_by       uuid not null references profiles(id),
  category          text not null check (category in (
    'before','diagnosis','progress','after','part','damage','measurement','receipt','qc','voice_note'
  )),
  captured_at       timestamptz,
  uploaded_at       timestamptz not null default now(),
  caption           text,
  storage_path      text not null,
  mime_type         text not null,
  size_bytes        bigint,
  checksum          text,
  duration_seconds  numeric,
  visibility        text not null default 'internal' check (visibility in ('internal','customer_visible','kcc_only')),
  client_generated_id uuid,
  deleted_at        timestamptz,
  foreign key (vessel_id, organization_id) references vessels(id, organization_id),
  foreign key (work_order_id, organization_id) references work_orders(id, organization_id),
  foreign key (appointment_id, organization_id) references appointments(id, organization_id)
);
create unique index uq_media_assets_client_id on media_assets(work_order_id, client_generated_id) where client_generated_id is not null;
create index idx_media_assets_wo on media_assets(work_order_id) where deleted_at is null;
create index idx_media_assets_vessel on media_assets(vessel_id) where deleted_at is null;
alter table media_assets enable row level security;

create table work_notes (
  id                    uuid primary key default gen_random_uuid(),
  organization_id       uuid not null references organizations(id),
  work_order_id         uuid not null,
  appointment_id        uuid,
  technician_profile_id uuid not null references profiles(id),
  body                  text not null,
  note_type             text not null default 'general' check (note_type in ('general','diagnostic','progress','internal','customer_update')),
  visibility            text not null default 'internal' check (visibility in ('internal','customer_visible','kcc_only')),
  client_generated_id   uuid,
  deleted_at            timestamptz,
  created_at            timestamptz not null default now(),
  foreign key (work_order_id, organization_id) references work_orders(id, organization_id),
  foreign key (appointment_id, organization_id) references appointments(id, organization_id)
);
create unique index uq_work_notes_client_id on work_notes(work_order_id, client_generated_id) where client_generated_id is not null;
create index idx_work_notes_wo on work_notes(work_order_id) where deleted_at is null;
alter table work_notes enable row level security;

create table measurements (
  id                    uuid primary key default gen_random_uuid(),
  organization_id       uuid not null references organizations(id),
  vessel_id             uuid not null,
  work_order_id         uuid not null,
  appointment_id        uuid,
  technician_profile_id uuid not null references profiles(id),
  system_id             uuid,
  measurement_type      text not null,
  value                 numeric not null,
  unit                  text not null,
  label                 text,
  notes                 text,
  measured_at           timestamptz not null default now(),
  client_generated_id   uuid,
  voided_at             timestamptz,
  void_reason           text,
  foreign key (vessel_id, organization_id) references vessels(id, organization_id),
  foreign key (work_order_id, organization_id) references work_orders(id, organization_id),
  foreign key (appointment_id, organization_id) references appointments(id, organization_id),
  foreign key (system_id, vessel_id) references vessel_systems(id, vessel_id)
);
create unique index uq_measurements_client_id on measurements(work_order_id, client_generated_id) where client_generated_id is not null;
create index idx_measurements_wo on measurements(work_order_id);
alter table measurements enable row level security;
