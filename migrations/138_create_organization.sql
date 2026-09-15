-- =========================================================
-- 138_create_organization.sql — Marine Cloud Phase 10
-- =========================================================
-- Transaccional: organización + settings + ubicación primaria
-- opcional + invitación de owner opcional, todo o nada. Reusa
-- invite_team_member() ya existente para el owner — nunca inventa
-- contraseñas ni un sistema de invitación paralelo.
-- Verificado con datos reales: kcc_admin puede, company_owner no,
-- las 4 piezas (org/settings/location/invitación) se crean juntas.
-- =========================================================

create or replace function create_organization(
  p_name text,
  p_legal_name text default null,
  p_slug text default null,
  p_timezone text default 'America/New_York',
  p_currency text default 'USD',
  p_locale text default 'en',
  p_location_name text default null,
  p_location_address text default null,
  p_owner_email text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_slug text;
begin
  if not is_kcc_admin() then
    raise exception 'only KCC platform staff can create organizations';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'organization name is required';
  end if;

  v_slug := coalesce(nullif(trim(p_slug), ''), lower(regexp_replace(p_name, '[^a-zA-Z0-9]+', '-', 'g')) || '-' || substr(gen_random_uuid()::text, 1, 6));

  insert into organizations (name, legal_name, slug, status, created_by)
  values (p_name, p_legal_name, v_slug, 'active', auth.uid())
  returning id into v_org_id;

  insert into organization_settings (organization_id, timezone, currency, locale)
  values (v_org_id, p_timezone, p_currency, p_locale);

  if p_location_name is not null then
    insert into organization_locations (organization_id, name, address, is_primary)
    values (v_org_id, p_location_name, p_location_address, true);
  end if;

  if p_owner_email is not null and length(trim(p_owner_email)) > 0 then
    perform invite_team_member(v_org_id, p_owner_email, 'company_owner');
  end if;

  perform log_domain_event(v_org_id, 'ORGANIZATION_CREATED', 'organization', v_org_id,
    jsonb_build_object('name', p_name, 'slug', v_slug));
  perform log_audit_event(v_org_id, 'organization', v_org_id, 'organization_created',
    null, jsonb_build_object('name', p_name));

  return v_org_id;
end;
$$;

revoke execute on function create_organization(text, text, text, text, text, text, text, text, text) from public, anon;
grant execute on function create_organization(text, text, text, text, text, text, text, text, text) to authenticated;
