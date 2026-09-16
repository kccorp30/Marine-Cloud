-- =========================================================
-- 231_select_organization_plan_self_service.sql — Marine Cloud Phase 14
-- =========================================================
-- RPC separada y más restringida que change_subscription_plan(): un
-- company_owner/company_admin de SU PROPIA organización puede elegir
-- un plan PÚBLICO Y ACTIVO cuando no hay suscripción vigente o la
-- vigente quedó trial_expired/cancelled — nunca custom/oculto/
-- complimentary. Nunca puede alterar precio/trial/términos.
-- Verificado con datos reales: técnico bloqueado, owner selecciona
-- plan público tras trial vencido con price_snapshot correcto, owner
-- bloqueado de seleccionar un plan custom/no público.
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
  if v_plan.id is null or v_plan.is_public is not true or v_plan.status != 'active' then
    raise exception 'this plan is not available for self-service selection';
  end if;

  select * into v_current from organization_subscriptions where organization_id = p_organization_id and superseded_at is null for update;
  if v_current.id is not null then
    v_current_effective := subscription_effective_status(v_current.status, v_current.trial_ends_at, v_current.grace_period_ends_at, v_current.complimentary);
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

  insert into organization_subscriptions (organization_id, plan_id, status, billing_cycle, currency, price_snapshot, subscription_started_at, current_period_started_at, created_by)
  values (p_organization_id, p_plan_id, 'active', p_billing_cycle, v_plan.currency, v_effective_price, now(), now(), auth.uid())
  returning * into v_new_sub;

  perform log_domain_event(p_organization_id, 'SUBSCRIPTION_ACTIVATED', 'organization', p_organization_id,
    jsonb_build_object('subscription_id', v_new_sub.id, 'plan_id', p_plan_id, 'self_service', true));
  perform log_audit_event(p_organization_id, 'organization_subscription', v_new_sub.id, 'plan_self_selected', null, to_jsonb(v_new_sub));

  return v_new_sub;
end;
$$;

revoke execute on function select_organization_plan(uuid, uuid, text) from public, anon;
grant execute on function select_organization_plan(uuid, uuid, text) to authenticated;
