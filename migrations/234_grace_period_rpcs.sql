-- =========================================================
-- 234_grace_period_rpcs.sql — Phase 14 final integrity
-- =========================================================
-- Período de gracia real, otorgable manualmente por kcc_admin (el
-- disparo automático por fallo de pago pertenece a Phase 15). Acceso
-- se mantiene durante el período válido; tras vencer, el efectivo
-- pasa a 'past_due' sin cron.
-- Verificado con datos reales: grace period concede acceso, vencido
-- lo deniega.
-- =========================================================

create or replace function grant_subscription_grace_period(p_organization_id uuid, p_grace_ends_at timestamptz, p_reason text default null)
returns organization_subscriptions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sub organization_subscriptions%rowtype;
begin
  if not is_kcc_admin() then
    raise exception 'only KCC platform staff can grant a grace period';
  end if;
  if p_grace_ends_at <= now() then
    raise exception 'grace period end must be in the future';
  end if;

  select * into v_sub from organization_subscriptions where organization_id = p_organization_id and superseded_at is null for update;
  if v_sub.id is null then
    raise exception 'no current subscription for this organization';
  end if;
  if v_sub.status = 'cancelled' then
    raise exception 'cannot grant a grace period to a cancelled subscription';
  end if;

  update organization_subscriptions set status = 'grace_period', grace_period_ends_at = p_grace_ends_at, updated_at = now()
  where id = v_sub.id returning * into v_sub;

  perform log_domain_event(p_organization_id, 'SUBSCRIPTION_GRACE_PERIOD_STARTED', 'organization', p_organization_id,
    jsonb_build_object('subscription_id', v_sub.id, 'grace_period_ends_at', p_grace_ends_at, 'reason', p_reason));
  perform log_audit_event(p_organization_id, 'organization_subscription', v_sub.id, 'grace_period_granted', null, jsonb_build_object('grace_period_ends_at', p_grace_ends_at, 'reason', p_reason));

  return v_sub;
end;
$$;

revoke execute on function grant_subscription_grace_period(uuid, timestamptz, text) from public, anon, authenticated;
grant execute on function grant_subscription_grace_period(uuid, timestamptz, text) to authenticated;

create or replace function end_subscription_grace_period(p_organization_id uuid, p_resulting_status text, p_reason text default null)
returns organization_subscriptions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sub organization_subscriptions%rowtype;
begin
  if not is_kcc_admin() then
    raise exception 'only KCC platform staff can end a grace period';
  end if;
  if p_resulting_status not in ('active', 'past_due', 'cancelled') then
    raise exception 'invalid resulting status: %', p_resulting_status;
  end if;

  select * into v_sub from organization_subscriptions where organization_id = p_organization_id and superseded_at is null for update;
  if v_sub.id is null then
    raise exception 'no current subscription for this organization';
  end if;
  if v_sub.status != 'grace_period' then
    raise exception 'subscription is not currently in a grace period (status: %)', v_sub.status;
  end if;

  update organization_subscriptions set status = p_resulting_status, grace_period_ends_at = now(), updated_at = now(),
    cancelled_at = case when p_resulting_status = 'cancelled' then now() else cancelled_at end,
    cancelled_by = case when p_resulting_status = 'cancelled' then auth.uid() else cancelled_by end,
    cancellation_reason = case when p_resulting_status = 'cancelled' then p_reason else cancellation_reason end
  where id = v_sub.id returning * into v_sub;

  perform log_domain_event(p_organization_id, 'SUBSCRIPTION_GRACE_PERIOD_ENDED', 'organization', p_organization_id,
    jsonb_build_object('subscription_id', v_sub.id, 'resulting_status', p_resulting_status, 'reason', p_reason));
  perform log_audit_event(p_organization_id, 'organization_subscription', v_sub.id, 'grace_period_ended', null, jsonb_build_object('resulting_status', p_resulting_status));

  return v_sub;
end;
$$;

revoke execute on function end_subscription_grace_period(uuid, text, text) from public, anon, authenticated;
grant execute on function end_subscription_grace_period(uuid, text, text) to authenticated;
