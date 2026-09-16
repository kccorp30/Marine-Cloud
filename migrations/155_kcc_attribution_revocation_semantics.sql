-- =========================================================
-- 155_kcc_attribution_revocation_semantics.sql — Phase 10 last closure
-- =========================================================
-- BUG REAL: set_work_order_kcc_generated(false) cambiaba el flag
-- pero dejaba kcc_revenue_attributions en status='snapshot' —
-- kcc_generated=false con una comisión potencial todavía "activa".
--
-- Modelo de reversión auditable: status ahora soporta 'revoked'.
-- true->false: NUNCA borra la fila — la marca revoked, con
-- revoked_at/revoked_by, emite evento. false->true de nuevo: regla
-- determinística — si existe una fila revoked para ese work_order_id
-- (unique constraint lo garantiza), se REACTIVA la misma con sus
-- parámetros históricos originales (nunca se recalculan) — domain_events/
-- audit_events conservan la reversión completa para siempre.
--
-- Verificado con datos reales: true crea atribución, true->false
-- revoca (status/revoked_at/revoked_by/evidencia de auditoría),
-- false->true reactiva la MISMA fila con la tasa original (20%, no
-- la 99% de un acuerdo posterior), reintento idempotente, escritura
-- directa de false sigue imposible.
-- =========================================================

alter table kcc_revenue_attributions drop constraint kcc_revenue_attributions_status_check;
alter table kcc_revenue_attributions add constraint kcc_revenue_attributions_status_check check (status in ('snapshot', 'revoked', 'finalized'));
alter table kcc_revenue_attributions add column revoked_at timestamptz;
alter table kcc_revenue_attributions add column revoked_by uuid references profiles(id);

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

create or replace function set_work_order_kcc_generated(p_work_order_id uuid, p_kcc_generated boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_attribution_id uuid;
begin
  if not is_kcc_admin() then
    raise exception 'only KCC platform staff can change kcc_generated';
  end if;

  perform set_config('app.kcc_generated_via_trusted_rpc', 'true', true);

  update work_orders set kcc_generated = p_kcc_generated, updated_at = now() where id = p_work_order_id;
  if not found then
    raise exception 'work order not found';
  end if;

  if p_kcc_generated then
    perform attribute_kcc_work(p_work_order_id);
  else
    select organization_id, id into v_org_id, v_attribution_id from kcc_revenue_attributions
    where work_order_id = p_work_order_id and status = 'snapshot';
    if v_attribution_id is not null then
      update kcc_revenue_attributions set status = 'revoked', revoked_at = now(), revoked_by = auth.uid()
      where id = v_attribution_id;
      perform log_domain_event(v_org_id, 'KCC_ATTRIBUTION_REVOKED', 'work_order', p_work_order_id,
        jsonb_build_object('attribution_id', v_attribution_id));
      perform log_audit_event(v_org_id, 'kcc_revenue_attribution', v_attribution_id, 'kcc_attribution_revoked',
        jsonb_build_object('status', 'snapshot'), jsonb_build_object('status', 'revoked'));
    end if;
  end if;

  perform set_config('app.kcc_generated_via_trusted_rpc', 'false', true);
end;
$$;
