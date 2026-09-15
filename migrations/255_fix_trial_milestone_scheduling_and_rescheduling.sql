-- =========================================================
-- 255_fix_trial_milestone_scheduling_and_rescheduling.sql — Phase 14 lifecycle consistency
-- =========================================================
-- BUG REAL #1: schedule_trial_milestones() siempre creaba los 4
-- milestones sin importar la duración real del trial — un trial
-- corto generaba milestones YA EN EL PASADO. Corregido: cada
-- milestone solo se crea si su fecha es realmente futura.
--
-- BUG REAL #2: extend_organization_trial() nunca actualizaba los
-- milestones — reminders y TRIAL_EXPIRED seguían la fecha vieja.
-- reschedule_trial_milestones() reprograma lo no procesado; lo ya
-- procesado nunca se reenvía; trial_expired siempre se realinea
-- (y se reabre si ya había disparado, para permitir un nuevo
-- vencimiento real tras la extensión).
-- Verificado con datos reales: trial de 2 días solo genera 1d+expired,
-- extensión reprograma correctamente incluyendo crear 7d/3d que antes
-- no eran elegibles.
-- =========================================================

create or replace function schedule_trial_milestones(p_subscription_id uuid, p_organization_id uuid, p_trial_ends_at timestamptz)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_trial_ends_at - interval '7 days' > now() then
    insert into subscription_lifecycle_milestones (subscription_id, organization_id, milestone, scheduled_for)
    values (p_subscription_id, p_organization_id, 'trial_7d', p_trial_ends_at - interval '7 days')
    on conflict (subscription_id, milestone) do nothing;
  end if;
  if p_trial_ends_at - interval '3 days' > now() then
    insert into subscription_lifecycle_milestones (subscription_id, organization_id, milestone, scheduled_for)
    values (p_subscription_id, p_organization_id, 'trial_3d', p_trial_ends_at - interval '3 days')
    on conflict (subscription_id, milestone) do nothing;
  end if;
  if p_trial_ends_at - interval '1 day' > now() then
    insert into subscription_lifecycle_milestones (subscription_id, organization_id, milestone, scheduled_for)
    values (p_subscription_id, p_organization_id, 'trial_1d', p_trial_ends_at - interval '1 day')
    on conflict (subscription_id, milestone) do nothing;
  end if;
  insert into subscription_lifecycle_milestones (subscription_id, organization_id, milestone, scheduled_for)
  values (p_subscription_id, p_organization_id, 'trial_expired', p_trial_ends_at)
  on conflict (subscription_id, milestone) do nothing;
end;
$$;

create or replace function reschedule_trial_milestones(p_subscription_id uuid, p_organization_id uuid, p_new_trial_ends_at timestamptz)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_milestone text;
  v_new_scheduled_for timestamptz;
begin
  foreach v_milestone in array array['trial_7d', 'trial_3d', 'trial_1d'] loop
    v_new_scheduled_for := p_new_trial_ends_at - case v_milestone
      when 'trial_7d' then interval '7 days'
      when 'trial_3d' then interval '3 days'
      when 'trial_1d' then interval '1 day'
    end;

    if v_new_scheduled_for > now() then
      update subscription_lifecycle_milestones set scheduled_for = v_new_scheduled_for
      where subscription_id = p_subscription_id and milestone = v_milestone and processed_at is null;

      insert into subscription_lifecycle_milestones (subscription_id, organization_id, milestone, scheduled_for)
      values (p_subscription_id, p_organization_id, v_milestone, v_new_scheduled_for)
      on conflict (subscription_id, milestone) do nothing;
    else
      delete from subscription_lifecycle_milestones
      where subscription_id = p_subscription_id and milestone = v_milestone and processed_at is null;
    end if;
  end loop;

  update subscription_lifecycle_milestones set scheduled_for = p_new_trial_ends_at, processed_at = null
  where subscription_id = p_subscription_id and milestone = 'trial_expired';

  insert into subscription_lifecycle_milestones (subscription_id, organization_id, milestone, scheduled_for)
  values (p_subscription_id, p_organization_id, 'trial_expired', p_new_trial_ends_at)
  on conflict (subscription_id, milestone) do nothing;
end;
$$;

revoke execute on function reschedule_trial_milestones(uuid, uuid, timestamptz) from public, anon, authenticated;
grant execute on function reschedule_trial_milestones(uuid, uuid, timestamptz) to authenticated;

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

  perform reschedule_trial_milestones(v_sub.id, p_organization_id, p_new_trial_ends_at);

  perform log_domain_event(p_organization_id, 'SUBSCRIPTION_TRIAL_EXTENDED', 'organization', p_organization_id,
    jsonb_build_object('subscription_id', v_sub.id, 'previous_trial_ends_at', v_before, 'new_trial_ends_at', p_new_trial_ends_at, 'reason', p_reason));
  perform log_audit_event(p_organization_id, 'organization_subscription', v_sub.id, 'trial_extended',
    jsonb_build_object('trial_ends_at', v_before), jsonb_build_object('trial_ends_at', p_new_trial_ends_at, 'reason', p_reason));

  return v_sub;
end;
$$;
