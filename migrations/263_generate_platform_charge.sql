-- =========================================================
-- 263_generate_platform_charge.sql — Marine Cloud Phase 15
-- =========================================================
-- Verificado con datos reales: usa price_snapshot, nunca factura
-- complimentary/trial, idempotente real, precio de catálogo no
-- afecta charges ya emitidos.
-- =========================================================

create or replace function generate_platform_charge(p_organization_id uuid, p_period_start timestamptz default null, p_period_end timestamptz default null)
returns platform_billing_charges
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sub organization_subscriptions%rowtype;
  v_period_start timestamptz;
  v_period_end timestamptz;
  v_due_at timestamptz;
  v_charge platform_billing_charges%rowtype;
begin
  if not (is_kcc_admin() or is_platform_trusted_actor()) then
    raise exception 'not authorized to generate platform charges';
  end if;

  select * into v_sub from organization_subscriptions where organization_id = p_organization_id and superseded_at is null;
  if v_sub.id is null then
    raise exception 'no current subscription for this organization';
  end if;

  if v_sub.complimentary then
    raise exception 'cannot generate a recurring platform charge for a complimentary subscription';
  end if;
  if v_sub.status = 'trialing' then
    raise exception 'cannot bill during a free trial';
  end if;
  if v_sub.price_snapshot is null then
    raise exception 'this subscription has no price snapshot to bill from';
  end if;

  v_period_start := coalesce(p_period_start, v_sub.current_period_started_at, v_sub.subscription_started_at, now());
  v_period_end := coalesce(p_period_end, v_sub.current_period_ends_at, calculate_period_end(v_period_start, v_sub.billing_cycle));
  if v_period_end is null then
    raise exception 'cannot determine a billing period end for cycle %; provide explicit period dates', v_sub.billing_cycle;
  end if;

  v_due_at := v_period_start;

  insert into platform_billing_charges (
    organization_id, subscription_id, billing_period_start, billing_period_end, due_at,
    currency, subtotal, total_amount, balance_due, status, source, created_by
  )
  values (
    p_organization_id, v_sub.id, v_period_start, v_period_end, v_due_at,
    v_sub.currency, v_sub.price_snapshot, v_sub.price_snapshot, v_sub.price_snapshot, 'open', 'subscription', auth.uid()
  )
  on conflict (subscription_id, billing_period_start, billing_period_end) do nothing
  returning * into v_charge;

  if v_charge.id is null then
    select * into v_charge from platform_billing_charges where subscription_id = v_sub.id and billing_period_start = v_period_start and billing_period_end = v_period_end;
    return v_charge;
  end if;

  perform log_domain_event(p_organization_id, 'PLATFORM_BILLING_CHARGE_ISSUED', 'organization', p_organization_id,
    jsonb_build_object('charge_id', v_charge.id, 'total_amount', v_charge.total_amount, 'due_at', v_due_at));
  perform log_audit_event(p_organization_id, 'platform_billing_charge', v_charge.id, 'charge_generated', null, to_jsonb(v_charge));

  insert into platform_ledger_entries (organization_id, entry_type, source_type, source_id, currency, amount, direction, description)
  values (p_organization_id, 'subscription_charge', 'platform_billing_charge', v_charge.id, v_charge.currency, v_charge.total_amount, 'debit', 'Subscription charge issued');

  return v_charge;
end;
$$;

revoke execute on function generate_platform_charge(uuid, timestamptz, timestamptz) from public, anon;
grant execute on function generate_platform_charge(uuid, timestamptz, timestamptz) to authenticated;
