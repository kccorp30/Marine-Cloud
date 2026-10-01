-- =========================================================
-- 20261001000000_website_studio.sql — Sitio web editable desde Marine Cloud
-- =========================================================
-- Decisión de producto (Alejo, oct 2026): el contenido del sitio
-- público KCCORP se edita DENTRO de Marine Cloud (KCC Admin), no en
-- un CMS externo. El sitio (repo kccorp-web) y la app comparten este
-- mismo proyecto Supabase, así que el sitio lee estas tablas directo.
--
-- Modelo de seguridad:
--   * Visitante anónimo del sitio  → SOLO filas published = true.
--   * kcc_admin                    → lee y escribe todo.
--   * cualquier otro usuario       → igual que un anónimo (solo publicado).
--   El sitio lee con la anon key, así que RLS es la puerta real: un
--   borrador nunca puede filtrarse aunque el código del sitio falle.
--
-- Textos localizados: jsonb {"en": "...", "es": "..."}. Inglés es el
-- idioma principal del sitio; español es opcional por campo.
--
-- Testimonios: no se pueden publicar sin consent_confirmed = true.
-- Es una restricción en la base, no una sugerencia de la UI — un
-- testimonio inventado o sin permiso del cliente no puede salir al
-- sitio.
-- =========================================================

