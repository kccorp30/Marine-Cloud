-- =========================================================
-- 20260916090200_fix_missing_checked_in_event.sql — Technician Mission
-- =========================================================
-- BUG REAL en mi propia migración anterior (20260916090100): al
-- agregar la llamada a transition_work_order() dentro de
-- technician_check_in(), quité por error el
-- log_domain_event('TECHNICIAN_CHECKED_IN', ...) explícito que la
-- función original sí tenía — transition_work_order() ya registra su
-- propio 'WORK_ORDER_STATUS_CHANGED', pero es un evento DISTINTO,
-- no reemplaza el evento específico de misión que notification_rules
-- espera. Detectado verificando con datos reales que la fila de
-- notificación nunca se creaba pese a que el check-in sí funcionaba.
-- =========================================================

create or replace function technician_check_in(p_appointment_id uuid, p_latitude double precision default null, p_longitude double precision default null, p_device_metadata jsonb default null)
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

  perform transition_work_order(v_appt.work_order_id, 'checked_in', 'Technician checked in on site');

  -- Evento específico de misión — distinto de WORK_ORDER_STATUS_CHANGED
  -- que transition_work_order() ya registra; notification_rules
  -- escucha este evento específico, no el genérico.
  perform log_domain_event(v_appt.organization_id, 'TECHNICIAN_CHECKED_IN', 'appointment', p_appointment_id,
    jsonb_build_object('work_order_id', v_appt.work_order_id, 'check_in_id', v_checkin.id));

  return v_checkin;
end;
$$;
