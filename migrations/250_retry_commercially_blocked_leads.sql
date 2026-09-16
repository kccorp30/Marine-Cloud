-- =========================================================
-- 250_retry_commercially_blocked_leads.sql — Phase 14 absolute final closure
-- =========================================================
-- retry_commercially_blocked_leads(): bounded (max 100), solo leads
-- de esa organización con blocked_commercial, reusa convert_website_
-- lead() idempotente. Conectado automáticamente a assign_organization_
-- subscription() — activar una suscripción real reintenta los leads
-- bloqueados de esa organización, nunca cross-tenant, nunca sin límite.
-- Verificado con datos reales: lead bloqueado se convierte
-- automáticamente al activar suscripción, lead de otra organización
-- queda intacto, batch_size fuera de rango rechazado.
-- =========================================================

create or replace function retry_commercially_blocked_leads(p_organization_id uuid, p_batch_size int default 25)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lead_id uuid;
  v_result jsonb;
  v_converted_count int := 0;
  v_still_blocked_count int := 0;
  v_failed_count int := 0;
begin
  if not (is_kcc_admin() or is_platform_trusted_actor()) then
    raise exception 'not authorized to retry blocked leads';
  end if;
  if p_batch_size is null or p_batch_size <= 0 or p_batch_size > 100 then
    raise exception 'batch size must be between 1 and 100';
  end if;

  for v_lead_id in
    select id from leads
    where assigned_organization_id = p_organization_id and conversion_status = 'blocked_commercial'
    order by created_at asc
    limit p_batch_size
  loop
    begin
      v_result := convert_website_lead(v_lead_id);
      case v_result->>'status'
        when 'created' then v_converted_count := v_converted_count + 1;
        when 'blocked_commercial' then v_still_blocked_count := v_still_blocked_count + 1;
        else v_failed_count := v_failed_count + 1;
      end case;
    exception when others then
      v_failed_count := v_failed_count + 1;
    end;
  end loop;

  return jsonb_build_object('organization_id', p_organization_id, 'converted', v_converted_count, 'still_blocked', v_still_blocked_count, 'failed', v_failed_count);
end;
$$;

revoke execute on function retry_commercially_blocked_leads(uuid, int) from public, anon;
grant execute on function retry_commercially_blocked_leads(uuid, int) to authenticated;

create or replace function assign_organization_subscription(
  p_organization_id uuid, p_plan_id uuid, p_billing_cycle text,
  p_trial_days int default null, p_price_override numeric default null,
  p_complimentary boolean default false, p_complimentary_reason text default null, p_custom_terms text default null
)
returns organization_subscriptions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plan subscription_plans%rowtype;
  v_effective_price numeric;
  v_status text;
  v_trial_started timestamptz;
  v_trial_ends timestamptz;
  v_period_started timestamptz;
  v_sub organization_subscriptions%rowtype;
begin
  if not is_kcc_admin() then
    raise exception 'only KCC platform staff can assign a commercial subscription';
  end if;
  if not exists (select 1 from organizations where id = p_organization_id) then
    raise exception 'organization not found';
  end if;
  if p_billing_cycle not in ('weekly', 'monthly', 'annual', 'custom') then
    raise exception 'invalid billing cycle: %', p_billing_cycle;
  end if;
  if p_price_override is not null and p_price_override < 0 then
    raise exception 'price override cannot be negative';
  end if;
  if p_trial_days is not null and p_trial_days < 0 then
    raise exception 'trial days cannot be negative';
  end if;

  select * into v_plan from subscription_plans where id = p_plan_id;
  if v_plan.id is null then
    raise exception 'plan not found';
  end if;

  if p_complimentary then
    if p_complimentary_reason is null or trim(p_complimentary_reason) = '' then
      raise exception 'a reason is required for complimentary access';
    end if;
    v_status := 'complimentary';
    v_effective_price := null;
  elsif p_trial_days is not null and p_trial_days > 0 then
    v_status := 'trialing';
    v_trial_started := now();
    v_trial_ends := now() + (p_trial_days || ' days')::interval;
  else
    v_status := 'active';
    v_period_started := now();
  end if;

  if not p_complimentary then
    v_effective_price := coalesce(
      p_price_override,
      case p_billing_cycle
        when 'weekly' then v_plan.weekly_price
        when 'monthly' then v_plan.monthly_price
        when 'annual' then v_plan.annual_price
        else null
      end
    );
  end if;

  update organization_subscriptions set superseded_at = now(), updated_at = now()
  where organization_id = p_organization_id and superseded_at is null;

  insert into organization_subscriptions (
    organization_id, plan_id, status, billing_cycle, currency, price_snapshot,
    trial_started_at, trial_ends_at, subscription_started_at, current_period_started_at,
    current_period_ends_at,
    complimentary, complimentary_reason, custom_terms, price_override, created_by
  )
  values (
    p_organization_id, p_plan_id, v_status, p_billing_cycle, v_plan.currency, v_effective_price,
    v_trial_started, v_trial_ends, v_period_started, v_period_started,
    case when v_period_started is not null then calculate_period_end(v_period_started, p_billing_cycle) else null end,
    p_complimentary, p_complimentary_reason, p_custom_terms, p_price_override is not null, auth.uid()
  )
  returning * into v_sub;

  perform log_domain_event(p_organization_id,
    case when v_status = 'trialing' then 'SUBSCRIPTION_TRIAL_STARTED' else 'SUBSCRIPTION_ACTIVATED' end,
    'organization', p_organization_id,
    jsonb_build_object('subscription_id', v_sub.id, 'plan_id', p_plan_id, 'status', v_status));
  perform log_audit_event(p_organization_id, 'organization_subscription', v_sub.id, 'subscription_assigned', null, to_jsonb(v_sub));

  perform retry_commercially_blocked_leads(p_organization_id, 25);

  return v_sub;
end;
$$;
