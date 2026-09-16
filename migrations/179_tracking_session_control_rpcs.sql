-- =========================================================
-- 179_tracking_session_control_rpcs.sql — Marine Cloud Phase 12
-- =========================================================
-- El browser NUNCA elige organization_id/technician_profile_id/
-- work_order_id/assignment_id — se derivan 100% server-side del
-- actor autenticado + la asignación activa real. Solo el técnico
-- asignado inicia su propio tracking; start repetido es idempotente.
-- Verificado con datos reales: técnico asignado puede, reinicio
-- idempotente, técnico no asignado/de otra org/customer/company admin
-- (impersonando) todos rechazados.
-- =========================================================

create or replace function start_technician_tracking(p_work_order_id uuid)
returns technician_tracking_sessions
language plpgsql
security definer
set search_path = public
as $$
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

  select * into v_assignment from assignments
  where work_order_id = p_work_order_id and technician_profile_id = auth.uid() and status = 'active';
  if v_assignment.id is null then
    raise exception 'only the technician assigned to this work order can start tracking';
  end if;

  if v_wo.current_status != 'en_route' then
    raise exception 'tracking can only be started while the work order is en_route (current status: %)', v_wo.current_status;
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
$$;

revoke execute on function start_technician_tracking(uuid) from public, anon;
grant execute on function start_technician_tracking(uuid) to authenticated;

create or replace function pause_technician_tracking(p_session_id uuid)
returns technician_tracking_sessions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session technician_tracking_sessions%rowtype;
begin
  select * into v_session from technician_tracking_sessions where id = p_session_id and technician_profile_id = auth.uid();
  if v_session.id is null then
    raise exception 'tracking session not found or not yours';
  end if;
  if v_session.status != 'active' then
    raise exception 'session is not active (current status: %)', v_session.status;
  end if;

  update technician_tracking_sessions set status = 'paused', updated_at = now() where id = p_session_id returning * into v_session;
  perform log_domain_event(v_session.organization_id, 'TECHNICIAN_TRACKING_PAUSED', 'work_order', v_session.work_order_id,
    jsonb_build_object('tracking_session_id', p_session_id));
  return v_session;
end;
$$;

revoke execute on function pause_technician_tracking(uuid) from public, anon;
grant execute on function pause_technician_tracking(uuid) to authenticated;

create or replace function resume_technician_tracking(p_session_id uuid)
returns technician_tracking_sessions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session technician_tracking_sessions%rowtype;
  v_wo_status text;
begin
  select * into v_session from technician_tracking_sessions where id = p_session_id and technician_profile_id = auth.uid();
  if v_session.id is null then
    raise exception 'tracking session not found or not yours';
  end if;
  if v_session.status != 'paused' then
    raise exception 'session is not paused (current status: %)', v_session.status;
  end if;

  select current_status into v_wo_status from work_orders where id = v_session.work_order_id;
  if v_wo_status != 'en_route' then
    raise exception 'cannot resume — work order is no longer en_route';
  end if;

  update technician_tracking_sessions set status = 'active', updated_at = now() where id = p_session_id returning * into v_session;
  perform log_domain_event(v_session.organization_id, 'TECHNICIAN_TRACKING_RESUMED', 'work_order', v_session.work_order_id,
    jsonb_build_object('tracking_session_id', p_session_id));
  return v_session;
end;
$$;

revoke execute on function resume_technician_tracking(uuid) from public, anon;
grant execute on function resume_technician_tracking(uuid) to authenticated;

create or replace function stop_technician_tracking(p_session_id uuid)
returns technician_tracking_sessions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session technician_tracking_sessions%rowtype;
begin
  select * into v_session from technician_tracking_sessions where id = p_session_id and technician_profile_id = auth.uid();
  if v_session.id is null then
    raise exception 'tracking session not found or not yours';
  end if;
  if v_session.status in ('stopped', 'expired') then
    return v_session;
  end if;

  update technician_tracking_sessions set status = 'stopped', stopped_at = now(), updated_at = now() where id = p_session_id returning * into v_session;
  perform log_domain_event(v_session.organization_id, 'TECHNICIAN_TRACKING_STOPPED', 'work_order', v_session.work_order_id,
    jsonb_build_object('tracking_session_id', p_session_id));
  return v_session;
end;
$$;

revoke execute on function stop_technician_tracking(uuid) from public, anon;
grant execute on function stop_technician_tracking(uuid) to authenticated;
