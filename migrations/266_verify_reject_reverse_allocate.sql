-- =========================================================
-- 266_verify_reject_reverse_allocate.sql — Marine Cloud Phase 15
-- =========================================================
-- Verificado con datos reales: pago completo auto-asignado y charge
-- pagado, pago parcial deja partially_paid con balance correcto,
-- reversa revierte el charge a open/amount_paid=0.
-- =========================================================

create or replace function recalculate_charge_from_allocations(p_charge_id uuid)
returns platform_billing_charges
language plpgsql
security definer
set search_path = public
as $$
declare
  v_charge platform_billing_charges%rowtype;
  v_total_allocated numeric;
  v_new_status text;
begin
  select * into v_charge from platform_billing_charges where id = p_charge_id for update;
  if v_charge.id is null then
    raise exception 'charge not found';
  end if;

  select coalesce(sum(pa.amount), 0) into v_total_allocated
  from platform_payment_allocations pa
  join platform_payments pp on pp.id = pa.payment_id
  where pa.billing_charge_id = p_charge_id and pp.status = 'verified';

  if v_charge.status = 'void' then
    return v_charge;
  end if;

  v_new_status := calculate_charge_effective_status(
    case when v_total_allocated >= v_charge.total_amount then 'paid' else 'open' end,
    v_charge.total_amount - v_total_allocated, v_total_allocated, v_charge.total_amount, v_charge.due_at
  );

  update platform_billing_charges set
    amount_paid = v_total_allocated, balance_due = v_charge.total_amount - v_total_allocated,
    status = v_new_status, updated_at = now()
  where id = p_charge_id returning * into v_charge;

  return v_charge;
end;
$$;

create or replace function allocate_platform_payment(p_payment_id uuid, p_billing_charge_id uuid, p_amount numeric)
returns platform_payment_allocations
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment platform_payments%rowtype;
  v_charge platform_billing_charges%rowtype;
  v_already_allocated numeric;
  v_charge_balance numeric;
  v_allocation platform_payment_allocations%rowtype;
begin
  if not is_kcc_admin() then
    raise exception 'only KCC platform staff can allocate a payment';
  end if;
  if p_amount <= 0 then
    raise exception 'allocation amount must be positive';
  end if;

  select * into v_payment from platform_payments where id = p_payment_id for update;
  if v_payment.id is null then
    raise exception 'payment not found';
  end if;
  if v_payment.status != 'verified' then
    raise exception 'only a verified payment can be allocated (status: %)', v_payment.status;
  end if;

  select * into v_charge from platform_billing_charges where id = p_billing_charge_id for update;
  if v_charge.id is null then
    raise exception 'billing charge not found';
  end if;
  if v_charge.organization_id != v_payment.organization_id then
    raise exception 'payment and charge belong to different organizations';
  end if;
  if v_charge.currency != v_payment.currency then
    raise exception 'currency mismatch — payment is % but charge is % (no automatic FX conversion)', v_payment.currency, v_charge.currency;
  end if;
  if v_charge.status = 'void' then
    raise exception 'cannot allocate to a voided charge';
  end if;

  select coalesce(sum(amount), 0) into v_already_allocated from platform_payment_allocations where payment_id = p_payment_id;
  if v_already_allocated + p_amount > v_payment.amount then
    raise exception 'allocation would exceed the verified payment amount (already allocated: %, payment: %)', v_already_allocated, v_payment.amount;
  end if;

  v_charge_balance := v_charge.total_amount - v_charge.amount_paid;
  if p_amount > v_charge_balance then
    raise exception 'allocation would exceed the remaining charge balance (%)', v_charge_balance;
  end if;

  insert into platform_payment_allocations (payment_id, billing_charge_id, amount, created_by)
  values (p_payment_id, p_billing_charge_id, p_amount, auth.uid())
  returning * into v_allocation;

  perform recalculate_charge_from_allocations(p_billing_charge_id);

  return v_allocation;
end;
$$;

revoke execute on function allocate_platform_payment(uuid, uuid, numeric) from public, anon;
grant execute on function allocate_platform_payment(uuid, uuid, numeric) to authenticated;

create or replace function verify_platform_payment(p_payment_id uuid)
returns platform_payments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment platform_payments%rowtype;
  v_charge record;
  v_remaining numeric;
  v_to_allocate numeric;
