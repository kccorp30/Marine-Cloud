-- =========================================================
-- 077_fix_customer_triggered_audit_calls.sql — Phase 6 hardening
-- =========================================================
-- BUG REAL: approve_estimate()/decline_estimate() llaman a
-- log_audit_event(), que exige is_org_staff() del que llama — pero
-- quien llama es el CUSTOMER aprobando/rechazando, no staff. Mismo
-- patrón de bug ya resuelto antes en este proyecto para
-- technician/customer (log_audit_event_internal() existe
-- exactamente para esto). Se usa la versión interna acá también.
-- Verificado: aprobación y rechazo por el customer ahora sí escriben
-- su registro de auditoría, sin la excepción "not authorized to log
-- audit events".
-- =========================================================

create or replace function approve_estimate(p_estimate_version_id uuid, p_customer_note text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_version estimate_versions%rowtype;
  v_estimate estimates%rowtype;
  v_event_type text;
begin
  select * into v_version from estimate_versions where id = p_estimate_version_id for update;
  if v_version.id is null then
    raise exception 'estimate version not found';
  end if;

  select * into v_estimate from estimates where id = v_version.estimate_id for update;

  if not is_own_customer_record(v_estimate.customer_id) then
    raise exception 'not authorized to approve this estimate';
  end if;

  if v_estimate.current_version_id != p_estimate_version_id then
    raise exception 'this is not the current actionable version';
  end if;
  if v_version.status not in ('sent', 'viewed') then
    raise exception 'this version cannot be approved (status: %)', v_version.status;
  end if;
  if v_version.valid_until is not null and v_version.valid_until < current_date then
    raise exception 'this estimate has expired';
  end if;

  insert into estimate_decisions (organization_id, estimate_id, estimate_version_id, customer_id, decision, version_total_at_decision, customer_note)
  values (v_estimate.organization_id, v_estimate.id, p_estimate_version_id, v_estimate.customer_id, 'approved', v_version.total, p_customer_note);

  update estimate_versions set status = 'approved' where id = p_estimate_version_id;
  update estimates set status = 'approved', updated_at = now() where id = v_estimate.id;

  if v_estimate.type = 'estimate' and v_estimate.work_order_id is not null then
    if (select current_status from work_orders where id = v_estimate.work_order_id) = 'awaiting_approval' then
      perform transition_work_order(v_estimate.work_order_id, 'scheduled');
    end if;
  end if;

  v_event_type := case when v_estimate.type = 'change_order' then 'CHANGE_ORDER_APPROVED' else 'ESTIMATE_APPROVED' end;
  perform log_domain_event(v_estimate.organization_id, v_event_type, 'estimate', v_estimate.id,
    jsonb_build_object('estimate_version_id', p_estimate_version_id, 'total', v_version.total));
  perform log_audit_event_internal(v_estimate.organization_id, 'estimate', v_estimate.id,
    case when v_estimate.type = 'change_order' then 'change_order_approved' else 'estimate_approved' end,
    null, jsonb_build_object('estimate_version_id', p_estimate_version_id, 'total', v_version.total, 'customer_note', p_customer_note));
end;
$$;

create or replace function decline_estimate(p_estimate_version_id uuid, p_customer_note text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_version estimate_versions%rowtype;
  v_estimate estimates%rowtype;
  v_event_type text;
begin
  select * into v_version from estimate_versions where id = p_estimate_version_id for update;
  if v_version.id is null then
    raise exception 'estimate version not found';
  end if;

  select * into v_estimate from estimates where id = v_version.estimate_id for update;

  if not is_own_customer_record(v_estimate.customer_id) then
    raise exception 'not authorized to decline this estimate';
  end if;

  if v_estimate.current_version_id != p_estimate_version_id then
    raise exception 'this is not the current actionable version';
  end if;
  if v_version.status not in ('sent', 'viewed') then
    raise exception 'this version cannot be declined (status: %)', v_version.status;
  end if;
  if v_version.valid_until is not null and v_version.valid_until < current_date then
    raise exception 'this estimate has expired';
  end if;

  insert into estimate_decisions (organization_id, estimate_id, estimate_version_id, customer_id, decision, version_total_at_decision, customer_note)
  values (v_estimate.organization_id, v_estimate.id, p_estimate_version_id, v_estimate.customer_id, 'declined', v_version.total, p_customer_note);

  update estimate_versions set status = 'declined' where id = p_estimate_version_id;
  update estimates set status = 'declined', updated_at = now() where id = v_estimate.id;

  if v_estimate.type = 'estimate' and v_estimate.work_order_id is not null then
    if (select current_status from work_orders where id = v_estimate.work_order_id) = 'awaiting_approval' then
      perform transition_work_order(v_estimate.work_order_id, 'cancelled');
    end if;
  end if;

  v_event_type := case when v_estimate.type = 'change_order' then 'CHANGE_ORDER_DECLINED' else 'ESTIMATE_DECLINED' end;
  perform log_domain_event(v_estimate.organization_id, v_event_type, 'estimate', v_estimate.id,
    jsonb_build_object('estimate_version_id', p_estimate_version_id, 'reason', p_customer_note));
  perform log_audit_event_internal(v_estimate.organization_id, 'estimate', v_estimate.id,
    case when v_estimate.type = 'change_order' then 'change_order_declined' else 'estimate_declined' end,
    null, jsonb_build_object('estimate_version_id', p_estimate_version_id, 'reason', p_customer_note));
end;
$$;
