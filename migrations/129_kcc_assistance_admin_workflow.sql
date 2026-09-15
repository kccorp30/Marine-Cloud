-- =========================================================
-- 129_kcc_assistance_admin_workflow.sql — Marine Cloud Phase 9
-- =========================================================
-- Solo kcc_admin en las 4 acciones. Transiciones ilegales rechazadas.
-- Verificado con datos reales: staff normal no puede aceptar como
-- KCC, open->started directo rechazado, kcc_admin sí puede aceptar/
-- iniciar/resolver/escalar, resolved->accept de nuevo rechazado,
-- flujo de escalación funciona.
-- =========================================================

create or replace function accept_kcc_assistance(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_req kcc_assistance_requests%rowtype;
begin
  if not is_kcc_admin() then
    raise exception 'only KCC platform staff can accept an assistance request';
  end if;

  select * into v_req from kcc_assistance_requests where id = p_request_id for update;
  if v_req.id is null then
    raise exception 'request not found';
  end if;
  if v_req.status != 'open' then
    raise exception 'only an open request can be accepted (current status: %)', v_req.status;
  end if;

  update kcc_assistance_requests set status = 'accepted', accepted_by = auth.uid(), accepted_at = now(), updated_at = now()
  where id = p_request_id;

  perform log_domain_event(v_req.organization_id, 'KCC_ASSISTANCE_ACCEPTED', 'kcc_assistance_request', p_request_id,
    jsonb_build_object('work_order_id', v_req.work_order_id, 'accepted_by', auth.uid()));
  perform log_audit_event(v_req.organization_id, 'kcc_assistance_request', p_request_id, 'kcc_assistance_accepted',
    jsonb_build_object('status', 'open'), jsonb_build_object('status', 'accepted'));
end;
$$;

revoke execute on function accept_kcc_assistance(uuid) from public, anon;
grant execute on function accept_kcc_assistance(uuid) to authenticated;

create or replace function start_kcc_assistance(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_req kcc_assistance_requests%rowtype;
begin
  if not is_kcc_admin() then
    raise exception 'only KCC platform staff can start an assistance request';
  end if;

  select * into v_req from kcc_assistance_requests where id = p_request_id for update;
  if v_req.id is null then
    raise exception 'request not found';
  end if;
  if v_req.status != 'accepted' then
    raise exception 'only an accepted request can be started (current status: %)', v_req.status;
  end if;

  update kcc_assistance_requests set status = 'started', started_at = now(), updated_at = now()
  where id = p_request_id;

  perform log_domain_event(v_req.organization_id, 'KCC_ASSISTANCE_STARTED', 'kcc_assistance_request', p_request_id,
    jsonb_build_object('work_order_id', v_req.work_order_id));
  perform log_audit_event(v_req.organization_id, 'kcc_assistance_request', p_request_id, 'kcc_assistance_started',
    jsonb_build_object('status', 'accepted'), jsonb_build_object('status', 'started'));
end;
$$;

revoke execute on function start_kcc_assistance(uuid) from public, anon;
grant execute on function start_kcc_assistance(uuid) to authenticated;

create or replace function resolve_kcc_assistance(p_request_id uuid, p_resolution_notes text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_req kcc_assistance_requests%rowtype;
begin
  if not is_kcc_admin() then
    raise exception 'only KCC platform staff can resolve an assistance request';
  end if;

  select * into v_req from kcc_assistance_requests where id = p_request_id for update;
  if v_req.id is null then
    raise exception 'request not found';
  end if;
  if v_req.status not in ('accepted', 'started') then
    raise exception 'only an accepted or started request can be resolved (current status: %)', v_req.status;
  end if;

  update kcc_assistance_requests set status = 'resolved', resolved_at = now(), resolution_notes = p_resolution_notes, updated_at = now()
  where id = p_request_id;

  perform log_domain_event(v_req.organization_id, 'KCC_ASSISTANCE_RESOLVED', 'kcc_assistance_request', p_request_id,
    jsonb_build_object('work_order_id', v_req.work_order_id));
  perform log_audit_event(v_req.organization_id, 'kcc_assistance_request', p_request_id, 'kcc_assistance_resolved',
    jsonb_build_object('status', v_req.status), jsonb_build_object('status', 'resolved'));
end;
$$;

revoke execute on function resolve_kcc_assistance(uuid, text) from public, anon;
grant execute on function resolve_kcc_assistance(uuid, text) to authenticated;

create or replace function escalate_kcc_assistance(p_request_id uuid, p_resolution_notes text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_req kcc_assistance_requests%rowtype;
begin
  if not is_kcc_admin() then
    raise exception 'only KCC platform staff can escalate an assistance request';
  end if;

  select * into v_req from kcc_assistance_requests where id = p_request_id for update;
  if v_req.id is null then
    raise exception 'request not found';
  end if;
  if v_req.status not in ('open', 'accepted', 'started') then
    raise exception 'a resolved or already-escalated request cannot be escalated again (current status: %)', v_req.status;
  end if;

  update kcc_assistance_requests set status = 'escalated', escalated_at = now(), resolution_notes = p_resolution_notes, updated_at = now()
  where id = p_request_id;

  perform log_domain_event(v_req.organization_id, 'KCC_ASSISTANCE_ESCALATED', 'kcc_assistance_request', p_request_id,
    jsonb_build_object('work_order_id', v_req.work_order_id));
  perform log_audit_event(v_req.organization_id, 'kcc_assistance_request', p_request_id, 'kcc_assistance_escalated',
    jsonb_build_object('status', v_req.status), jsonb_build_object('status', 'escalated'));
end;
$$;

revoke execute on function escalate_kcc_assistance(uuid, text) from public, anon;
grant execute on function escalate_kcc_assistance(uuid, text) to authenticated;
