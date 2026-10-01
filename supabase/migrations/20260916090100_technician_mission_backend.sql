-- =========================================================
-- 20260916090100_technician_mission_backend.sql — Technician Mission
-- =========================================================
-- 1. Dirección de servicio REAL en vessels — nunca existió antes.
--    marina queda como label libre; los campos nuevos son la
--    dirección real usable para geocoding/mapas/navegación externa.
-- 2. technician_check_in() corregido — BUG REAL: antes solo tocaba
--    check_ins/appointments, work_orders.current_status quedaba
--    congelado en 'en_route'. Ahora transiciona a 'checked_in' vía
--    transition_work_order() (única puerta de estado real).
-- 3. Gate real server-side de fotos BEFORE (mínimo 3) para
--    diagnosis->work_in_progress, mismo patrón que el gate de QC
--    ya existente en la función — nunca solo deshabilitado en el
--    frontend, nunca una copia paralela de la máquina de estados.
-- 4. Reglas de notificación para los eventos de misión — no existía
--    ninguna antes de esto.
--
-- Verificado con datos reales: check-in transiciona correctamente,
-- gate bloquea sin evidencia BEFORE, permite con 3 fotos reales.
-- =========================================================

alter table vessels add column if not exists service_street_address text;
alter table vessels add column if not exists service_city text;
alter table vessels add column if not exists service_state text;
alter table vessels add column if not exists service_postal_code text;
alter table vessels add column if not exists service_latitude double precision;
alter table vessels add column if not exists service_longitude double precision;

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

  return v_checkin;
end;
$$;

-- ---------------------------------------------------------
create or replace function transition_work_order(p_work_order_id uuid, p_to_status text, p_reason text DEFAULT NULL::text)
 RETURNS work_orders
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_wo work_orders;
  v_org_id uuid;
  v_from_status text;
  v_actor_role text;
  v_rule_exists boolean;
  v_has_passed_qc boolean;
  v_before_photo_count int;
begin
  select * into v_wo from work_orders where id = p_work_order_id for update;
  if v_wo.id is null then
    raise exception 'work order not found';
  end if;

  v_org_id := v_wo.organization_id;
  v_from_status := v_wo.current_status;

  if is_kcc_admin() then
    v_actor_role := 'kcc_admin';
  else
    select role into v_actor_role from organization_memberships
    where profile_id = auth.uid() and organization_id = v_org_id and status = 'active'
    limit 1;

    if v_actor_role is null then
      raise exception 'not authorized for this organization';
    end if;

    if v_actor_role = 'technician' and not is_assigned_to_work_order(p_work_order_id) then
      raise exception 'technician is not assigned to this work order';
    end if;

    if v_actor_role = 'customer' and not is_customer_of_work_order(p_work_order_id) then
      raise exception 'customer does not own this work order';
    end if;
  end if;

  select exists (
    select 1 from work_order_transition_rules
    where from_status = v_from_status
      and to_status = p_to_status
      and active = true
      and v_actor_role = any(allowed_roles)
  ) into v_rule_exists;

  if not v_rule_exists then
    raise exception 'transition from % to % not allowed for role %', v_from_status, p_to_status, coalesce(v_actor_role,'none');
  end if;

  -- GATE DE QC — sin cambios, se preserva tal cual.
  if v_from_status = 'quality_control' and p_to_status = 'invoice' and v_wo.qc_required then
    select exists (
      select 1 from qc_submissions where work_order_id = p_work_order_id and status = 'passed'
    ) into v_has_passed_qc;
    if not v_has_passed_qc then
      raise exception 'this work order requires a passed QC submission before it can be invoiced';
    end if;
  end if;

  -- GATE NUEVO REAL DE EVIDENCIA BEFORE — mismo patrón exacto que el
  -- gate de QC de arriba.
  if v_from_status = 'diagnosis' and p_to_status = 'work_in_progress' then
    select count(*) into v_before_photo_count from media_assets where work_order_id = p_work_order_id and category = 'before';
    if v_before_photo_count < 3 then
      raise exception 'before-work documentation required: % of 3 minimum photos uploaded', v_before_photo_count;
    end if;
  end if;

  update work_orders
  set current_status = p_to_status,
      closed_at = case when p_to_status in ('completed','cancelled') then now() else closed_at end
  where id = p_work_order_id
  returning * into v_wo;

  insert into work_order_status_history (work_order_id, organization_id, from_status, to_status, actor_profile_id, reason)
  values (p_work_order_id, v_org_id, v_from_status, p_to_status, auth.uid(), p_reason);

  perform log_domain_event(
    v_org_id, 'WORK_ORDER_STATUS_CHANGED', 'work_order', p_work_order_id,
    jsonb_build_object('from_status', v_from_status, 'to_status', p_to_status, 'reason', p_reason)
  );

  perform log_audit_event_internal(
    v_org_id, 'work_orders', p_work_order_id, 'STATUS_TRANSITION',
    jsonb_build_object('status', v_from_status), jsonb_build_object('status', p_to_status)
  );

  return v_wo;
end;
$function$;

-- ---------------------------------------------------------
insert into notification_rules (organization_id, event_type, payload_filter, severity, recipient_strategy, title_template, body_template, acknowledgement_required) values
  (null, 'TECHNICIAN_EN_ROUTE', null, 'info', 'billing_admin', 'Technician en route', 'Your assigned technician is on the way.', false),
  (null, 'TECHNICIAN_CHECKED_IN', null, 'info', 'billing_admin', 'Technician arrived', 'Your technician has arrived at the service location.', false)
on conflict do nothing;
