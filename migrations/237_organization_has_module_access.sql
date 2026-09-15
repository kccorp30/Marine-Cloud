-- =========================================================
-- 237_organization_has_module_access.sql — Phase 14 final integrity
-- =========================================================
-- Helper central de entitlements. Sin fila explícita -> disponible
-- por default. start_technician_tracking() (Phase 12) ahora exige el
-- módulo 'tracking' habilitado, como ejemplo real de enforcement
-- server-side, no solo ocultamiento de UI.
-- Verificado con datos reales: módulo explícitamente deshabilitado
-- bloqueado, módulo sin fila explícita habilitado por default.
-- =========================================================

create or replace function organization_has_module_access(p_organization_id uuid, p_module_key text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_plan_id uuid;
  v_entitlement boolean;
begin
  if is_kcc_admin() then
    return true;
  end if;
  if not organization_has_active_access(p_organization_id) then
    return false;
  end if;
  select plan_id into v_plan_id from organization_subscriptions where organization_id = p_organization_id and superseded_at is null;
  if v_plan_id is null then
    return false;
  end if;
  select enabled into v_entitlement from plan_module_entitlements where plan_id = v_plan_id and module_key = p_module_key;
  return coalesce(v_entitlement, true);
end;
$$;

revoke execute on function organization_has_module_access(uuid, text) from public, anon;
grant execute on function organization_has_module_access(uuid, text) to authenticated;

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
  if not organization_has_module_access(v_wo.organization_id, 'tracking') then
    raise exception 'this organization''s plan does not include live technician tracking';
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