-- ---------- Ajustes globales (singleton) ----------
create table if not exists site_settings (
  id boolean primary key default true check (id),
  company_name text not null default 'KCCORP Marine Solutions',
  tagline jsonb not null default '{}'::jsonb check (jsonb_typeof(tagline) = 'object'),
  hero_headline jsonb not null default '{}'::jsonb check (jsonb_typeof(hero_headline) = 'object'),
  hero_subheadline jsonb not null default '{}'::jsonb check (jsonb_typeof(hero_subheadline) = 'object'),
  hero_image_path text,
  primary_cta_label jsonb not null default '{}'::jsonb check (jsonb_typeof(primary_cta_label) = 'object'),
  response_promise jsonb not null default '{}'::jsonb check (jsonb_typeof(response_promise) = 'object'),
  phone text,
  whatsapp text check (whatsapp is null or whatsapp ~ '^[0-9]{8,15}$'),
  email text check (email is null or email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  service_areas text[] not null default '{}',
  -- Cifras de confianza: OPCIONALES. El sitio solo muestra una cifra
  -- si está cargada; nunca se rellena con un valor por defecto.
  years_in_business integer check (years_in_business is null or years_in_business between 0 and 100),
  jobs_completed integer check (jobs_completed is null or jobs_completed >= 0),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid() references profiles(id)
);
insert into site_settings (id) values (true) on conflict (id) do nothing;

-- ---------- Servicios ----------
create table if not exists site_services (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  category text not null default 'other' check (category in ('electrical','maintenance','electronics','other')),
  title jsonb not null check (jsonb_typeof(title) = 'object' and coalesce(title->>'en','') <> ''),
  summary jsonb not null default '{}'::jsonb check (jsonb_typeof(summary) = 'object'),
  body jsonb not null default '{}'::jsonb check (jsonb_typeof(body) = 'object'),
  -- [{"en": "...", "es": "..."}, ...]
  benefits jsonb not null default '[]'::jsonb check (jsonb_typeof(benefits) = 'array'),
  hero_image_path text,
  icon text not null default 'bolt' check (icon in ('bolt','radar','pulse','compass','speaker','bulb','battery','pump','wrench')),
  featured boolean not null default false,
  sort_order integer not null default 100,
  published boolean not null default false,
  seo_title jsonb not null default '{}'::jsonb check (jsonb_typeof(seo_title) = 'object'),
  seo_description jsonb not null default '{}'::jsonb check (jsonb_typeof(seo_description) = 'object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid() references profiles(id)
);

-- ---------- Proyectos / casos reales ----------
create table if not exists site_projects (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  service_id uuid references site_services(id) on delete set null,
  title jsonb not null check (jsonb_typeof(title) = 'object' and coalesce(title->>'en','') <> ''),
  vessel_type text,
  location text,
  problem jsonb not null default '{}'::jsonb check (jsonb_typeof(problem) = 'object'),
  solution jsonb not null default '{}'::jsonb check (jsonb_typeof(solution) = 'object'),
  result jsonb not null default '{}'::jsonb check (jsonb_typeof(result) = 'object'),
  before_image_path text,
  after_image_path text,
  gallery_paths text[] not null default '{}',
  completed_on date,
  featured boolean not null default false,
  sort_order integer not null default 100,
  published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid() references profiles(id)
);

-- ---------- Testimonios ----------
create table if not exists site_testimonials (
  id uuid primary key default gen_random_uuid(),
  service_id uuid references site_services(id) on delete set null,
  author_name text not null check (length(trim(author_name)) > 0),
  author_detail text,
  quote jsonb not null check (jsonb_typeof(quote) = 'object' and coalesce(quote->>'en', quote->>'es', '') <> ''),
  rating smallint check (rating is null or rating between 1 and 5),
  consent_confirmed boolean not null default false,
  featured boolean not null default false,
  sort_order integer not null default 100,
  published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid() references profiles(id),
  constraint site_testimonials_publish_requires_consent check (not published or consent_confirmed)
);

-- ---------- Landing pages de campaña ----------
create table if not exists site_landing_pages (
  id uuid primary key default gen_random_uuid(),
  -- ruta pública sin "/" inicial: "offers/marine-electrical-miami"
  path text not null unique check (path ~ '^[a-z0-9]+(-[a-z0-9]+)*(/[a-z0-9]+(-[a-z0-9]+)*)*$'),
  internal_name text not null,
  service_id uuid references site_services(id) on delete set null,
  headline jsonb not null check (jsonb_typeof(headline) = 'object' and coalesce(headline->>'en','') <> ''),
  subheadline jsonb not null default '{}'::jsonb check (jsonb_typeof(subheadline) = 'object'),
  offer jsonb not null default '{}'::jsonb check (jsonb_typeof(offer) = 'object'),
  bullets jsonb not null default '[]'::jsonb check (jsonb_typeof(bullets) = 'array'),
  cta_label jsonb not null default '{}'::jsonb check (jsonb_typeof(cta_label) = 'object'),
  hero_image_path text,
  project_id uuid references site_projects(id) on delete set null,
  testimonial_id uuid references site_testimonials(id) on delete set null,
  utm_source text,
  utm_campaign text,
  published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid() references profiles(id)
);

-- ---------- updated_at ----------
do $$
declare t text;
begin
  foreach t in array array['site_settings','site_services','site_projects','site_testimonials','site_landing_pages'] loop
    execute format('drop trigger if exists trg_%1$s_updated_at on %1$s', t);
    execute format('create trigger trg_%1$s_updated_at before update on %1$s for each row execute function set_updated_at()', t);
  end loop;
end $$;

create index if not exists idx_site_services_published on site_services (published, sort_order);
create index if not exists idx_site_projects_published on site_projects (published, sort_order);
create index if not exists idx_site_testimonials_published on site_testimonials (published, sort_order);
create index if not exists idx_site_landing_pages_published on site_landing_pages (published, path);

-- ---------- RLS ----------
alter table site_settings enable row level security;
alter table site_services enable row level security;
alter table site_projects enable row level security;
alter table site_testimonials enable row level security;
alter table site_landing_pages enable row level security;

-- Ajustes: públicos (teléfono, WhatsApp, textos del hero ya son
-- información pública del sitio). Solo kcc_admin escribe.
drop policy if exists site_settings_read on site_settings;
create policy site_settings_read on site_settings for select to anon, authenticated using (true);
drop policy if exists site_settings_write on site_settings;
create policy site_settings_write on site_settings for update to authenticated using (is_kcc_admin()) with check (is_kcc_admin());

do $$
declare t text;
begin
  foreach t in array array['site_services','site_projects','site_testimonials','site_landing_pages'] loop
    execute format('drop policy if exists %1$s_public_read on %1$s', t);
    execute format('create policy %1$s_public_read on %1$s for select to anon, authenticated using (published = true or is_kcc_admin())', t);
    execute format('drop policy if exists %1$s_admin_insert on %1$s', t);
    execute format('create policy %1$s_admin_insert on %1$s for insert to authenticated with check (is_kcc_admin())', t);
    execute format('drop policy if exists %1$s_admin_update on %1$s', t);
    execute format('create policy %1$s_admin_update on %1$s for update to authenticated using (is_kcc_admin()) with check (is_kcc_admin())', t);
    execute format('drop policy if exists %1$s_admin_delete on %1$s', t);
    execute format('create policy %1$s_admin_delete on %1$s for delete to authenticated using (is_kcc_admin())', t);
  end loop;
end $$;

grant select on site_settings, site_services, site_projects, site_testimonials, site_landing_pages to anon, authenticated;
grant insert, update, delete on site_services, site_projects, site_testimonials, site_landing_pages to authenticated;
grant update on site_settings to authenticated;

-- ---------- Bucket de imágenes del sitio ----------
-- Público a propósito: son fotos de marketing que el sitio muestra a
-- cualquier visitante. NO se reutilizan vessel-media / lead-media /
-- portal-media, que son privados y siguen privados.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('site-media', 'site-media', true, 10485760, array['image/jpeg','image/png','image/webp','image/avif'])
on conflict (id) do update
  set public = true,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists site_media_admin_insert on storage.objects;
create policy site_media_admin_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'site-media' and is_kcc_admin());
drop policy if exists site_media_admin_update on storage.objects;
create policy site_media_admin_update on storage.objects for update to authenticated
  using (bucket_id = 'site-media' and is_kcc_admin()) with check (bucket_id = 'site-media' and is_kcc_admin());
drop policy if exists site_media_admin_delete on storage.objects;
create policy site_media_admin_delete on storage.objects for delete to authenticated
  using (bucket_id = 'site-media' and is_kcc_admin());
