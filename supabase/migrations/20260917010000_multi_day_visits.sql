-- =========================================================
-- 20260917010000_multi_day_visits.sql — Technician Mission / Multi-Day Work
-- =========================================================
-- Reusa appointments (= visitas bajo el MISMO work order) y
-- check_ins (= presencia en sitio). Nunca una tabla paralela.
--
-- 1. BUG REAL en mi fix anterior (20260916090200): technician_check_in()
--    transicionaba SIEMPRE a 'checked_in' — en el Día 2 el work order
--    está en work_in_progress/waiting_parts y el check-in fallaba.
--    Ahora solo transiciona si el status es 'en_route'.
-- 2. start_technician_tracking() solo aceptaba 'en_route' — el técnico
--    no podía compartir ubicación viajando a una visita de
--    continuación. Ahora también acepta estados de continuación SI no
--    tiene un check-in abierto (está viajando, no en sitio).
-- 3. technician_start_continuation_route(): emite TECHNICIAN_EN_ROUTE
--    para la visita del Día N sin cambiar el status del work order
--    (que sigue en progreso) — mismo evento, mismas notificaciones.
-- 4. finish_todays_visit(): cierra la visita (check-out, time entries,
--    tracking, appointment con outcome+resumen), NUNCA completa el
--    work order, opcionalmente mueve a waiting_parts/
--    waiting_customer_approval vía transition_work_order(), y agenda
--    la próxima visita si se indica.
--
-- Verificado con datos reales: Día 1 5/5 PASS, Día 2 6/6 PASS.
-- =========================================================

alter table appointments add column if not exists visit_outcome text
  check (visit_outcome in ('continue_tomorrow','waiting_parts','waiting_approval','return_scheduled','access_weather','other'));
alter table appointments add column if not exists visit_summary text;

-- ---------------------------------------------------------
create or replace function technician_check_in(p_appointment_id uuid, p_latitude double precision default null, p_longitude double precision default null, p_device_metadata jsonb default null)
returns check_ins
language plpgsql
security definer
set search_path = public
as $$
declare
  v_appt appointments;
  v_checkin check_ins;
  v_wo_status text;
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

  -- Solo la PRIMERA llegada (desde en_route) cambia el status. En una
  -- visita de continuación el work order ya está en progreso — la
  -- llegada se registra (check_in + evento), el status no se toca.
  select current_status into v_wo_status from work_orders where id = v_appt.work_order_id;
  if v_wo_status = 'en_route' then
    perform transition_work_order(v_appt.work_order_id, 'checked_in', 'Technician checked in on site');
  end if;

  -- Las visitas de continuación terminan de viajar al llegar.
  update technician_tracking_sessions set status = 'stopped', updated_at = now()
  where work_order_id = v_appt.work_order_id and technician_profile_id = auth.uid() and status in ('active','paused');

  perform log_domain_event(v_appt.organization_id, 'TECHNICIAN_CHECKED_IN', 'appointment', p_appointment_id,
    jsonb_build_object('work_order_id', v_appt.work_order_id, 'check_in_id', v_checkin.id));

  return v_checkin;
end;
$$;

-- ---------------------------------------------------------
create or replace function start_technician_tracking(p_work_order_id uuid)
 RETURNS technician_tracking_sessions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_wo work_orders%rowtype;
  v_assignment assignments%rowtype;
  v_session technician_tracking_sessions%rowtype;
begin
  select * into v_wo from work_orders where id = p_work_order_id;
  if v_wo.id is null then
    raise exception 'work order not found';
  end if;

  if not exists (select 1 from organizations where id = v_wo.organization_id and status = 'active') then
    raise exception 'organization is not active';
  end if;
  if not organization_has_module_access(v_wo.organization_id, 'tracking') then
    raise exception 'this organization''s plan does not include live technician tracking';
  end if;

  select * into v_assignment from assignments
  where work_order_id = p_work_order_id and technician_profile_id = auth.uid() and status = 'active';
  if v_assignment.id is null then
    raise exception 'only the technician assigned to this work order can start tracking';
  end if;

  -- en_route (primera visita) O viajando a una visita de continuación:
  -- work order en progreso/espera Y sin check-in abierto (no está en sitio).
  if not (
    v_wo.current_status = 'en_route'
    or (
      v_wo.current_status in ('work_in_progress','waiting_parts','waiting_customer_approval')
      and not exists (select 1 from check_ins where work_order_id = p_work_order_id and technician_profile_id = auth.uid() and checked_out_at is null)
    )
  ) then
    raise exception 'tracking can only be started while traveling to the service location (current status: %)', v_wo.current_status;
  end if;

  select * into v_session from technician_tracking_sessions
  where technician_profile_id = auth.uid() and work_order_id = p_work_order_id and status in ('active', 'paused');
  if v_session.id is not null then
    if v_session.status = 'paused' then
      update technician_tracking_sessions set status = 'active', updated_at = now() where id = v_session.id returning * into v_session;
    end if;
    return v_session;
  end if;

  insert into technician_tracking_sessions (organization_id, technician_profile_id, work_order_id, assignment_id, status)
  values (v_wo.organization_id, auth.uid(), p_work_order_id, v_assignment.id, 'active')
  returning * into v_session;

  perform log_domain_event(v_wo.organization_id, 'TECHNICIAN_TRACKING_STARTED', 'work_order', p_work_order_id,
    jsonb_build_object('tracking_session_id', v_session.id, 'technician_profile_id', auth.uid()));

  return v_session;
