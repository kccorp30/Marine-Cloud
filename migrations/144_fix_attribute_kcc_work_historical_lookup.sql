-- =========================================================
-- 144_fix_attribute_kcc_work_historical_lookup.sql — Phase 10 final fix
-- =========================================================
-- Usa resolve_compensation_agreement() (143) — resolución histórica
-- real, nunca filtrada por active=true.
-- =========================================================

create or replace function attribute_kcc_work(p_work_order_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_wo work_orders%rowtype;
  v_agreement compensation_agreements%rowtype;
  v_agreement_id uuid;
  v_basis numeric(12,2);
  v_calculated numeric(12,2);
  v_attribution_id uuid;
begin
  if not is_kcc_admin() then
    raise exception 'only KCC platform staff can attribute KCC work';
  end if;

  select * into v_wo from work_orders where id = p_work_order_id;
  if v_wo.id is null then
    raise exception 'work order not found';
  end if;
  if not v_wo.kcc_generated then
    raise exception 'work order is not marked kcc_generated — no attribution created';
  end if;

  select id into v_attribution_id from kcc_revenue_attributions where work_order_id = p_work_order_id;
  if v_attribution_id is not null then
    return v_attribution_id;
  end if;

  v_agreement_id := resolve_compensation_agreement(v_wo.organization_id, v_wo.created_at::date);
  if v_agreement_id is null then
    raise exception 'no compensation agreement was effective for this organization on the work order creation date (%)', v_wo.created_at::date;
  end if;
  select * into v_agreement from compensation_agreements where id = v_agreement_id;

  v_basis := coalesce(get_work_order_authorized_total(p_work_order_id), 0);

  v_calculated := case
    when v_agreement.compensation_type = 'percentage' then round(v_basis * v_agreement.percentage_rate / 100, 2)
    else v_agreement.fixed_amount
  end;

  insert into kcc_revenue_attributions (
    organization_id, work_order_id, compensation_agreement_id, compensation_type,
    compensation_rate, compensation_fixed_amount, currency, basis_amount, calculated_kcc_amount, status
  )
  values (
    v_wo.organization_id, p_work_order_id, v_agreement.id, v_agreement.compensation_type,
    v_agreement.percentage_rate, v_agreement.fixed_amount, v_agreement.currency, v_basis, v_calculated, 'snapshot'
  )
  returning id into v_attribution_id;

  perform log_domain_event(v_wo.organization_id, 'KCC_WORK_ATTRIBUTED', 'work_order', p_work_order_id,
    jsonb_build_object('attribution_id', v_attribution_id, 'calculated_kcc_amount', v_calculated));

  return v_attribution_id;
end;
$$;
