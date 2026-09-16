-- =========================================================
-- 035_checkin_idempotency_guard.sql — Marine Cloud Phase 2
-- =========================================================
-- Ver definición completa en 032 — esta migración reemplaza
-- technician_check_in() agregando el guard de idempotencia
-- (clave natural: appointment_id + technician_profile_id + sin
-- checkout activo). Documentada por separado porque se aplicó
-- como una corrección incremental durante el desarrollo, no como
-- parte del diseño original de la función.

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
