-- =========================================================
-- 000_baseline_shared_with_website.sql
-- =========================================================
-- ⚠️ ESTE ARCHIVO ES PROPIEDAD DEL REPO kccorp-web (el sitio web),
-- NO de kcc-marine-cloud. Se copia aquí sin modificaciones únicamente
-- para que este repo sea reproducible por sí solo — ambos proyectos
-- comparten el MISMO proyecto Supabase (zxgeipuzglromtuxhxtb).
--
-- Si este archivo diverge del original en kccorp-web/migrations/000_baseline.sql,
-- el de kccorp-web es la fuente de verdad — actualizar ahí primero,
-- después sincronizar la copia aquí.
--
-- Contiene: profiles, organizations, organization_locations,
-- organization_settings, organization_memberships,
-- technician_relationships, customer_relationships, leads (dominio
-- del sitio web, Marine Cloud no lo toca), funciones helper base
-- (set_updated_at, current_organization_id [en desuso, ver nota en
-- 013_permission_matrix_rls.sql], is_kcc_admin, handle_new_user,
-- sync_lead_media_count), bucket lead-media (dominio del sitio web).
-- =========================================================


create extension if not exists "pgcrypto";
create extension if not exists "pg_trgm" with schema extensions;

-- ---------------------------------------------------------
-- Funciones helper
-- ---------------------------------------------------------
create or replace function set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function current_organization_id()
returns uuid
language sql
stable
set search_path = public
as $$
  select nullif(current_setting('app.current_organization_id', true), '')::uuid;
$$;

create or replace function is_kcc_admin()
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  return exists (
    select 1 from organization_memberships
    where profile_id = auth.uid() and role = 'kcc_admin' and status = 'active'
  );
end;
$$;
revoke execute on function is_kcc_admin() from public;

create or replace function handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name)
  values (new.id, new.email, new.raw_user_meta_data->>'full_name');
  return new;
end;
$$;
revoke execute on function handle_new_user() from public;

create or replace function sync_lead_media_count()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  new.media_count = jsonb_array_length(coalesce(new.media, '[]'::jsonb));
  return new;
end;
$$;

-- ---------------------------------------------------------
-- Tipos
-- ---------------------------------------------------------
create type membership_role as enum (
  'kcc_admin', 'company_owner', 'company_admin', 'manager', 'technician', 'customer'
);

