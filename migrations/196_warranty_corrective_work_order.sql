-- =========================================================
-- 196_warranty_corrective_work_order.sql — Marine Cloud Phase 13
-- =========================================================
-- El work order correctivo retiene enlaces reales a warranty/claim/
-- original — nunca sobreescribe el historial original. NUNCA marca
-- kcc_generated=true. Contabilidad de garantía real queda diferida
-- explícitamente. Verificado con datos reales: enlaces preservados,
-- kcc_generated=false, work order original intacto.
-- =========================================================

alter table work_orders add column warranty_id uuid references warranties(id);
alter table work_orders add column warranty_claim_id uuid references warranty_claims(id);

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

  perform log_domain_event(v_claim.organization_id, 'WARRANTY_CLAIM_RESOLVED', 'warranty', v_claim.warranty_id,
    jsonb_build_object('claim_id', p_claim_id, 'corrective_work_order_id', v_new_wo.id, 'stage', 'work_order_created'));

  return v_new_wo;
end;
$$;

revoke execute on function create_corrective_work_order_from_claim(uuid, text, text) from public, anon;
grant execute on function create_corrective_work_order_from_claim(uuid, text, text) to authenticated;
