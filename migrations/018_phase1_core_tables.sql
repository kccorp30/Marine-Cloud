-- =========================================================
-- 018_phase1_core_tables.sql — Marine Cloud Phase 1
-- Customer + Vessel + Work Order core
-- =========================================================

-- ---------------------------------------------------------
-- customers — identidad de negocio separada del profile de login.
-- Un customer puede existir SIN profile_id (la compañía lo crea
-- antes de invitarlo a tener acceso a Marine Cloud).
-- ---------------------------------------------------------
create table customers (
  id                        uuid primary key default gen_random_uuid(),
  organization_id           uuid not null references organizations(id),
  profile_id                uuid references profiles(id),  -- nullable a propósito
  first_name                text not null,
  last_name                 text not null,
  email                     text,
  phone                     text,
  preferred_contact_method  text check (preferred_contact_method in ('phone','email','whatsapp')),
  status                    text not null default 'active' check (status in ('active','inactive')),
  notes                     text,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),
  created_by                uuid references profiles(id)
);

create index idx_customers_org on customers(organization_id);
create index idx_customers_profile on customers(profile_id) where profile_id is not null;
-- Campos canónicos de matching para la futura conversión de leads del
-- sitio (Phase 10) — email/phone ya cubren lo que CustomerInput del
-- sitio necesita para buscar/matchear antes de crear duplicados.
create index idx_customers_email on customers(organization_id, email) where email is not null;
create index idx_customers_phone on customers(organization_id, phone) where phone is not null;

create trigger trg_customers_updated_at before update on customers for each row execute function set_updated_at();
alter table customers enable row level security;

-- ---------------------------------------------------------
-- vessels
-- ---------------------------------------------------------
create table vessels (
  id                  uuid primary key default gen_random_uuid(),
  organization_id     uuid not null references organizations(id),
  current_customer_id uuid references customers(id),  -- desnormalizado por performance; la fuente de verdad histórica es vessel_ownership_history
  name                text,
  hin                 text,
  make                text,
  model               text,
  year                integer,
  vessel_type         text,
  length              numeric(6,2),
  location_id         uuid references organization_locations(id),
  marina              text,
  status              text not null default 'active' check (status in ('active','inactive','sold')),
  passport_id         uuid unique default gen_random_uuid(),  -- future-ready (QR/NFC), no funcional todavía
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  created_by          uuid references profiles(id)
);

create index idx_vessels_org on vessels(organization_id);
create index idx_vessels_customer on vessels(current_customer_id) where current_customer_id is not null;
create index idx_vessels_hin on vessels(organization_id, hin) where hin is not null;

create trigger trg_vessels_updated_at before update on vessels for each row execute function set_updated_at();
alter table vessels enable row level security;

-- ---------------------------------------------------------
-- vessel_ownership_history — nunca se sobrescribe
-- ---------------------------------------------------------
create table vessel_ownership_history (
  id                uuid primary key default gen_random_uuid(),
  organization_id   uuid not null references organizations(id),
  vessel_id         uuid not null references vessels(id),
  customer_id       uuid not null references customers(id),
  relationship_type text not null default 'owner',
  start_date        date not null default current_date,
  end_date          date  -- null = relación actual
);

create index idx_vessel_ownership_vessel on vessel_ownership_history(vessel_id);
-- Solo puede haber UNA relación "actual" (end_date null) por vessel —
-- previene el registro imposible de dos dueños actuales simultáneos.
create unique index uq_vessel_ownership_one_current on vessel_ownership_history(vessel_id) where end_date is null;

alter table vessel_ownership_history enable row level security;

-- ---------------------------------------------------------
-- vessel_systems — modelo híbrido aprobado
-- ---------------------------------------------------------
create table vessel_systems (
  id                uuid primary key default gen_random_uuid(),
  organization_id   uuid not null references organizations(id),
  vessel_id         uuid not null references vessels(id),
  system_type       text not null,
  manufacturer      text,
  model             text,
  serial_number     text,
  install_date      date,
  status            text not null default 'active' check (status in ('active','inactive','needs_repair','replaced')),
  metadata          jsonb not null default '{}'::jsonb,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index idx_vessel_systems_vessel on vessel_systems(vessel_id);
create index idx_vessel_systems_type on vessel_systems(vessel_id, system_type);

create trigger trg_vessel_systems_updated_at before update on vessel_systems for each row execute function set_updated_at();
alter table vessel_systems enable row level security;

-- ---------------------------------------------------------
-- service_catalog
-- ---------------------------------------------------------
create table service_catalog (
  id                  uuid primary key default gen_random_uuid(),
  organization_id     uuid not null references organizations(id),
  name                text not null,
  description         text,
  active              boolean not null default true,
  estimated_duration  interval,
  base_price          numeric(10,2),
  pricing_type        text check (pricing_type in ('fixed','hourly','estimate')),
  display_order       integer not null default 0,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create index idx_service_catalog_org on service_catalog(organization_id) where active = true;

create trigger trg_service_catalog_updated_at before update on service_catalog for each row execute function set_updated_at();
alter table service_catalog enable row level security;
