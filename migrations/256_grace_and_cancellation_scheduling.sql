-- =========================================================
-- 256_grace_and_cancellation_scheduling.sql — Phase 14 lifecycle consistency
-- =========================================================
-- BUG #3: grant_subscription_grace_period() nunca programaba
-- 'grace_expired'. BUG #4: cancel_subscription(immediately=false)
-- nunca programaba 'scheduled_cancellation'. BUG #5: emitía
-- SUBSCRIPTION_CANCELLED de inmediato aunque el acceso seguía activo
-- — ahora emite SUBSCRIPTION_CANCELLATION_SCHEDULED, solo el
-- procesador emite CANCELLED real al llegar la fecha. ITEM #6: el
-- procesador persiste el status almacenado (grace_expired->past_due,
-- scheduled_cancellation->cancelled+cancelled_at) sin depender de
-- cron para autorización.
-- Verificado con datos reales: 15/15 PASS — scheduling, reprogramación,
-- fin manual sin evento fantasma, vencimiento exactamente una vez,
-- persistencia de status, cancelación inmediata sigue funcionando.
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

  insert into subscription_lifecycle_milestones (subscription_id, organization_id, milestone, scheduled_for, processed_at)
  values (v_sub.id, p_organization_id, 'grace_expired', p_grace_ends_at, null)
  on conflict (subscription_id, milestone) do update set scheduled_for = p_grace_ends_at, processed_at = null;

  perform log_domain_event(p_organization_id, 'SUBSCRIPTION_GRACE_PERIOD_STARTED', 'organization', p_organization_id,
    jsonb_build_object('subscription_id', v_sub.id, 'grace_period_ends_at', p_grace_ends_at, 'reason', p_reason));
  perform log_audit_event(p_organization_id, 'organization_subscription', v_sub.id, 'grace_period_granted', null, jsonb_build_object('grace_period_ends_at', p_grace_ends_at, 'reason', p_reason));

  return v_sub;
end;
$$;

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

  update subscription_lifecycle_milestones set processed_at = now()
  where subscription_id = v_sub.id and milestone = 'grace_expired' and processed_at is null;

  perform log_domain_event(p_organization_id, 'SUBSCRIPTION_GRACE_PERIOD_ENDED', 'organization', p_organization_id,
    jsonb_build_object('subscription_id', v_sub.id, 'resulting_status', p_resulting_status, 'reason', p_reason));
  perform log_audit_event(p_organization_id, 'organization_subscription', v_sub.id, 'grace_period_ended', null, jsonb_build_object('resulting_status', p_resulting_status));

  return v_sub;
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

    update subscription_lifecycle_milestones set processed_at = now()
    where subscription_id = v_sub.id and milestone = 'scheduled_cancellation' and processed_at is null;

    perform log_domain_event(p_organization_id, 'SUBSCRIPTION_CANCELLED', 'organization', p_organization_id,
      jsonb_build_object('subscription_id', v_sub.id, 'immediately', true, 'reason', p_reason));
  else
    v_period_end := coalesce(v_sub.current_period_ends_at, calculate_period_end(coalesce(v_sub.current_period_started_at, v_sub.subscription_started_at, v_sub.created_at), v_sub.billing_cycle));
    if v_period_end is null then
      raise exception 'cannot schedule end-of-period cancellation — this subscription has no determinable period end (billing_cycle=%); use immediate cancellation instead', v_sub.billing_cycle;
    end if;
    update organization_subscriptions set cancel_at_period_end = true, current_period_ends_at = v_period_end, cancelled_by = auth.uid(), cancellation_reason = p_reason, updated_at = now()
    where id = v_sub.id returning * into v_sub;

    insert into subscription_lifecycle_milestones (subscription_id, organization_id, milestone, scheduled_for, processed_at)
    values (v_sub.id, p_organization_id, 'scheduled_cancellation', v_period_end, null)
    on conflict (subscription_id, milestone) do update set scheduled_for = v_period_end, processed_at = null;

    perform log_domain_event(p_organization_id, 'SUBSCRIPTION_CANCELLATION_SCHEDULED', 'organization', p_organization_id,
      jsonb_build_object('subscription_id', v_sub.id, 'scheduled_for', v_period_end, 'reason', p_reason));
  end if;

  perform log_audit_event(p_organization_id, 'organization_subscription', v_sub.id, 'subscription_cancelled', null, jsonb_build_object('immediately', p_immediately, 'reason', p_reason));

  return v_sub;
end;
$$;

create or replace function process_due_subscription_lifecycle_milestones(p_batch_size int default 100)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_milestone subscription_lifecycle_milestones%rowtype;
  v_event_type text;
  v_processed_count int := 0;
  v_has_jwt_context boolean;
begin
  v_has_jwt_context := current_setting('request.jwt.claims', true) is not null and current_setting('request.jwt.claims', true) != '';

  if v_has_jwt_context and not (is_kcc_admin() or is_platform_trusted_actor()) then
    raise exception 'not authorized to process lifecycle milestones';
  end if;

  for v_milestone in
    select * from subscription_lifecycle_milestones
    where processed_at is null and scheduled_for <= now()
    order by scheduled_for asc
    limit p_batch_size
    for update skip locked
  loop
    v_event_type := case v_milestone.milestone
      when 'trial_7d' then 'SUBSCRIPTION_TRIAL_7_DAYS_REMAINING'
      when 'trial_3d' then 'SUBSCRIPTION_TRIAL_3_DAYS_REMAINING'
      when 'trial_1d' then 'SUBSCRIPTION_TRIAL_1_DAY_REMAINING'
      when 'trial_expired' then 'SUBSCRIPTION_TRIAL_EXPIRED'
      when 'grace_expired' then 'SUBSCRIPTION_GRACE_PERIOD_EXPIRED'
      when 'scheduled_cancellation' then 'SUBSCRIPTION_CANCELLED'
    end;

    update subscription_lifecycle_milestones set processed_at = now() where id = v_milestone.id;

    if v_milestone.milestone = 'grace_expired' then
      update organization_subscriptions set status = 'past_due', updated_at = now()
      where id = v_milestone.subscription_id and superseded_at is null and status = 'grace_period';
    elsif v_milestone.milestone = 'scheduled_cancellation' then
      update organization_subscriptions set status = 'cancelled', cancelled_at = now(), updated_at = now()
      where id = v_milestone.subscription_id and superseded_at is null and status != 'cancelled';
    end if;

    perform log_domain_event(v_milestone.organization_id, v_event_type, 'organization', v_milestone.organization_id,
      jsonb_build_object('subscription_id', v_milestone.subscription_id, 'milestone', v_milestone.milestone));

    v_processed_count := v_processed_count + 1;
  end loop;

  return jsonb_build_object('processed', v_processed_count);
end;
$$;
