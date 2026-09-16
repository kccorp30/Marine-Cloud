-- =========================================================
-- 224_trial_extension_and_cancellation_rpcs.sql — Marine Cloud Phase 14
-- =========================================================
-- extend_organization_trial: solo kcc_admin, nunca fecha pasada,
-- audita antes/después. cancel_subscription: inmediato o al fin del
-- período — nunca borra datos de la compañía. grant/remove_
-- complimentary_access: categoría propia, nunca $0 fake payment.
-- Verificado con datos reales: técnico bloqueado, kcc_admin extiende
-- y restaura acceso, cancelación inmediata deniega acceso sin borrar
-- datos, complimentary concede acceso.
-- =========================================================

create or replace function extend_organization_trial(p_organization_id uuid, p_new_trial_ends_at timestamptz, p_reason text default null)
returns organization_subscriptions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sub organization_subscriptions%rowtype;
  v_before timestamptz;
begin
  if not is_kcc_admin() then
    raise exception 'only KCC platform staff can extend a trial';
  end if;

  select * into v_sub from organization_subscriptions where organization_id = p_organization_id and superseded_at is null for update;
  if v_sub.id is null then
    raise exception 'no current subscription for this organization';
  end if;
  if v_sub.status not in ('trialing') then
    raise exception 'trial can only be extended while status is trialing (current: %)', v_sub.status;
  end if;
  if p_new_trial_ends_at <= now() then
    raise exception 'new trial end date must be in the future';
  end if;

  v_before := v_sub.trial_ends_at;

  update organization_subscriptions set trial_ends_at = p_new_trial_ends_at, updated_at = now()
  where id = v_sub.id returning * into v_sub;

  perform log_domain_event(p_organization_id, 'SUBSCRIPTION_TRIAL_EXTENDED', 'organization', p_organization_id,
    jsonb_build_object('subscription_id', v_sub.id, 'previous_trial_ends_at', v_before, 'new_trial_ends_at', p_new_trial_ends_at, 'reason', p_reason));
  perform log_audit_event(p_organization_id, 'organization_subscription', v_sub.id, 'trial_extended',
    jsonb_build_object('trial_ends_at', v_before), jsonb_build_object('trial_ends_at', p_new_trial_ends_at, 'reason', p_reason));

  return v_sub;
end;
$$;

revoke execute on function extend_organization_trial(uuid, timestamptz, text) from public, anon, authenticated;
grant execute on function extend_organization_trial(uuid, timestamptz, text) to authenticated;

create or replace function cancel_subscription(p_organization_id uuid, p_immediately boolean, p_reason text default null)
returns organization_subscriptions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sub organization_subscriptions%rowtype;
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
    update organization_subscriptions set cancel_at_period_end = true, cancelled_by = auth.uid(), cancellation_reason = p_reason, updated_at = now()
    where id = v_sub.id returning * into v_sub;
  end if;

  perform log_domain_event(p_organization_id, 'SUBSCRIPTION_CANCELLED', 'organization', p_organization_id,
    jsonb_build_object('subscription_id', v_sub.id, 'immediately', p_immediately, 'reason', p_reason));
  perform log_audit_event(p_organization_id, 'organization_subscription', v_sub.id, 'subscription_cancelled', null, jsonb_build_object('immediately', p_immediately, 'reason', p_reason));

  return v_sub;
end;
$$;

revoke execute on function cancel_subscription(uuid, boolean, text) from public, anon, authenticated;
grant execute on function cancel_subscription(uuid, boolean, text) to authenticated;

create or replace function grant_complimentary_access(p_organization_id uuid, p_reason text)
returns organization_subscriptions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sub organization_subscriptions%rowtype;
begin
  if not is_kcc_admin() then
    raise exception 'only KCC platform staff can grant complimentary access';
  end if;
  if p_reason is null or trim(p_reason) = '' then
    raise exception 'a reason is required for complimentary access';
  end if;

  select * into v_sub from organization_subscriptions where organization_id = p_organization_id and superseded_at is null for update;
  if v_sub.id is null then
    raise exception 'no current subscription for this organization — use assign_organization_subscription first';
  end if;

  update organization_subscriptions set complimentary = true, complimentary_reason = p_reason, updated_at = now()
  where id = v_sub.id returning * into v_sub;

  perform log_audit_event(p_organization_id, 'organization_subscription', v_sub.id, 'complimentary_granted', null, jsonb_build_object('reason', p_reason));

  return v_sub;
end;
$$;

revoke execute on function grant_complimentary_access(uuid, text) from public, anon, authenticated;
grant execute on function grant_complimentary_access(uuid, text) to authenticated;

create or replace function remove_complimentary_access(p_organization_id uuid)
returns organization_subscriptions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sub organization_subscriptions%rowtype;
begin
  if not is_kcc_admin() then
    raise exception 'only KCC platform staff can remove complimentary access';
  end if;

  select * into v_sub from organization_subscriptions where organization_id = p_organization_id and superseded_at is null for update;
  if v_sub.id is null then
    raise exception 'no current subscription for this organization';
  end if;

  update organization_subscriptions set complimentary = false, updated_at = now()
  where id = v_sub.id returning * into v_sub;

  perform log_audit_event(p_organization_id, 'organization_subscription', v_sub.id, 'complimentary_removed', null, null);

  return v_sub;
end;
$$;

revoke execute on function remove_complimentary_access(uuid) from public, anon, authenticated;
grant execute on function remove_complimentary_access(uuid) to authenticated;
