-- =========================================================
-- 203_qc_required_snapshot_remaining_paths.sql — Phase 13 final integrity
-- =========================================================
-- Mismo snapshot vía resolve_qc_required() en los 2 caminos
-- restantes. Trabajo correctivo de garantía: hereda el default de
-- organización (decisión explícita documentada, no inventada).
-- También corrige acá: create_corrective_work_order_from_claim()
-- emitía WARRANTY_CLAIM_RESOLVED al crear el trabajo — evento
-- incorrecto (el claim recién entra a trabajo correctivo, no se
-- resolvió). Ahora emite WARRANTY_CLAIM_WORK_CREATED.
-- =========================================================

create or replace function convert_service_request_to_work_order(p_request_id uuid, p_title text DEFAULT NULL::text, p_description text DEFAULT NULL::text, p_priority text DEFAULT 'normal'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_request service_requests%rowtype;
  v_work_order_id uuid;
begin
  select * into v_request from service_requests where id = p_request_id for update;
  if v_request.id is null then
    raise exception 'service request not found';
  end if;

  if not (is_kcc_admin() or is_org_staff(v_request.organization_id)) then
    raise exception 'not authorized';
  end if;

  if v_request.status not in ('submitted', 'under_review', 'accepted') then
    raise exception 'service request cannot be converted from status %', v_request.status;
  end if;

  insert into work_orders (organization_id, customer_id, vessel_id, title, description, priority, created_by, source, website_lead_id, qc_required)
  values (
    v_request.organization_id,
    v_request.customer_id,
    v_request.vessel_id,
    coalesce(p_title, v_request.title),
    coalesce(p_description, v_request.description),
    coalesce(p_priority, case v_request.urgency when 'urgent' then 'urgent' when 'high' then 'high' when 'low' then 'low' else 'normal' end),
    auth.uid(),
    v_request.source,
    v_request.website_lead_id,
    resolve_qc_required(v_request.organization_id, null)
  )
  returning id into v_work_order_id;

  update service_requests
  set status = 'converted', converted_work_order_id = v_work_order_id, reviewed_by = auth.uid(), reviewed_at = now(), updated_at = now()
  where id = p_request_id;

  perform log_domain_event(v_request.organization_id, 'SERVICE_REQUEST_CONVERTED', 'service_request', p_request_id,
    jsonb_build_object('work_order_id', v_work_order_id));

  return v_work_order_id;
end;
$function$;

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
  if not is_org_staff(v_claim.organization_id) then
    raise exception 'not authorized to create corrective work for this organization';
  end if;

  select * into v_warranty from warranties where id = v_claim.warranty_id;
  select * into v_original from work_orders where id = v_claim.original_work_order_id;

  insert into work_orders (
    organization_id, customer_id, vessel_id, title, description, created_by,
    source, warranty_id, warranty_claim_id, qc_required
  )
  values (
    v_claim.organization_id, v_claim.customer_id, v_claim.vessel_id,
    coalesce(p_title, 'Warranty correction: ' || v_original.title),
    coalesce(p_description, v_claim.description),
    auth.uid(), 'warranty_claim', v_claim.warranty_id, p_claim_id,
    resolve_qc_required(v_claim.organization_id, null)
  )
  returning * into v_new_wo;

  update warranty_claims set claim_work_order_id = v_new_wo.id, status = 'in_progress', updated_at = now()
  where id = p_claim_id;

  perform log_domain_event(v_claim.organization_id, 'WARRANTY_CLAIM_WORK_CREATED', 'warranty', v_claim.warranty_id,
    jsonb_build_object('claim_id', p_claim_id, 'corrective_work_order_id', v_new_wo.id));

  return v_new_wo;
end;
$$;
