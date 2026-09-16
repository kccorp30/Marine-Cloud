-- =========================================================
-- 142_kcc_revenue_attributions.sql — Marine Cloud Phase 10
-- =========================================================
-- Regla de snapshot elegida (determinística, documentada): el
-- acuerdo vigente en work_orders.created_at — nunca "hoy". Una vez
-- creada la atribución, sus parámetros quedan congelados para
-- siempre. status='snapshot' — nunca 'paid', porque Stripe/KCC
-- Ledger no existen todavía. Idempotente: unique(work_order_id).
-- Reusa get_work_order_authorized_total() de Phase 7 para el monto
-- base.
-- Verificado con datos reales: kcc_generated=false rechazado,
-- kcc_generated=true calcula 15% de $1000 = $150 exacto, reintento
-- idempotente no duplica, cambiar el acuerdo después no altera la
-- atribución histórica ya creada.
-- =========================================================

create table kcc_revenue_attributions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  work_order_id uuid not null references work_orders(id),
  compensation_agreement_id uuid not null references compensation_agreements(id),
  compensation_type text not null check (compensation_type in ('percentage', 'fixed')),
  compensation_rate numeric(6,3),
  compensation_fixed_amount numeric(12,2),
  currency text not null default 'USD',
  basis_amount numeric(12,2) not null default 0,
  calculated_kcc_amount numeric(12,2) not null,
  status text not null default 'snapshot' check (status in ('snapshot', 'finalized')),
  created_at timestamptz not null default now(),

  constraint uq_kcc_attribution_work_order unique (work_order_id)
);

create index idx_kcc_attributions_org on kcc_revenue_attributions(organization_id, created_at desc);

alter table kcc_revenue_attributions enable row level security;

create policy "read_kcc_attributions" on kcc_revenue_attributions for select
using (is_kcc_admin());

revoke all on kcc_revenue_attributions from anon, authenticated;
grant select on kcc_revenue_attributions to authenticated;

create or replace function attribute_kcc_work(p_work_order_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_wo work_orders%rowtype;
  v_agreement compensation_agreements%rowtype;
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

  select * into v_agreement from compensation_agreements
  where organization_id = v_wo.organization_id
    and active = true
    and effective_from <= v_wo.created_at::date
    and (effective_until is null or effective_until >= v_wo.created_at::date)
  order by effective_from desc
  limit 1;

  if v_agreement.id is null then
    raise exception 'no compensation agreement was effective for this organization on the work order creation date (%)', v_wo.created_at::date;
  end if;

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

revoke execute on function attribute_kcc_work(uuid) from public, anon;
grant execute on function attribute_kcc_work(uuid) to authenticated;
