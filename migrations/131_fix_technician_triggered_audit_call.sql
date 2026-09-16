-- =========================================================
-- 131_fix_technician_triggered_audit_call.sql — Marine Cloud Phase 9
-- =========================================================
-- BUG REAL encontrado probando request_kcc_assistance(): llama a
-- log_audit_event(), que exige is_org_staff() — pero quien llama es
-- el TÉCNICO, no staff. Mismo patrón de bug ya resuelto antes en este
-- proyecto (Phase 6/7) para acciones disparadas por technician/
-- customer — log_audit_event_internal() existe exactamente para esto.
-- Verificado: el flujo completo funciona tras este fix.
-- =========================================================

create or replace function request_kcc_assistance(
  p_work_order_id uuid,
  p_category text,
  p_urgency text,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_wo work_orders%rowtype;
  v_request_id uuid;
begin
  select * into v_wo from work_orders where id = p_work_order_id;
  if v_wo.id is null then
    raise exception 'work order not found';
  end if;
  if not is_assigned_to_work_order(p_work_order_id) then
    raise exception 'only the technician assigned to this work order can request KCC assistance for it';
  end if;

  insert into kcc_assistance_requests (
    organization_id, requesting_technician_id, work_order_id, vessel_id,
    current_job_status, category, urgency, notes
  )
  values (
    v_wo.organization_id, auth.uid(), p_work_order_id, v_wo.vessel_id,
    v_wo.current_status, p_category, p_urgency, p_notes
  )
  returning id into v_request_id;

  perform log_domain_event(v_wo.organization_id, 'KCC_ASSISTANCE_REQUESTED', 'kcc_assistance_request', v_request_id,
    jsonb_build_object('work_order_id', p_work_order_id, 'category', p_category, 'urgency', p_urgency));
  perform log_audit_event_internal(v_wo.organization_id, 'kcc_assistance_request', v_request_id, 'kcc_assistance_requested',
    null, jsonb_build_object('category', p_category, 'urgency', p_urgency));

  return v_request_id;
end;
$$;
