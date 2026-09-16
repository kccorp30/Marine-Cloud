-- =========================================================
-- 211_kcc_admin_authority_audit.sql — Phase 13 true final closure
-- =========================================================
-- 7 RPCs de QC/Warranty usaban solo is_org_staff() sin fallback a
-- is_kcc_admin(). Corregido acá en activate_warranty/void_warranty/
-- create_corrective_work_order_from_claim; el resto en 212. También
-- corrige acá: activate_warranty() ahora solo usa términos de
-- service_catalog cuando warranty_enabled=true — nunca una duración
-- obsoleta de un servicio con warranty deshabilitada.
-- Verificado con datos reales: kcc_admin activa/anula/crea trabajo
-- correctivo cross-org sin membresía en esa organización, Org A
-- bloqueada de operar sobre Org B, duración obsoleta con
-- warranty_enabled=false nunca usada.
-- =========================================================

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
  if not (is_org_staff(v_wo.organization_id) or is_kcc_admin()) then
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
    select * into v_service from service_catalog where id = v_wo.service_id and warranty_enabled = true;
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

create or replace function void_warranty(p_warranty_id uuid, p_reason text)
returns warranties
language plpgsql
security definer
set search_path = public
as $$
declare
  v_warranty warranties%rowtype;
begin
  select * into v_warranty from warranties where id = p_warranty_id for update;
  if v_warranty.id is null then
    raise exception 'warranty not found';
  end if;
  if not (is_org_staff(v_warranty.organization_id) or is_kcc_admin()) then
    raise exception 'not authorized to void this warranty';
  end if;
  if v_warranty.status = 'voided' then
    return v_warranty;
  end if;
  if p_reason is null or trim(p_reason) = '' then
    raise exception 'a reason is required to void a warranty';
  end if;

  update warranties set status = 'voided', voided_at = now(), void_reason = p_reason, updated_at = now()
  where id = p_warranty_id returning * into v_warranty;

  perform log_domain_event(v_warranty.organization_id, 'WARRANTY_VOIDED', 'warranty', p_warranty_id,
    jsonb_build_object('warranty_id', p_warranty_id, 'reason', p_reason));
  perform log_audit_event(v_warranty.organization_id, 'warranty', p_warranty_id, 'warranty_voided',
    jsonb_build_object('status', 'active'), jsonb_build_object('status', 'voided', 'reason', p_reason));

  return v_warranty;
end;
$$;

create or replace function create_corrective_work_order_from_claim(p_claim_id uuid, p_title text default null, p_description text default null)
returns work_orders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_claim warranty_claims%rowtype;
  v_warranty warranties%rowtype;
  v_original work_orders%rowtype;
  v_new_wo work_orders%rowtype;
begin
  select * into v_claim from warranty_claims where id = p_claim_id for update;
  if v_claim.id is null then
    raise exception 'warranty claim not found';
  end if;
  if v_claim.status != 'approved' then
    raise exception 'claim must be approved before corrective work can be created (status: %)', v_claim.status;
  end if;
  if v_claim.claim_work_order_id is not null then
    raise exception 'corrective work order already exists for this claim';
  end if;
  if not (is_org_staff(v_claim.organization_id) or is_kcc_admin()) then
    raise exception 'not authorized to create corrective work for this organization';
  end if;

  select * into v_warranty from warranties where id = v_claim.warranty_id;
  select * into v_original from work_orders where id = v_claim.original_work_order_id;

  insert into work_orders (
    organization_id, customer_id, vessel_id, title, description, created_by,
    source, warranty_id, warranty_claim_id
  )
  values (
    v_claim.organization_id, v_claim.customer_id, v_claim.vessel_id,
    coalesce(p_title, 'Warranty correction: ' || v_original.title),
    coalesce(p_description, v_claim.description),
    auth.uid(), 'warranty_claim', v_claim.warranty_id, p_claim_id
  )
  returning * into v_new_wo;

  update warranty_claims set claim_work_order_id = v_new_wo.id, status = 'in_progress', updated_at = now()
  where id = p_claim_id;

  perform log_domain_event(v_claim.organization_id, 'WARRANTY_CLAIM_WORK_CREATED', 'warranty', v_claim.warranty_id,
    jsonb_build_object('claim_id', p_claim_id, 'corrective_work_order_id', v_new_wo.id));

  return v_new_wo;
end;
$$;