begin
  if not is_kcc_admin() then
    raise exception 'only KCC platform staff can verify a payment';
  end if;

  select * into v_payment from platform_payments where id = p_payment_id for update;
  if v_payment.id is null then
    raise exception 'payment not found';
  end if;
  if v_payment.status != 'pending_verification' then
    raise exception 'payment is not pending verification (status: %)', v_payment.status;
  end if;

  update platform_payments set status = 'verified', verified_by = auth.uid(), verified_at = now(), updated_at = now()
  where id = p_payment_id returning * into v_payment;

  v_remaining := v_payment.amount;

  for v_charge in
    select id, total_amount - amount_paid as balance from platform_billing_charges
    where organization_id = v_payment.organization_id and currency = v_payment.currency
      and status not in ('paid', 'void') and (total_amount - amount_paid) > 0
    order by due_at asc
  loop
    exit when v_remaining <= 0;
    v_to_allocate := least(v_remaining, v_charge.balance);
    insert into platform_payment_allocations (payment_id, billing_charge_id, amount, created_by)
    values (p_payment_id, v_charge.id, v_to_allocate, auth.uid());
    perform recalculate_charge_from_allocations(v_charge.id);
    v_remaining := v_remaining - v_to_allocate;
  end loop;

  perform log_domain_event(v_payment.organization_id, 'PLATFORM_PAYMENT_VERIFIED', 'organization', v_payment.organization_id,
    jsonb_build_object('payment_id', v_payment.id, 'amount', v_payment.amount, 'unallocated_remainder', v_remaining));
  perform log_audit_event(v_payment.organization_id, 'platform_payment', p_payment_id, 'payment_verified', null, jsonb_build_object('verified_by', auth.uid()));

  insert into platform_ledger_entries (organization_id, entry_type, source_type, source_id, currency, amount, direction, description)
  values (v_payment.organization_id, 'manual_payment', 'platform_payment', p_payment_id, v_payment.currency, v_payment.amount, 'credit', 'Verified manual payment');

  perform reconcile_organization_platform_billing(v_payment.organization_id);

  return v_payment;
end;
$$;

revoke execute on function verify_platform_payment(uuid) from public, anon;
grant execute on function verify_platform_payment(uuid) to authenticated;

create or replace function reject_platform_payment(p_payment_id uuid, p_rejection_reason text)
returns platform_payments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment platform_payments%rowtype;
begin
  if not is_kcc_admin() then
    raise exception 'only KCC platform staff can reject a payment';
  end if;
  if p_rejection_reason is null or trim(p_rejection_reason) = '' then
    raise exception 'a rejection reason is required';
  end if;

  select * into v_payment from platform_payments where id = p_payment_id for update;
  if v_payment.id is null then
    raise exception 'payment not found';
  end if;
  if v_payment.status != 'pending_verification' then
    raise exception 'payment is not pending verification (status: %)', v_payment.status;
  end if;

  update platform_payments set status = 'rejected', rejected_by = auth.uid(), rejected_at = now(), rejection_reason = p_rejection_reason, updated_at = now()
  where id = p_payment_id returning * into v_payment;

  perform log_domain_event(v_payment.organization_id, 'PLATFORM_PAYMENT_REJECTED', 'organization', v_payment.organization_id,
    jsonb_build_object('payment_id', p_payment_id, 'reason', p_rejection_reason));
  perform log_audit_event(v_payment.organization_id, 'platform_payment', p_payment_id, 'payment_rejected', null, jsonb_build_object('reason', p_rejection_reason));

  return v_payment;
end;
$$;

revoke execute on function reject_platform_payment(uuid, text) from public, anon;
grant execute on function reject_platform_payment(uuid, text) to authenticated;

create or replace function reverse_platform_payment(p_payment_id uuid, p_reversal_reason text)
returns platform_payments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment platform_payments%rowtype;
  v_alloc record;
begin
  if not is_kcc_admin() then
    raise exception 'only KCC platform staff can reverse a payment';
  end if;
  if p_reversal_reason is null or trim(p_reversal_reason) = '' then
    raise exception 'a reversal reason is required';
  end if;

  select * into v_payment from platform_payments where id = p_payment_id for update;
  if v_payment.id is null then
    raise exception 'payment not found';
  end if;
  if v_payment.status != 'verified' then
    raise exception 'only a verified payment can be reversed (status: %)', v_payment.status;
  end if;

  update platform_payments set status = 'reversed', reversed_by = auth.uid(), reversed_at = now(), reversal_reason = p_reversal_reason, updated_at = now()
  where id = p_payment_id;

  for v_alloc in select distinct billing_charge_id from platform_payment_allocations where payment_id = p_payment_id
  loop
    perform recalculate_charge_from_allocations(v_alloc.billing_charge_id);
  end loop;

  perform log_domain_event(v_payment.organization_id, 'PLATFORM_PAYMENT_REVERSED', 'organization', v_payment.organization_id,
    jsonb_build_object('payment_id', p_payment_id, 'reason', p_reversal_reason));
  perform log_audit_event(v_payment.organization_id, 'platform_payment', p_payment_id, 'payment_reversed', null, jsonb_build_object('reason', p_reversal_reason));

  insert into platform_ledger_entries (organization_id, entry_type, source_type, source_id, currency, amount, direction, description)
  values (v_payment.organization_id, 'payment_reversal', 'platform_payment', p_payment_id, v_payment.currency, v_payment.amount, 'debit', 'Payment reversed: ' || p_reversal_reason);

  return v_payment;
end;
$$;

revoke execute on function reverse_platform_payment(uuid, text) from public, anon;
grant execute on function reverse_platform_payment(uuid, text) to authenticated;
