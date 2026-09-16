-- =========================================================
-- 030_phase2_checklists_progress_checkins.sql — Marine Cloud Phase 2
-- =========================================================
-- Nota: media_assets necesitó unique(id, work_order_id) adicional
-- (aplicada al inicio de esta migración) para que checklist_responses
-- y progress_update_media puedan referenciarla vía FK compuesta.

alter table media_assets add constraint uq_media_assets_id_wo unique (id, work_order_id);

create table checklist_templates (
  id                uuid primary key default gen_random_uuid(),
  organization_id   uuid not null references organizations(id),
  name              text not null,
  active            boolean not null default true,
  created_at        timestamptz not null default now()
);
alter table checklist_templates enable row level security;

create table checklist_template_items (
  id                uuid primary key default gen_random_uuid(),
  template_id       uuid not null references checklist_templates(id),
  organization_id   uuid not null references organizations(id),
  label             text not null,
  response_type     text not null check (response_type in ('checkbox','pass_fail','text','numeric','photo_required')),
  display_order     integer not null default 0
);
alter table checklist_template_items enable row level security;

create table checklist_responses (
  id                    uuid primary key default gen_random_uuid(),
  organization_id       uuid not null references organizations(id),
  work_order_id         uuid not null,
  appointment_id        uuid,
  template_item_id      uuid not null references checklist_template_items(id),
  technician_profile_id uuid not null references profiles(id),
  response_value        jsonb not null,
  media_id              uuid,
  completed_at          timestamptz not null default now(),
  client_generated_id   uuid,
  foreign key (work_order_id, organization_id) references work_orders(id, organization_id),
  foreign key (appointment_id, organization_id) references appointments(id, organization_id),
  foreign key (media_id, work_order_id) references media_assets(id, work_order_id)
);
create unique index uq_checklist_responses_client_id on checklist_responses(work_order_id, client_generated_id) where client_generated_id is not null;
create unique index uq_checklist_responses_item_per_wo on checklist_responses(work_order_id, template_item_id);
alter table checklist_responses enable row level security;

create table progress_updates (
  id                    uuid primary key default gen_random_uuid(),
  organization_id       uuid not null references organizations(id),
  work_order_id         uuid not null,
  appointment_id        uuid,
  technician_profile_id uuid not null references profiles(id),
  body                  text,
  customer_visible      boolean not null default false,
  client_generated_id   uuid,
  created_at            timestamptz not null default now(),
  foreign key (work_order_id, organization_id) references work_orders(id, organization_id),
  foreign key (appointment_id, organization_id) references appointments(id, organization_id)
);
create unique index uq_progress_updates_client_id on progress_updates(work_order_id, client_generated_id) where client_generated_id is not null;
alter table progress_updates enable row level security;

create table progress_update_media (
  progress_update_id   uuid not null references progress_updates(id),
  media_id              uuid not null,
  work_order_id         uuid not null,
  primary key (progress_update_id, media_id),
  foreign key (media_id, work_order_id) references media_assets(id, work_order_id)
);
alter table progress_update_media enable row level security;

create table check_ins (
  id                    uuid primary key default gen_random_uuid(),
  organization_id       uuid not null references organizations(id),
  work_order_id         uuid not null,
  appointment_id        uuid not null,
  technician_profile_id uuid not null references profiles(id),
  checked_in_at         timestamptz not null default now(),
  checked_out_at        timestamptz,
  latitude              double precision,
  longitude             double precision,
  device_metadata       jsonb,
  closing_note          text,
  foreign key (work_order_id, organization_id) references work_orders(id, organization_id),
  foreign key (appointment_id, organization_id) references appointments(id, organization_id)
);
create index idx_check_ins_wo on check_ins(work_order_id);
alter table check_ins enable row level security;
