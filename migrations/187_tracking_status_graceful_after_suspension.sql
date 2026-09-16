-- =========================================================
-- 187_tracking_status_graceful_after_suspension.sql — Phase 12 final fix
-- =========================================================
-- BUG REAL encontrado probando la suspensión: get_work_order_
-- tracking_status() usaba is_customer_of_work_order() para su propio
-- chequeo — pero esa función (Phase 10) ya exige organización activa,
-- así que tras suspender, el customer dueño real del trabajo recibía
-- una EXCEPCIÓN en vez del 'unavailable' documentado. Ver el estado
-- de tracking es una lectura informacional, no una acción operativa.
-- Chequeo de propiedad directo (sin exigir org activa) solo para esta
-- lectura — staff/técnico/kcc_admin siguen igual. Defensa en
-- profundidad adicional: aunque exista una sesión 'active', si la
-- organización ya no está activa nunca se presenta como viva.
-- Verificado con datos reales: customer ve 'active' antes de
-- suspender, ve 'unavailable' (nunca excepción, nunca 'active')
-- después.
-- =========================================================

create or replace function get_work_order_tracking_status(p_work_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_wo work_orders%rowtype;
  v_session technician_tracking_sessions%rowtype;
  v_location technician_locations%rowtype;
  v_freshness text;
  v_seconds_ago numeric;
  v_is_owning_customer boolean;
begin
  select * into v_wo from work_orders where id = p_work_order_id;
  if v_wo.id is null then
    raise exception 'work order not found';
  end if;

  select exists (
    select 1 from customers c where c.id = v_wo.customer_id and c.profile_id = auth.uid()
  ) into v_is_owning_customer;

  if not (is_kcc_admin() or is_org_staff(v_wo.organization_id) or v_is_owning_customer or is_assigned_to_work_order(p_work_order_id)) then
    raise exception 'not authorized to view tracking for this work order';
  end if;

  select * into v_session from technician_tracking_sessions
  where work_order_id = p_work_order_id and status = 'active'
  order by started_at desc limit 1;

  if v_session.id is null then
    return jsonb_build_object('trackingStatus', 'unavailable');
  end if;

  if not exists (select 1 from organizations where id = v_wo.organization_id and status = 'active') then
    return jsonb_build_object('trackingStatus', 'unavailable');
  end if;

  select * into v_location from technician_locations
  where tracking_session_id = v_session.id
  order by recorded_at desc limit 1;

  if v_location.id is null then
    return jsonb_build_object('trackingStatus', 'active_no_location_yet');
  end if;

  v_seconds_ago := extract(epoch from (now() - v_location.recorded_at));
  v_freshness := case
    when v_seconds_ago <= 90 then 'live'
    when v_seconds_ago <= 300 then 'stale'
    else 'offline'
  end;

  return jsonb_build_object(
    'trackingStatus', 'active',
    'freshness', v_freshness,
    'latitude', v_location.latitude,
    'longitude', v_location.longitude,
    'accuracyMeters', v_location.accuracy_meters,
    'recordedAt', v_location.recorded_at,
    'secondsAgo', round(v_seconds_ago)
  );
end;
$$;
