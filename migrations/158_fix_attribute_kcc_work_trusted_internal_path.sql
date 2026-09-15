-- =========================================================
-- 158_fix_attribute_kcc_work_trusted_internal_path.sql — Phase 11
-- =========================================================
-- BUG REAL encontrado antes de probar: attribute_kcc_work() exigía
-- is_kcc_admin() — pero el trigger automático de atribución (157)
-- corre con el rol de CUALQUIER staff normal que convierte un
-- service request. Se extiende el chequeo para también aceptar el
-- flag local ya usado por el guard de kcc_generated — la confianza
-- viene del camino de la llamada, no del rol de quien convierte.
-- Verificado con datos reales: staff normal (no kcc_admin) convierte
-- un service request originado en la web, kcc_generated se marca
-- true y la atribución se crea automáticamente; sin acuerdo vigente,
-- el work order igual se crea y el lead queda con un estado no
-- resuelto explícito.
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
  v_existing kcc_revenue_attributions%rowtype;
  v_via_trusted_rpc boolean;
begin
  v_via_trusted_rpc := coalesce(current_setting('app.kcc_generated_via_trusted_rpc', true), '') = 'true';
  if not (is_kcc_admin() or v_via_trusted_rpc) then
    raise exception 'only KCC platform staff can attribute KCC work';
  end if;

  select * into v_wo from work_orders where id = p_work_order_id;
  if v_wo.id is null then
    raise exception 'work order not found';
  end if;
  if not v_wo.kcc_generated then
    raise exception 'work order is not marked kcc_generated — no attribution created';
  end if;

  select * into v_existing from kcc_revenue_attributions where work_order_id = p_work_order_id;

  if v_existing.id is not null then
    if v_existing.status = 'revoked' then
      update kcc_revenue_attributions set status = 'snapshot', revoked_at = null, revoked_by = null
      where id = v_existing.id;
      perform log_domain_event(v_wo.organization_id, 'KCC_ATTRIBUTION_REACTIVATED', 'work_order', p_work_order_id,
        jsonb_build_object('attribution_id', v_existing.id, 'calculated_kcc_amount', v_existing.calculated_kcc_amount));
    end if;
    return v_existing.id;
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
