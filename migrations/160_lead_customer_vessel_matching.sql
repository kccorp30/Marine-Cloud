-- =========================================================
-- 160_lead_customer_vessel_matching.sql — Marine Cloud Phase 11
-- =========================================================
-- Matching determinístico, nunca por nombre solo. Orden: teléfono
-- normalizado (solo dígitos) -> email normalizado (lower/trim) ->
-- crear. Verificado con datos reales: (305) 555-1234 y 305-555-1234
-- normalizan igual y reusan el mismo customer, sin duplicar.
-- =========================================================

create or replace function normalize_phone(p_phone text)
returns text
language sql
immutable
as $$
  select nullif(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), '');
$$;

create or replace function find_or_create_customer_for_lead(
  p_organization_id uuid,
  p_name text,
  p_phone text,
  p_email text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_customer_id uuid;
  v_norm_phone text;
  v_norm_email text;
  v_first_name text;
  v_last_name text;
begin
  if not is_platform_trusted_actor() then
    raise exception 'only trusted platform infrastructure can match/create customers from website leads';
  end if;

  v_norm_phone := normalize_phone(p_phone);
  v_norm_email := nullif(lower(trim(coalesce(p_email, ''))), '');

  if v_norm_phone is not null then
    select id into v_customer_id from customers
    where organization_id = p_organization_id and normalize_phone(phone) = v_norm_phone
    limit 1;
  end if;

  if v_customer_id is null and v_norm_email is not null then
    select id into v_customer_id from customers
    where organization_id = p_organization_id and lower(trim(email)) = v_norm_email
    limit 1;
  end if;

  if v_customer_id is not null then
    return v_customer_id;
  end if;

  v_first_name := split_part(coalesce(nullif(trim(p_name), ''), 'Website'), ' ', 1);
  v_last_name := nullif(trim(substring(coalesce(nullif(trim(p_name), ''), 'Website') from length(v_first_name) + 1)), '');

  insert into customers (organization_id, first_name, last_name, phone, email)
  values (p_organization_id, v_first_name, coalesce(v_last_name, 'Lead'), p_phone, nullif(trim(p_email), ''))
  returning id into v_customer_id;

  return v_customer_id;
end;
$$;

revoke execute on function find_or_create_customer_for_lead(uuid, text, text, text) from public, anon, authenticated;

create or replace function find_or_create_vessel_for_lead(
  p_organization_id uuid,
  p_customer_id uuid,
  p_hin text,
  p_make text,
  p_model text,
  p_year int,
  p_name text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_vessel_id uuid;
  v_norm_hin text;
begin
  if not is_platform_trusted_actor() then
    raise exception 'only trusted platform infrastructure can match/create vessels from website leads';
  end if;

  v_norm_hin := nullif(upper(trim(coalesce(p_hin, ''))), '');

  if v_norm_hin is not null then
    select id into v_vessel_id from vessels
    where organization_id = p_organization_id and upper(trim(hin)) = v_norm_hin
    limit 1;
  end if;

  if v_vessel_id is null then
    select id into v_vessel_id from vessels
    where organization_id = p_organization_id
      and current_customer_id = p_customer_id
      and coalesce(lower(trim(make)), '') = coalesce(lower(trim(p_make)), '')
      and coalesce(lower(trim(model)), '') = coalesce(lower(trim(p_model)), '')
      and coalesce(year, -1) = coalesce(p_year, -1)
    limit 1;
  end if;

  if v_vessel_id is not null then
    return v_vessel_id;
  end if;

  insert into vessels (organization_id, current_customer_id, name, make, model, year, hin)
  values (p_organization_id, p_customer_id, coalesce(nullif(trim(p_name), ''), p_make || ' ' || p_model), p_make, p_model, p_year, nullif(trim(p_hin), ''))
  returning id into v_vessel_id;

  return v_vessel_id;
end;
$$;

revoke execute on function find_or_create_vessel_for_lead(uuid, uuid, text, text, text, int, text) from public, anon, authenticated;
