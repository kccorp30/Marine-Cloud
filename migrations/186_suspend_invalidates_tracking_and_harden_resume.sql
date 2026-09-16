-- =========================================================
-- 186_suspend_invalidates_tracking_and_harden_resume.sql — Phase 12 final fix
-- =========================================================
-- BUG REAL: solo se bloqueaba INGESTIÓN futura cuando la organización
-- no estaba activa — una sesión existente podía quedar 'active' para
-- siempre. set_organization_status() ahora expira toda sesión
-- activa/pausada al pasar a 'suspended'/'inactive' — nunca 'paused',
-- así que una reactivación de KCC NUNCA revive la sesión sola.
--
-- resume_technician_tracking() ya no confía solo en la propiedad
-- histórica — revalida organización activa, asignación activa, y
-- work order en_route, igual que start_technician_tracking().
--
-- Verificado con datos reales: sesión activa y pausada ambas expiran
-- al suspender, resume rechazado tras suspensión, resume rechazado
-- con asignación inactiva, técnico debe iniciar sesión nueva
-- intencionalmente tras reactivación (la vieja nunca revive sola).
-- =========================================================

create or replace function set_organization_status(p_organization_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org organizations%rowtype;
  v_event_type text;
begin
  if not is_kcc_admin() then
    raise exception 'only KCC platform staff can change organization status';
  end if;
  if p_status not in ('active', 'inactive', 'suspended') then
    raise exception 'invalid status: %', p_status;
  end if;

  select * into v_org from organizations where id = p_organization_id for update;
  if v_org.id is null then
    raise exception 'organization not found';
  end if;
  if v_org.status = p_status then
    raise exception 'organization is already %', p_status;
  end if;

  v_event_type := case
    when p_status = 'suspended' then 'ORGANIZATION_SUSPENDED'
    when p_status = 'active' and v_org.status = 'suspended' then 'ORGANIZATION_REACTIVATED'
    when p_status = 'active' then 'ORGANIZATION_ACTIVATED'
    else 'ORGANIZATION_STATUS_CHANGED'
  end;

  update organizations set status = p_status, updated_at = now() where id = p_organization_id;

  if p_status in ('suspended', 'inactive') then
    update technician_tracking_sessions
    set status = 'expired', stopped_at = now(), updated_at = now()
    where organization_id = p_organization_id and status in ('active', 'paused');
  end if;

  perform log_domain_event(p_organization_id, v_event_type, 'organization', p_organization_id,
    jsonb_build_object('from_status', v_org.status, 'to_status', p_status));
  perform log_audit_event(p_organization_id, 'organization', p_organization_id, 'organization_status_changed',
    jsonb_build_object('status', v_org.status), jsonb_build_object('status', p_status));
end;
$$;

create or replace function resume_technician_tracking(p_session_id uuid)
returns technician_tracking_sessions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session technician_tracking_sessions%rowtype;
  v_wo_status text;
  v_assignment_active boolean;
begin
  select * into v_session from technician_tracking_sessions where id = p_session_id and technician_profile_id = auth.uid();
  if v_session.id is null then
    raise exception 'tracking session not found or not yours';
  end if;
  if v_session.status != 'paused' then
    raise exception 'session is not paused (current status: %)', v_session.status;
  end if;

  if not exists (select 1 from organizations where id = v_session.organization_id and status = 'active') then
    raise exception 'organization is not active';
  end if;

  select exists (
    select 1 from assignments
    where id = v_session.assignment_id and technician_profile_id = auth.uid() and status = 'active'
  ) into v_assignment_active;
  if not v_assignment_active then
    raise exception 'assignment is no longer active';
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
