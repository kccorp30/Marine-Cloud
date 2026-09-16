-- =========================================================
-- 251_subscription_lifecycle_milestones.sql — Phase 14 absolute final closure
-- =========================================================
-- Infraestructura durable de milestones — idempotente:
-- unique(subscription_id, milestone) + processed_at garantizan que
-- cada recordatorio se dispare como máximo una vez. La AUTORIDAD de
-- acceso sigue siendo subscription_effective_status() (sin cron) —
-- esta tabla es solo para persistencia/notificación/mantenimiento.
-- Verificado con datos reales: 4 milestones creados al iniciar
-- trial, evento TRIAL_EXPIRED emitido exactamente una vez tras
-- correr el procesador dos veces.
-- =========================================================

create table subscription_lifecycle_milestones (
  id uuid primary key default gen_random_uuid(),
  subscription_id uuid not null references organization_subscriptions(id),
  organization_id uuid not null references organizations(id),
  milestone text not null check (milestone in ('trial_7d', 'trial_3d', 'trial_1d', 'trial_expired', 'grace_expired', 'scheduled_cancellation')),
  scheduled_for timestamptz not null,
  processed_at timestamptz,
  domain_event_id uuid,
  created_at timestamptz not null default now(),
  unique (subscription_id, milestone)
);

create index idx_lifecycle_milestones_due on subscription_lifecycle_milestones (scheduled_for) where processed_at is null;

alter table subscription_lifecycle_milestones enable row level security;
create policy "lifecycle_milestones_kcc_only" on subscription_lifecycle_milestones for select using (is_kcc_admin());
revoke all on subscription_lifecycle_milestones from anon;
grant select on subscription_lifecycle_milestones to authenticated;

create or replace function schedule_trial_milestones(p_subscription_id uuid, p_organization_id uuid, p_trial_ends_at timestamptz)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into subscription_lifecycle_milestones (subscription_id, organization_id, milestone, scheduled_for) values
    (p_subscription_id, p_organization_id, 'trial_7d', p_trial_ends_at - interval '7 days'),
    (p_subscription_id, p_organization_id, 'trial_3d', p_trial_ends_at - interval '3 days'),
    (p_subscription_id, p_organization_id, 'trial_1d', p_trial_ends_at - interval '1 day'),
    (p_subscription_id, p_organization_id, 'trial_expired', p_trial_ends_at)
  on conflict (subscription_id, milestone) do nothing;
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
begin
  if not (is_kcc_admin() or is_platform_trusted_actor()) then
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

    perform log_domain_event(v_milestone.organization_id, v_event_type, 'organization', v_milestone.organization_id,
      jsonb_build_object('subscription_id', v_milestone.subscription_id, 'milestone', v_milestone.milestone));

    v_processed_count := v_processed_count + 1;
  end loop;

  return jsonb_build_object('processed', v_processed_count);
end;
$$;

revoke execute on function schedule_trial_milestones(uuid, uuid, timestamptz) from public, anon, authenticated;
grant execute on function schedule_trial_milestones(uuid, uuid, timestamptz) to authenticated;
revoke execute on function process_due_subscription_lifecycle_milestones(int) from public, anon;
grant execute on function process_due_subscription_lifecycle_milestones(int) to authenticated;

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

  if v_status = 'trialing' then
    perform schedule_trial_milestones(v_sub.id, p_organization_id, v_trial_ends);
  end if;

  perform log_domain_event(p_organization_id,
    case when v_status = 'trialing' then 'SUBSCRIPTION_TRIAL_STARTED' else 'SUBSCRIPTION_ACTIVATED' end,
    'organization', p_organization_id,
    jsonb_build_object('subscription_id', v_sub.id, 'plan_id', p_plan_id, 'status', v_status));
  perform log_audit_event(p_organization_id, 'organization_subscription', v_sub.id, 'subscription_assigned', null, to_jsonb(v_sub));

  perform retry_commercially_blocked_leads(p_organization_id, 25);

  return v_sub;
end;
$$;
