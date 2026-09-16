-- =========================================================
-- 238_create_organization_with_commercial_setup.sql — Phase 14 final integrity
-- =========================================================
-- Reusa create_organization() y assign_organization_subscription()
-- tal cual existen. Una sola función PL/pgSQL = una sola transacción
-- real: si la suscripción falla, la organización recién creada NUNCA
-- persiste — todo o nada.
-- Verificado con datos reales: creación atómica con trial, plan
-- inválido revierte TODO (sin org huérfana), company owner bloqueado.
-- =========================================================

create or replace function create_organization_with_commercial_setup(
  p_name text, p_plan_id uuid, p_billing_cycle text,
  p_legal_name text default null, p_slug text default null,
  p_timezone text default 'America/New_York', p_currency text default 'USD', p_locale text default 'en',
  p_location_name text default null, p_location_address text default null, p_owner_email text default null,
  p_trial_days int default null, p_price_override numeric default null,
  p_complimentary boolean default false, p_complimentary_reason text default null, p_custom_terms text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
begin
  if not is_kcc_admin() then
    raise exception 'only KCC platform staff can create a company with commercial setup';
  end if;

  v_org_id := create_organization(p_name, p_legal_name, p_slug, p_timezone, p_currency, p_locale, p_location_name, p_location_address, p_owner_email);

  perform assign_organization_subscription(v_org_id, p_plan_id, p_billing_cycle, p_trial_days, p_price_override, p_complimentary, p_complimentary_reason, p_custom_terms);

  return v_org_id;
end;
$$;

revoke execute on function create_organization_with_commercial_setup(text, uuid, text, text, text, text, text, text, text, text, text, int, numeric, boolean, text, text) from public, anon, authenticated;
grant execute on function create_organization_with_commercial_setup(text, uuid, text, text, text, text, text, text, text, text, text, int, numeric, boolean, text, text) to authenticated;