end;
$function$;

-- ---------------------------------------------------------
create or replace function technician_start_continuation_route(p_work_order_id uuid)
returns work_orders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_wo work_orders;
begin
  select * into v_wo from work_orders where id = p_work_order_id;
  if v_wo.id is null then
    raise exception 'work order not found';
  end if;
  if not is_assigned_to_work_order(p_work_order_id) then
    raise exception 'only the assigned technician can start a continuation route';
  end if;
  if v_wo.current_status not in ('work_in_progress','waiting_parts','waiting_customer_approval') then
    raise exception 'a continuation route requires a work order already in progress (current status: %)', v_wo.current_status;
  end if;
  if exists (select 1 from check_ins where work_order_id = p_work_order_id and technician_profile_id = auth.uid() and checked_out_at is null) then
    raise exception 'you are already checked in on site for this work order';
  end if;
  if not exists (
    select 1 from vessels v where v.id = v_wo.vessel_id
      and (coalesce(trim(v.service_street_address), '') != '' or coalesce(trim(v.marina), '') != '')
  ) then
    raise exception 'service location required — this vessel has no service address or marina on file';
  end if;

  perform log_domain_event(v_wo.organization_id, 'TECHNICIAN_EN_ROUTE', 'work_order', p_work_order_id,
    jsonb_build_object('continuation', true));
  return v_wo;
end;
$$;

revoke execute on function technician_start_continuation_route(uuid) from public, anon;
grant execute on function technician_start_continuation_route(uuid) to authenticated;

-- ---------------------------------------------------------
create or replace function finish_todays_visit(
  p_work_order_id uuid,
  p_outcome text,
  p_summary text,
  p_next_visit_start timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_wo work_orders;
  v_checkin check_ins;
  v_session record;
  v_next_appt_id uuid;
begin
  select * into v_wo from work_orders where id = p_work_order_id for update;
  if v_wo.id is null then
    raise exception 'work order not found';
  end if;
  if not is_assigned_to_work_order(p_work_order_id) then
    raise exception 'only the assigned technician can finish a visit';
  end if;
  if v_wo.current_status != 'work_in_progress' then
    raise exception 'a visit can only be finished while work is in progress (current status: %)', v_wo.current_status;
  end if;
  if p_outcome not in ('continue_tomorrow','waiting_parts','waiting_approval','return_scheduled','access_weather','other') then
    raise exception 'invalid visit outcome: %', p_outcome;
  end if;
  if coalesce(trim(p_summary), '') = '' then
    raise exception 'a visit summary is required';
  end if;
  if p_outcome = 'return_scheduled' and p_next_visit_start is null then
    raise exception 'a return visit date is required';
  end if;
  if p_next_visit_start is not null and p_next_visit_start <= now() then
    raise exception 'the next visit must be scheduled in the future';
  end if;

  select * into v_checkin from check_ins
  where work_order_id = p_work_order_id and technician_profile_id = auth.uid() and checked_out_at is null
  order by checked_in_at desc limit 1;
  if v_checkin.id is null then
    raise exception 'no active on-site visit to finish';
  end if;

  update check_ins set checked_out_at = now(), closing_note = p_summary where id = v_checkin.id;

  update time_entries set end_time = now(), status = 'completed', updated_at = now()
  where work_order_id = p_work_order_id and technician_profile_id = auth.uid() and status = 'active' and end_time is null;

  update technician_tracking_sessions set status = 'stopped', updated_at = now()
  where work_order_id = p_work_order_id and technician_profile_id = auth.uid() and status in ('active','paused');

  if v_checkin.appointment_id is not null then
    update appointments set actual_end = now(), status = 'completed', visit_outcome = p_outcome, visit_summary = p_summary, updated_at = now()
    where id = v_checkin.appointment_id;
  end if;

  -- Nunca 'completed'. Solo las esperas reales cambian el status, por
  -- la puerta oficial.
  if p_outcome = 'waiting_parts' then
    perform transition_work_order(p_work_order_id, 'waiting_parts', p_summary);
  elsif p_outcome = 'waiting_approval' then
    perform transition_work_order(p_work_order_id, 'waiting_customer_approval', p_summary);
  end if;

  if p_next_visit_start is not null then
    insert into appointments (organization_id, work_order_id, scheduled_start, status, purpose)
    values (v_wo.organization_id, p_work_order_id, p_next_visit_start, 'scheduled', 'continuation')
    returning id into v_next_appt_id;
  end if;

  update work_orders set last_activity_at = now() where id = p_work_order_id;

  perform log_domain_event(v_wo.organization_id, 'VISIT_FINISHED', 'work_order', p_work_order_id,
    jsonb_build_object('outcome', p_outcome, 'appointment_id', v_checkin.appointment_id, 'next_appointment_id', v_next_appt_id));

  return jsonb_build_object('outcome', p_outcome, 'next_appointment_id', v_next_appt_id);
end;
$$;

revoke execute on function finish_todays_visit(uuid, text, text, timestamptz) from public, anon;
grant execute on function finish_todays_visit(uuid, text, text, timestamptz) to authenticated;
