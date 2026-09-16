-- =========================================================
-- 276_phase3_dispatch_mission_control.sql
-- Approved estimate -> scheduled work order -> technician dispatch
-- Uses the existing transition_work_order() state machine as the only
-- way to advance status. No direct current_status updates.
-- =========================================================

create or replace function public.activate_approved_estimate_work_order(p_estimate_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_est estimates%rowtype;
  v_wo work_orders%rowtype;
  v_id uuid;
begin
  select * into v_est from estimates where id=p_estimate_id for update;
  if v_est.id is null then raise exception 'estimate not found'; end if;
  if not (is_kcc_admin() or is_org_staff(v_est.organization_id)) then raise exception 'not authorized'; end if;
  if v_est.status <> 'approved' then raise exception 'estimate must be approved first'; end if;

  v_id := convert_estimate_to_work_order(p_estimate_id);
  select * into v_wo from work_orders where id=v_id for update;

  -- Progress only through the canonical machine. This makes a work order
  -- born from an already-approved estimate immediately ready for dispatch,
  -- while preserving complete status history/domain events.
  if v_wo.current_status='request_received' then
    perform transition_work_order(v_id,'triage','Approved estimate activated');
    select * into v_wo from work_orders where id=v_id;
  end if;
  if v_wo.current_status='triage' then
    perform transition_work_order(v_id,'estimate','Estimate already approved');
    select * into v_wo from work_orders where id=v_id;
  end if;
  if v_wo.current_status='estimate' then
    perform transition_work_order(v_id,'awaiting_approval','Customer approval already recorded');
    select * into v_wo from work_orders where id=v_id;
  end if;
  if v_wo.current_status='awaiting_approval' then
    perform transition_work_order(v_id,'scheduled','Customer approved estimate');
  end if;

  return v_id;
end;
$$;
revoke all on function public.activate_approved_estimate_work_order(uuid) from public, anon;
grant execute on function public.activate_approved_estimate_work_order(uuid) to authenticated;

create or replace function public.dispatch_work_order(
  p_work_order_id uuid,
  p_technician_profile_id uuid,
  p_scheduled_start timestamptz,
  p_purpose text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_wo work_orders%rowtype;
  v_appt appointments%rowtype;
  v_assignment assignments%rowtype;
  v_existing assignments%rowtype;
begin
  select * into v_wo from work_orders where id=p_work_order_id for update;
  if v_wo.id is null then raise exception 'work order not found'; end if;
  if not (is_kcc_admin() or is_org_staff(v_wo.organization_id)) then raise exception 'not authorized'; end if;

  if not exists(
    select 1 from organization_memberships
    where organization_id=v_wo.organization_id
      and profile_id=p_technician_profile_id
      and role='technician' and status='active'
  ) then raise exception 'technician is not an active member of this company'; end if;

  if p_scheduled_start is null then raise exception 'schedule is required'; end if;
  if v_wo.current_status not in ('scheduled','technician_assigned') then
    raise exception 'work order must be ready for scheduling before dispatch (status: %)',v_wo.current_status;
  end if;

  select * into v_existing from assignments
  where work_order_id=p_work_order_id and status='active'
  order by assigned_at desc limit 1 for update;

  -- Appointment: reuse the latest active appointment when possible so a
  -- re-dispatch updates one mission instead of producing duplicates.
  select * into v_appt from appointments
  where work_order_id=p_work_order_id and status in ('scheduled','rescheduled')
  order by scheduled_start desc limit 1 for update;

  if v_appt.id is null then
    insert into appointments(organization_id,work_order_id,scheduled_start,purpose,status)
    values(v_wo.organization_id,p_work_order_id,p_scheduled_start,nullif(trim(p_purpose),''),'scheduled')
    returning * into v_appt;
  else
    update appointments
      set scheduled_start=p_scheduled_start,
          purpose=coalesce(nullif(trim(p_purpose),''),purpose),
          status=case when v_appt.scheduled_start is distinct from p_scheduled_start then 'rescheduled' else status end
      where id=v_appt.id returning * into v_appt;
  end if;

  if v_existing.id is not null and v_existing.technician_profile_id=p_technician_profile_id then
    update assignments set appointment_id=v_appt.id where id=v_existing.id returning * into v_assignment;
  else
    if v_existing.id is not null then
      update assignments set status='removed',removed_at=now() where id=v_existing.id;
    end if;
    insert into assignments(
      organization_id,work_order_id,appointment_id,technician_profile_id,
      role_on_job,status,assigned_by
    ) values(
      v_wo.organization_id,p_work_order_id,v_appt.id,p_technician_profile_id,
      'primary','active',auth.uid()
    ) returning * into v_assignment;
  end if;

  if v_wo.current_status='scheduled' then
    perform transition_work_order(p_work_order_id,'technician_assigned','Technician dispatched');
  end if;

  return jsonb_build_object(
    'work_order_id',p_work_order_id,
    'appointment_id',v_appt.id,
    'assignment_id',v_assignment.id,
    'technician_profile_id',p_technician_profile_id,
    'scheduled_start',v_appt.scheduled_start
  );
end;
$$;
revoke all on function public.dispatch_work_order(uuid,uuid,timestamptz,text) from public, anon;
grant execute on function public.dispatch_work_order(uuid,uuid,timestamptz,text) to authenticated;

-- Company attention for a technician becoming en route / arriving / work started.
-- Customer notifications already flow from the existing domain-event engine.
create or replace function private.phase3_company_status_attention() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if new.current_status is distinct from old.current_status then
    if new.current_status='en_route' then
      perform private.notify_company_operations(new.organization_id,'TECHNICIAN_EN_ROUTE','info','Technician en route','The assigned technician has started the route to the customer.','work_order',new.id,false);
    elsif new.current_status='checked_in' then
      perform private.notify_company_operations(new.organization_id,'TECHNICIAN_ARRIVED','info','Technician arrived','The technician has checked in at the service location.','work_order',new.id,false);
    elsif new.current_status='work_in_progress' then
      perform private.notify_company_operations(new.organization_id,'WORK_STARTED','info','Work started','The assigned technician started work on the vessel.','work_order',new.id,false);
    elsif new.current_status='quality_control' then
      perform private.notify_company_operations(new.organization_id,'QC_READY','action_required','Work ready for QC','Technician work is ready for quality-control review.','work_order',new.id,true);
    end if;
  end if;
  return new;
end;$$;
drop trigger if exists trg_phase3_company_status_attention on public.work_orders;
create trigger trg_phase3_company_status_attention
  after update of current_status on public.work_orders
  for each row execute function private.phase3_company_status_attention();
