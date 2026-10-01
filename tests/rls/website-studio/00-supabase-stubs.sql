-- Imitación mínima de Supabase para probar la migración localmente.
create role anon nologin; create role authenticated nologin;
create schema auth;
create function auth.uid() returns uuid language sql stable as $$
  select nullif(nullif(current_setting('request.jwt.claims', true),'')::json->>'sub','')::uuid $$;
grant usage on schema auth to anon, authenticated;
grant usage on schema public to anon, authenticated;
create table profiles (id uuid primary key);
create table organization_memberships (profile_id uuid, role text, status text);
create function is_kcc_admin() returns boolean language plpgsql stable security definer set search_path = public as $$
begin return exists (select 1 from organization_memberships where profile_id = auth.uid() and role='kcc_admin' and status='active'); end $$;
create function set_updated_at() returns trigger language plpgsql set search_path = public as $$ begin new.updated_at = now(); return new; end $$;
create schema storage;
create table storage.buckets (id text primary key, name text, public boolean, file_size_limit bigint, allowed_mime_types text[]);
grant usage on schema storage to anon, authenticated;
create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text, name text);
alter table storage.objects enable row level security;
insert into profiles values ('00000000-0000-4000-8000-0000000000a1'),('00000000-0000-4000-8000-0000000000b1');
insert into organization_memberships values ('00000000-0000-4000-8000-0000000000a1','kcc_admin','active'),('00000000-0000-4000-8000-0000000000b1','company_owner','active');
