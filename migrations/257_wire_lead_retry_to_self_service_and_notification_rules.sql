-- =========================================================
-- 257_wire_lead_retry_to_self_service_and_notification_rules.sql — Phase 14 lifecycle consistency
-- =========================================================
-- retry_commercially_blocked_leads() ahora también se invoca desde
-- select_organization_plan() (auto-servicio) — el flujo real más
-- común (trial vence -> owner elige plan) ahora reintenta leads
-- bloqueados automáticamente. Agregadas reglas de notificación
-- faltantes: SUBSCRIPTION_CANCELLATION_SCHEDULED, SUBSCRIPTION_
-- GRACE_PERIOD_EXPIRED.
-- =========================================================

create or replace function select_organization_plan(p_organization_id uuid, p_plan_id uuid, p_billing_cycle text)
returns organization_subscriptions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_role text;
  v_plan subscription_plans%rowtype;
  v_current organization_subscriptions%rowtype;
  v_effective_price numeric;
  v_current_effective text;
  v_new_sub organization_subscriptions%rowtype;
begin
  select role into v_actor_role from organization_memberships
  where profile_id = auth.uid() and organization_id = p_organization_id and status = 'active';
  if v_actor_role not in ('company_owner', 'company_admin') then
    raise exception 'only the company owner/admin can select a plan for their own organization';
  end if;
  if p_billing_cycle not in ('weekly', 'monthly', 'annual') then
    raise exception 'invalid billing cycle for self-service plan selection: %', p_billing_cycle;
  end if;

  select * into v_plan from subscription_plans where id = p_plan_id;
  if v_plan.id is null or v_plan.is_public is not true or v_plan.status != 'active' or v_plan.is_custom = true then
    raise exception 'this plan is not available for self-service selection';
  end if;

  select * into v_current from organization_subscriptions where organization_id = p_organization_id and superseded_at is null for update;
  if v_current.id is not null then
    v_current_effective := subscription_effective_status(v_current.status, v_current.trial_ends_at, v_current.grace_period_ends_at, v_current.complimentary, v_current.cancel_at_period_end, v_current.current_period_ends_at);
    if v_current_effective not in ('trial_expired', 'cancelled') then
      raise exception 'a plan can only be self-selected when there is no active subscription or the trial has expired/subscription was cancelled (current effective status: %)', v_current_effective;
    end if;
    update organization_subscriptions set superseded_at = now(), updated_at = now() where id = v_current.id;
  end if;

  v_effective_price := case p_billing_cycle
    when 'weekly' then v_plan.weekly_price
    when 'monthly' then v_plan.monthly_price
    when 'annual' then v_plan.annual_price
  end;
  if v_effective_price is null then
    raise exception 'this plan does not have a configured price for the % billing cycle', p_billing_cycle;
  end if;

  insert into organization_subscriptions (organization_id, plan_id, status, billing_cycle, currency, price_snapshot, subscription_started_at, current_period_started_at, current_period_ends_at, created_by)
  values (p_organization_id, p_plan_id, 'active', p_billing_cycle, v_plan.currency, v_effective_price, now(), now(), calculate_period_end(now(), p_billing_cycle), auth.uid())
  returning * into v_new_sub;

  perform log_domain_event(p_organization_id, 'SUBSCRIPTION_ACTIVATED', 'organization', p_organization_id,
    jsonb_build_object('subscription_id', v_new_sub.id, 'plan_id', p_plan_id, 'self_service', true));
  perform log_audit_event(p_organization_id, 'organization_subscription', v_new_sub.id, 'plan_self_selected', null, to_jsonb(v_new_sub));

  perform retry_commercially_blocked_leads(p_organization_id, 25);

  return v_new_sub;
end;
$$;

insert into notification_rules (organization_id, event_type, payload_filter, severity, recipient_strategy, title_template, body_template, acknowledgement_required) values
  (null, 'SUBSCRIPTION_CANCELLATION_SCHEDULED', null, 'action_required', 'billing_admin', 'Your subscription is scheduled to end', 'Your Marine Cloud subscription is scheduled to end at the close of your current billing period. Your access remains active until then.', false),
  (null, 'SUBSCRIPTION_GRACE_PERIOD_EXPIRED', null, 'action_required', 'billing_admin', 'Your grace period has ended', 'Your Marine Cloud grace period has ended. Please restore your subscription to continue full access.', false)
on conflict do nothing;