-- ---------------------------------------------------------
-- organizations
-- ---------------------------------------------------------
create table organizations (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  legal_name    text,
  slug          text not null unique,
  branding_json jsonb not null default '{}'::jsonb,
  status        text not null default 'active' check (status in ('active','suspended','archived')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  created_by    uuid,
  deleted_at    timestamptz
);
create trigger trg_organizations_updated_at before update on organizations for each row execute function set_updated_at();
create index idx_organizations_status on organizations(status) where deleted_at is null;
alter table organizations enable row level security;

-- ---------------------------------------------------------
-- organization_locations
-- ---------------------------------------------------------
create table organization_locations (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  name            text not null,
  address         text,
  marina_name     text,
  lat             double precision,
  lng             double precision,
  is_primary      boolean not null default false,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz
);
create trigger trg_org_locations_updated_at before update on organization_locations for each row execute function set_updated_at();
create index idx_org_locations_org on organization_locations(organization_id) where deleted_at is null;
create unique index uq_org_locations_one_primary on organization_locations(organization_id) where is_primary = true and deleted_at is null;
alter table organization_locations enable row level security;

-- ---------------------------------------------------------
-- organization_settings
-- ---------------------------------------------------------
create table organization_settings (
  organization_id uuid primary key references organizations(id) on delete cascade,
  timezone        text not null default 'America/New_York',
  currency        text not null default 'USD',
  locale          text not null default 'es',
  units_system    text not null default 'imperial' check (units_system in ('imperial','metric')),
  tax_config      jsonb not null default '{}'::jsonb,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create trigger trg_org_settings_updated_at before update on organization_settings for each row execute function set_updated_at();
alter table organization_settings enable row level security;

-- ---------------------------------------------------------
-- profiles
-- ---------------------------------------------------------
create table profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  full_name  text,
  phone      text,
  email      text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_profiles_updated_at before update on profiles for each row execute function set_updated_at();
alter table profiles enable row level security;

create trigger trg_on_auth_user_created after insert on auth.users for each row execute function handle_new_user();

alter table organizations add constraint fk_organizations_created_by foreign key (created_by) references profiles(id);

-- ---------------------------------------------------------
-- organization_memberships
-- ---------------------------------------------------------
create table organization_memberships (
  id              uuid primary key default gen_random_uuid(),
  profile_id      uuid not null references profiles(id) on delete cascade,
  organization_id uuid not null references organizations(id) on delete cascade,
  role            membership_role not null,
  status          text not null default 'active' check (status in ('active','invited','suspended')),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (profile_id, organization_id, role)
);
create trigger trg_org_memberships_updated_at before update on organization_memberships for each row execute function set_updated_at();
create index idx_org_memberships_org_role on organization_memberships(organization_id, role) where status = 'active';
create index idx_org_memberships_profile on organization_memberships(profile_id) where status = 'active';
alter table organization_memberships enable row level security;

-- ---------------------------------------------------------
-- technician_relationships
-- ---------------------------------------------------------
create table technician_relationships (
  id              uuid primary key default gen_random_uuid(),
  profile_id      uuid not null references profiles(id) on delete cascade,
  organization_id uuid not null references organizations(id) on delete cascade,
  skills          text[] not null default '{}',
  certifications  jsonb not null default '[]'::jsonb,
  service_areas   jsonb not null default '[]'::jsonb,
  pay_type        text not null default 'hourly' check (pay_type in ('hourly','daily')),
  pay_rate        numeric(10,2),
  hire_date       date,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (profile_id, organization_id)
);
create trigger trg_technician_rel_updated_at before update on technician_relationships for each row execute function set_updated_at();
alter table technician_relationships enable row level security;

-- ---------------------------------------------------------
-- customer_relationships
-- ---------------------------------------------------------
create table customer_relationships (
  id                     uuid primary key default gen_random_uuid(),
  profile_id             uuid not null references profiles(id) on delete cascade,
  organization_id        uuid not null references organizations(id) on delete cascade,
  billing_address        text,
  notes                  text,
  loyalty_points_balance integer not null default 0,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  unique (profile_id, organization_id)
);
create trigger trg_customer_rel_updated_at before update on customer_relationships for each row execute function set_updated_at();
alter table customer_relationships enable row level security;

-- ---------------------------------------------------------
-- leads (nombres CANÓNICOS confirmados en vivo — customer_name,
-- internal_notes, region, media, media_count, conversion_status,
-- integration_status, integration_error, last_sync_at,
-- idempotency_key, first_touch_*)
-- ---------------------------------------------------------
create table leads (
  id                         uuid primary key default gen_random_uuid(),
  reference_code             text not null unique,
  created_at                 timestamptz not null default now(),
  updated_at                 timestamptz not null default now(),
  status                     text not null default 'new'
    check (status in ('new','contacted','qualified','estimate','booked','lost','converted')),
  country                    text,
  region                     text,
  city                       text,
  service_type               text,
  vessel_make                text,
  vessel_model               text,
  vessel_year                integer,
  vessel_name                text,
  hin                        text,
  description                text,
  customer_name              text,
  phone                      text,
  email                      text,
  preferred_contact_method   text,
  source                     text,
  campaign                   text,
  medium                     text,
  utm_source                 text,
  utm_campaign               text,
  utm_medium                 text,
  utm_content                text,
  referrer                   text,
  landing_page               text,
  internal_notes             text,
  media                      jsonb not null default '[]'::jsonb,
  media_count                integer not null default 0,
  assigned_organization_id   uuid references organizations(id),
  marine_cloud_customer_id   uuid references profiles(id),
  marine_cloud_vessel_id     uuid,
  marine_cloud_work_order_id uuid,
  conversion_status          text not null default 'not_converted'
    check (conversion_status in ('not_converted','pending','converted','failed')),
  converted_at               timestamptz,
  converted_by               uuid references profiles(id),
  integration_status         text not null default 'pending'
    check (integration_status in ('pending','synced','error')),
  integration_error          text,
  last_sync_at               timestamptz,
  idempotency_key            uuid not null default gen_random_uuid() unique,
  -- first-touch attribution (Sprint 6)
  first_utm_source           text,
  first_utm_medium           text,
  first_utm_campaign         text,
  first_utm_content          text,
  first_referrer             text,
  first_landing_page         text,
  first_touch_at             timestamptz
);
create trigger trg_leads_updated_at before update on leads for each row execute function set_updated_at();
create trigger trg_sync_lead_media_count before insert or update of media on leads for each row execute function sync_lead_media_count();
create index idx_leads_status on leads(status);
create index idx_leads_assigned_org on leads(assigned_organization_id) where assigned_organization_id is not null;
create index idx_leads_created_at on leads(created_at desc);
create index idx_leads_conversion_status on leads(conversion_status);
create index idx_leads_integration_status on leads(integration_status) where integration_status is not null;
alter table leads enable row level security;

create policy "kcc_admin_full_access_leads" on leads for all using (is_kcc_admin()) with check (is_kcc_admin());

-- ---------------------------------------------------------
-- Storage: bucket lead-media (privado)
-- ---------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('lead-media', 'lead-media', false, 26214400,
  array['image/jpeg','image/png','image/webp','image/heic','video/mp4','video/quicktime'])
on conflict (id) do nothing;

create policy "kcc_admin_read_lead_media" on storage.objects for select using (bucket_id = 'lead-media' and is_kcc_admin());
create policy "kcc_admin_delete_lead_media" on storage.objects for delete using (bucket_id = 'lead-media' and is_kcc_admin());
