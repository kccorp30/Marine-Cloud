-- =========================================================
-- 232_period_calculation_and_cancellation_fix.sql — Phase 14 final integrity
-- =========================================================
-- BUG REAL: cancel_subscription(immediately=false) nunca fijaba
-- current_period_ends_at real y subscription_effective_status()
-- ignoraba cancel_at_period_end por completo — la cancelación
-- programada nunca se volvía efectiva. calculate_period_end() deriva
-- el fin real (weekly/monthly/annual; custom nunca inventa fecha).
--
-- BUG REAL #2: remove_complimentary_access() dejaba
-- status='complimentary' — el efectivo seguía devolviendo
-- 'complimentary' después de que KCC lo quitó. Corregido: decide el
-- siguiente estado real (active si hay price_snapshot, cancelled si
-- no).
-- Verificado con datos reales: remoción revierte a active/cancelled
-- según corresponda, cancelación al fin de período sigue activa
-- antes de la fecha y efectivamente cancelada después, sin cron.
-- =========================================================

create or replace function calculate_period_end(p_started_at timestamptz, p_billing_cycle text)
returns timestamptz
language sql
immutable
as $$
  select case p_billing_cycle
    when 'weekly' then p_started_at + interval '7 days'
    when 'monthly' then p_started_at + interval '1 month'
    when 'annual' then p_started_at + interval '1 year'
    else null
  end;
$$;

create or replace function subscription_effective_status(
  p_status text, p_trial_ends_at timestamptz, p_grace_period_ends_at timestamptz, p_complimentary boolean,
  p_cancel_at_period_end boolean default false, p_current_period_ends_at timestamptz default null
)
returns text
language sql
stable
as $$
  select case
    when p_complimentary then 'complimentary'
    when p_status = 'cancelled' then 'cancelled'
    when p_cancel_at_period_end and p_current_period_ends_at is not null and p_current_period_ends_at <= now() then 'cancelled'
    when p_status = 'trialing' and p_trial_ends_at is not null and p_trial_ends_at < now() then 'trial_expired'
    when p_status = 'grace_period' and p_grace_period_ends_at is not null and p_grace_period_ends_at < now() then 'past_due'
    else p_status
  end;
$$;

create or replace view organization_subscription_effective as
select os.*, subscription_effective_status(os.status, os.trial_ends_at, os.grace_period_ends_at, os.complimentary, os.cancel_at_period_end, os.current_period_ends_at) as effective_status
from organization_subscriptions os where os.superseded_at is null;

alter view organization_subscription_effective set (security_invoker = true);

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
  v_effective := subscription_effective_status(v_sub.status, v_sub.trial_ends_at, v_sub.grace_period_ends_at, v_sub.complimentary, v_sub.cancel_at_period_end, v_sub.current_period_ends_at);
  return v_effective in ('trialing', 'active', 'grace_period', 'complimentary');
end;
$$;

create or replace function cancel_subscription(p_organization_id uuid, p_immediately boolean, p_reason text default null)
returns organization_subscriptions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sub organization_subscriptions%rowtype;
  v_period_end timestamptz;
begin
  if not is_kcc_admin() then
    raise exception 'only KCC platform staff can cancel a subscription';
  end if;
  select * into v_sub from organization_subscriptions where organization_id = p_organization_id and superseded_at is null for update;
  if v_sub.id is null then
    raise exception 'no current subscription for this organization';
  end if;
  if v_sub.status = 'cancelled' then
    return v_sub;
  end if;

  if p_immediately then
    update organization_subscriptions set status = 'cancelled', cancelled_at = now(), cancelled_by = auth.uid(), cancellation_reason = p_reason, cancel_at_period_end = false, updated_at = now()
    where id = v_sub.id returning * into v_sub;
  else
    v_period_end := coalesce(v_sub.current_period_ends_at, calculate_period_end(coalesce(v_sub.current_period_started_at, v_sub.subscription_started_at, v_sub.created_at), v_sub.billing_cycle));
    if v_period_end is null then
      raise exception 'cannot schedule end-of-period cancellation — this subscription has no determinable period end (billing_cycle=%); use immediate cancellation instead', v_sub.billing_cycle;
    end if;
    update organization_subscriptions set cancel_at_period_end = true, current_period_ends_at = v_period_end, cancelled_by = auth.uid(), cancellation_reason = p_reason, updated_at = now()
    where id = v_sub.id returning * into v_sub;
  end if;

  perform log_domain_event(p_organization_id, 'SUBSCRIPTION_CANCELLED', 'organization', p_organization_id,
    jsonb_build_object('subscription_id', v_sub.id, 'immediately', p_immediately, 'reason', p_reason, 'effective_end', v_period_end));
  perform log_audit_event(p_organization_id, 'organization_subscription', v_sub.id, 'subscription_cancelled', null, jsonb_build_object('immediately', p_immediately, 'reason', p_reason));

  return v_sub;
end;
$$;

create or replace function remove_complimentary_access(p_organization_id uuid)
returns organization_subscriptions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sub organization_subscriptions%rowtype;
  v_next_status text;
begin
  if not is_kcc_admin() then
    raise exception 'only KCC platform staff can remove complimentary access';
  end if;
  select * into v_sub from organization_subscriptions where organization_id = p_organization_id and superseded_at is null for update;
  if v_sub.id is null then
    raise exception 'no current subscription for this organization';
  end if;

  v_next_status := case when v_sub.price_snapshot is not null then 'active' else 'cancelled' end;

  update organization_subscriptions set
    complimentary = false, status = v_next_status,
    cancelled_at = case when v_next_status = 'cancelled' then now() else cancelled_at end,
    cancelled_by = case when v_next_status = 'cancelled' then auth.uid() else cancelled_by end,
    cancellation_reason = case when v_next_status = 'cancelled' then 'complimentary access removed with no underlying paid plan' else cancellation_reason end,
    updated_at = now()
  where id = v_sub.id returning * into v_sub;

  perform log_audit_event(p_organization_id, 'organization_subscription', v_sub.id, 'complimentary_removed', jsonb_build_object('status', 'complimentary'), jsonb_build_object('status', v_next_status));

  return v_sub;
end;
$$;
