-- =========================================================
-- 221_organization_has_active_access.sql — Marine Cloud Phase 14
-- =========================================================
-- Helper CENTRAL de enforcement — nunca decorativo de UI.
-- Verificado con datos reales: sin suscripción aún deniega, kcc_admin
-- siempre tiene acceso.
-- =========================================================

create or replace function organization_has_active_access(p_organization_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_org_status text;
  v_sub organization_subscriptions%rowtype;
  v_effective text;
begin
  if is_kcc_admin() then
    return true;
  end if;

  select status into v_org_status from organizations where id = p_organization_id;
  if v_org_status is null or v_org_status not in ('active') then
    return false;
  end if;

  select * into v_sub from organization_subscriptions where organization_id = p_organization_id and superseded_at is null;
  if v_sub.id is null then
    return false;
  end if;

  v_effective := subscription_effective_status(v_sub.status, v_sub.trial_ends_at, v_sub.grace_period_ends_at, v_sub.complimentary);

  return v_effective in ('trialing', 'active', 'grace_period', 'complimentary');
end;
$$;

revoke execute on function organization_has_active_access(uuid) from public, anon;
grant execute on function organization_has_active_access(uuid) to authenticated;
