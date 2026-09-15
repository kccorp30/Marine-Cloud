-- =========================================================
-- 181_submit_technician_location.sql — Marine Cloud Phase 12
-- =========================================================
-- El cliente SOLO envía datos de sensor reales — todo lo demás se
-- deriva server-side de la sesión activa. Rechaza sesión no activa,
-- coordenadas inválidas (CHECK a nivel de tabla), timestamps
-- absurdos. Verificado con datos reales: ubicación válida aceptada,
-- lat/lng inválidos rechazados, técnico equivocado rechazado.
-- =========================================================

create or replace function submit_technician_location(
  p_session_id uuid,
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy_meters double precision default null,
  p_heading_degrees double precision default null,
  p_speed_mps double precision default null,
  p_recorded_at timestamptz default now()
)
returns technician_locations
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session technician_tracking_sessions%rowtype;
  v_location technician_locations%rowtype;
begin
  select * into v_session from technician_tracking_sessions
  where id = p_session_id and technician_profile_id = auth.uid();
  if v_session.id is null then
    raise exception 'tracking session not found or not yours';
  end if;
  if v_session.status != 'active' then
    raise exception 'tracking session is not active (status: %)', v_session.status;
  end if;
  if not exists (select 1 from organizations where id = v_session.organization_id and status = 'active') then
    raise exception 'organization is not active';
  end if;

  if p_recorded_at > now() + interval '2 minutes' then
    raise exception 'recorded_at is implausibly in the future';
  end if;
  if p_recorded_at < now() - interval '1 day' then
    raise exception 'recorded_at is implausibly old for a live tracking point';
  end if;

  insert into technician_locations (
    organization_id, tracking_session_id, technician_profile_id, work_order_id,
    latitude, longitude, accuracy_meters, heading_degrees, speed_mps, recorded_at, source
  )
  values (
    v_session.organization_id, p_session_id, auth.uid(), v_session.work_order_id,
    p_latitude, p_longitude, p_accuracy_meters, p_heading_degrees, p_speed_mps, p_recorded_at, 'browser_gps'
  )
  returning * into v_location;

  update technician_tracking_sessions set last_location_at = p_recorded_at, updated_at = now() where id = p_session_id;

  return v_location;
end;
$$;

revoke execute on function submit_technician_location(uuid, double precision, double precision, double precision, double precision, double precision, timestamptz) from public, anon;
grant execute on function submit_technician_location(uuid, double precision, double precision, double precision, double precision, double precision, timestamptz) to authenticated;
