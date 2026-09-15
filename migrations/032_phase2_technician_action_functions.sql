-- =========================================================
-- 032_phase2_technician_action_functions.sql — Marine Cloud Phase 2
-- =========================================================

create or replace function technician_start_route(p_work_order_id uuid)
returns work_orders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_wo work_orders;
begin
  v_wo := transition_work_order(p_work_order_id, 'en_route');
  perform log_domain_event(v_wo.organization_id, 'TECHNICIAN_EN_ROUTE', 'work_order', p_work_order_id, '{}'::jsonb);
  return v_wo;
end;
$$;
revoke execute on function technician_start_route(uuid) from public, anon;
grant execute on function technician_start_route(uuid) to authenticated;

create or replace function technician_check_in(
  p_appointment_id uuid,
  p_latitude double precision default null,
  p_longitude double precision default null,
  p_device_metadata jsonb default null
)
returns check_ins
language plpgsql
security definer
set search_path = public
as $$
declare
  v_appt appointments;
  v_checkin check_ins;
begin
  select * into v_appt from appointments where id = p_appointment_id;
  if v_appt.id is null then
    raise exception 'appointment not found';
  end if;

  if not (is_org_staff(v_appt.organization_id) or is_kcc_admin() or is_assigned_to_work_order(v_appt.work_order_id)) then
    raise exception 'not authorized to check in to this appointment';
  end if;

  select * into v_checkin from check_ins
  where appointment_id = p_appointment_id and technician_profile_id = auth.uid() and checked_out_at is null
  limit 1;
  if v_checkin.id is not null then
    return v_checkin;
  end if;

  insert into check_ins (organization_id, work_order_id, appointment_id, technician_profile_id, latitude, longitude, device_metadata)
  values (v_appt.organization_id, v_appt.work_order_id, p_appointment_id, auth.uid(), p_latitude, p_longitude, p_device_metadata)
  returning * into v_checkin;

  update appointments set actual_start = now(), status = 'in_progress' where id = p_appointment_id;

  perform log_domain_event(v_appt.organization_id, 'TECHNICIAN_CHECKED_IN', 'appointment', p_appointment_id,
    jsonb_build_object('work_order_id', v_appt.work_order_id, 'check_in_id', v_checkin.id));

  return v_checkin;
end;
$$;
revoke execute on function technician_check_in(uuid, double precision, double precision, jsonb) from public, anon;
grant execute on function technician_check_in(uuid, double precision, double precision, jsonb) to authenticated;

create or replace function technician_check_out(p_check_in_id uuid, p_closing_note text default null)
returns check_ins
language plpgsql
security definer
set search_path = public
as $$
declare
  v_checkin check_ins;
begin
  select * into v_checkin from check_ins where id = p_check_in_id;
  if v_checkin.id is null then
    raise exception 'check-in not found';
  end if;

  if not (is_org_staff(v_checkin.organization_id) or is_kcc_admin() or v_checkin.technician_profile_id = auth.uid()) then
    raise exception 'not authorized to check out this check-in';
  end if;

  update check_ins set checked_out_at = now(), closing_note = p_closing_note where id = p_check_in_id
  returning * into v_checkin;

  update appointments set actual_end = now(), status = 'completed' where id = v_checkin.appointment_id;

  perform log_domain_event(v_checkin.organization_id, 'TECHNICIAN_CHECKED_OUT', 'appointment', v_checkin.appointment_id,
    jsonb_build_object('work_order_id', v_checkin.work_order_id, 'check_in_id', v_checkin.id));

  return v_checkin;
end;
$$;
revoke execute on function technician_check_out(uuid, text) from public, anon;
grant execute on function technician_check_out(uuid, text) to authenticated;

create or replace function start_time_entry(
  p_work_order_id uuid,
  p_appointment_id uuid default null,
  p_entry_type text default 'work',
  p_client_generated_id uuid default null
)
returns time_entries
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_entry time_entries;
begin
  select organization_id into v_org_id from work_orders where id = p_work_order_id;
  if v_org_id is null then
    raise exception 'work order not found';
  end if;

  if not (is_org_staff(v_org_id) or is_kcc_admin() or is_assigned_to_work_order(p_work_order_id)) then
    raise exception 'not authorized to log time for this work order';
  end if;

  if p_client_generated_id is not null then
    select * into v_entry from time_entries where work_order_id = p_work_order_id and client_generated_id = p_client_generated_id;
    if v_entry.id is not null then
      return v_entry;
    end if;
  end if;

  insert into time_entries (organization_id, work_order_id, appointment_id, technician_profile_id, entry_type, client_generated_id)
  values (v_org_id, p_work_order_id, p_appointment_id, auth.uid(), p_entry_type, p_client_generated_id)
  returning * into v_entry;

  perform log_domain_event(v_org_id, 'TIME_ENTRY_STARTED', 'time_entry', v_entry.id,
    jsonb_build_object('work_order_id', p_work_order_id, 'entry_type', p_entry_type));

  if p_entry_type = 'work' then
    perform log_domain_event(v_org_id, 'TECHNICIAN_WORK_STARTED', 'work_order', p_work_order_id, '{}'::jsonb);
  end if;

  return v_entry;
end;
$$;
revoke execute on function start_time_entry(uuid, uuid, text, uuid) from public, anon;
grant execute on function start_time_entry(uuid, uuid, text, uuid) to authenticated;

create or replace function stop_time_entry(p_time_entry_id uuid)
returns time_entries
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entry time_entries;
begin
  select * into v_entry from time_entries where id = p_time_entry_id;
  if v_entry.id is null then
    raise exception 'time entry not found';
  end if;

  if not (is_org_staff(v_entry.organization_id) or is_kcc_admin() or v_entry.technician_profile_id = auth.uid()) then
    raise exception 'not authorized to stop this time entry';
  end if;

  update time_entries set end_time = now(), status = 'completed' where id = p_time_entry_id
  returning * into v_entry;

  perform log_domain_event(v_entry.organization_id, 'TIME_ENTRY_STOPPED', 'time_entry', v_entry.id,
    jsonb_build_object('work_order_id', v_entry.work_order_id, 'duration_seconds', extract(epoch from (v_entry.end_time - v_entry.start_time))));

  return v_entry;
end;
$$;
revoke execute on function stop_time_entry(uuid) from public, anon;
grant execute on function stop_time_entry(uuid) to authenticated;
