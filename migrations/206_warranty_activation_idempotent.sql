-- =========================================================
-- 206_warranty_activation_idempotent.sql — Phase 13 final integrity
-- =========================================================
-- BUG REAL: warranties.work_order_id no era único, activate_warranty()
-- no prevenía duplicados. Ahora: constraint unique real, reintento
-- devuelve la garantía existente (nunca crea una segunda). Defensa en
-- profundidad: si qc_required=true, exige QC pasado antes de activar
-- incluso si el work order llegó a 'completed' por otro camino.
-- Verificado con datos reales: reintento no duplica.
-- =========================================================

alter table warranties add constraint uq_warranties_work_order_id unique (work_order_id);

create or replace function activate_warranty(
  p_work_order_id uuid,
  p_duration_days int default null,
  p_coverage_type text default 'workmanship',
  p_coverage_notes text default null
)
returns warranties
language plpgsql
security definer
set search_path = public
as $$
declare
  v_wo work_orders%rowtype;
  v_service service_catalog%rowtype;
  v_effective_duration int;
  v_effective_notes text;
  v_warranty warranties%rowtype;
  v_has_passed_qc boolean;
begin
  select * into v_wo from work_orders where id = p_work_order_id for update;
  if v_wo.id is null then
    raise exception 'work order not found';
  end if;
  if not exists (select 1 from organizations where id = v_wo.organization_id and status = 'active') then
    raise exception 'organization is not active';
  end if;
  if not is_org_staff(v_wo.organization_id) then
    raise exception 'not authorized to activate warranty for this organization';
  end if;
  if v_wo.current_status not in ('completed', 'warranty') then
    raise exception 'work order must be completed before warranty can be activated (current: %)', v_wo.current_status;
  end if;

  select * into v_warranty from warranties where work_order_id = p_work_order_id;
  if v_warranty.id is not null then
    return v_warranty;
  end if;

  if v_wo.qc_required then
    select exists (select 1 from qc_submissions where work_order_id = p_work_order_id and status = 'passed') into v_has_passed_qc;
    if not v_has_passed_qc then
      raise exception 'this work order requires a passed QC submission before warranty can be activated';
    end if;
  end if;

  if v_wo.service_id is not null then
    select * into v_service from service_catalog where id = v_wo.service_id;
  end if;

  v_effective_duration := coalesce(p_duration_days, v_service.warranty_duration_days);
  v_effective_notes := coalesce(p_coverage_notes, v_service.warranty_coverage_notes);

  if v_effective_duration is null then
    raise exception 'no warranty duration available — this service has no warranty configured and none was explicitly provided';
  end if;
  if v_effective_duration <= 0 then
    raise exception 'warranty duration must be positive';
  end if;

  insert into warranties (
    organization_id, work_order_id, customer_id, vessel_id, status, coverage_type, coverage_notes,
    starts_at, ends_at, created_by, activated_at
  )
  values (
    v_wo.organization_id, p_work_order_id, v_wo.customer_id, v_wo.vessel_id, 'active', p_coverage_type, v_effective_notes,
    current_date, current_date + (v_effective_duration || ' days')::interval, auth.uid(), now()
  )
  returning * into v_warranty;

  perform log_domain_event(v_wo.organization_id, 'WARRANTY_ACTIVATED', 'warranty', v_warranty.id,
    jsonb_build_object('warranty_id', v_warranty.id, 'ends_at', v_warranty.ends_at));
  perform log_audit_event(v_wo.organization_id, 'warranty', v_warranty.id, 'warranty_activated',
    null, jsonb_build_object('ends_at', v_warranty.ends_at, 'coverage_type', p_coverage_type));

  return v_warranty;
end;
$$;
