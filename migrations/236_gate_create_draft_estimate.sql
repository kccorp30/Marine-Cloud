-- =========================================================
-- 236_gate_create_draft_estimate.sql — Phase 14 final integrity
-- =========================================================
-- Nuevo estimate = negocio comercial nuevo — mismo gate real.
-- =========================================================

create or replace function create_draft_estimate(p_organization_id uuid, p_customer_id uuid, p_vessel_id uuid, p_work_order_id uuid DEFAULT NULL::uuid, p_service_request_id uuid DEFAULT NULL::uuid, p_title text DEFAULT NULL::text, p_customer_message text DEFAULT NULL::text, p_valid_until date DEFAULT NULL::date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_estimate_id uuid;
  v_version_id uuid;
  v_currency text;
begin
  if not (is_kcc_admin() or is_org_staff(p_organization_id)) then
    raise exception 'not authorized to create estimates';
  end if;
  if not organization_has_active_access(p_organization_id) then
    raise exception 'this organization does not have active commercial access to create new estimates';
  end if;

  if not exists (select 1 from customers where id = p_customer_id and organization_id = p_organization_id) then
    raise exception 'customer does not belong to this organization';
  end if;
  if not exists (select 1 from vessels where id = p_vessel_id and organization_id = p_organization_id and current_customer_id = p_customer_id) then
    raise exception 'vessel does not belong to this customer/organization';
  end if;

  if p_work_order_id is not null then
    if not exists (
      select 1 from work_orders
      where id = p_work_order_id and organization_id = p_organization_id
        and customer_id = p_customer_id and vessel_id = p_vessel_id
    ) then
      raise exception 'work order does not match this organization/customer/vessel';
    end if;
  end if;

  if p_service_request_id is not null then
    if not exists (
      select 1 from service_requests
      where id = p_service_request_id and organization_id = p_organization_id
        and customer_id = p_customer_id and vessel_id = p_vessel_id
    ) then
      raise exception 'service request does not match this organization/customer/vessel';
    end if;
  end if;

  select currency into v_currency from organization_settings where organization_id = p_organization_id;
  v_currency := coalesce(v_currency, 'USD');

  insert into estimates (organization_id, customer_id, vessel_id, work_order_id, service_request_id, estimate_number, type, status, currency, created_by)
  values (p_organization_id, p_customer_id, p_vessel_id, p_work_order_id, p_service_request_id,
    generate_estimate_number(p_organization_id, 'estimate'), 'estimate', 'draft', v_currency, auth.uid())
  returning id into v_estimate_id;

  insert into estimate_versions (organization_id, estimate_id, version_number, status, title, customer_message, currency, valid_until, created_by)
  values (p_organization_id, v_estimate_id, 1, 'draft', p_title, p_customer_message, v_currency, p_valid_until, auth.uid())
  returning id into v_version_id;

  update estimates set current_version_id = v_version_id where id = v_estimate_id;

  perform log_domain_event(p_organization_id, 'ESTIMATE_CREATED', 'estimate', v_estimate_id,
    jsonb_build_object('estimate_number', (select estimate_number from estimates where id = v_estimate_id)));

  return v_estimate_id;
end;
$function$;
