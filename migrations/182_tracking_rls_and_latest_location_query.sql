-- =========================================================
-- 182_tracking_rls_and_latest_location_query.sql — Marine Cloud Phase 12
-- =========================================================
-- Umbrales de frescura (documentados una sola vez, no repetidos en
-- cada componente de UI): LIVE <= 90s, STALE <= 5min, OFFLINE más
-- viejo. get_work_order_tracking_status() es la ÚNICA vía segura de
-- lectura para customer/company — nunca escanean technician_locations
-- directo. Devuelve solo campos mínimos seguros.
-- Verificado con datos reales: customer dueño ve LIVE recién enviado,
-- customer no relacionado rechazado, ubicación vieja simulada se
-- marca OFFLINE (nunca se presenta como viva).
-- =========================================================

alter table technician_tracking_sessions enable row level security;
alter table technician_locations enable row level security;

create policy "technician_reads_own_tracking_sessions" on technician_tracking_sessions for select
using (
  is_kcc_admin()
  or is_org_staff(organization_id)
  or (technician_profile_id = auth.uid() and is_org_active(organization_id))
  or is_customer_of_work_order(work_order_id)
);

create policy "technician_reads_own_locations" on technician_locations for select
using (
  is_kcc_admin()
  or is_org_staff(organization_id)
  or (technician_profile_id = auth.uid() and is_org_active(organization_id))
  or is_customer_of_work_order(work_order_id)
);

revoke all on technician_tracking_sessions from anon;
revoke all on technician_locations from anon;
grant select on technician_tracking_sessions to authenticated;
grant select on technician_locations to authenticated;

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
begin
  select * into v_wo from work_orders where id = p_work_order_id;
  if v_wo.id is null then
    raise exception 'work order not found';
  end if;

  if not (is_kcc_admin() or is_org_staff(v_wo.organization_id) or is_customer_of_work_order(p_work_order_id) or is_assigned_to_work_order(p_work_order_id)) then
    raise exception 'not authorized to view tracking for this work order';
  end if;

  select * into v_session from technician_tracking_sessions
  where work_order_id = p_work_order_id and status = 'active'
  order by started_at desc limit 1;

  if v_session.id is null then
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

revoke execute on function get_work_order_tracking_status(uuid) from public, anon;
grant execute on function get_work_order_tracking_status(uuid) to authenticated;
