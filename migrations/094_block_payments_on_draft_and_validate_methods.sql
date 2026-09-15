-- =========================================================
-- 094_block_payments_on_draft_and_validate_methods.sql — Phase 7 hardening
-- =========================================================
-- BUG REAL: record_manual_payment() nunca rechazaba una invoice en
-- draft. Se agrega el chequeo, más validación del método contra
-- accepted_payment_methods real de la organización. Verificado: pago
-- en draft rechazado, tras issue_invoice() funciona, método no
-- aceptado (solo cash/zelle configurados) rechazado.
-- =========================================================

create or replace function record_manual_payment(
  p_invoice_id uuid,
  p_amount numeric,
  p_method text,
  p_reference text default null,
  p_received_at timestamptz default now(),
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invoice invoices%rowtype;
  v_settings organization_payment_settings%rowtype;
  v_current_paid numeric;
  v_payment_id uuid;
begin
  select * into v_invoice from invoices where id = p_invoice_id for update;
  if v_invoice.id is null then
    raise exception 'invoice not found';
  end if;
  if not (is_kcc_admin() or is_org_staff(v_invoice.organization_id)) then
    raise exception 'not authorized to record payments';
  end if;
  if v_invoice.status = 'draft' then
    raise exception 'cannot record a payment against a draft invoice — issue it first';
  end if;
  if v_invoice.status = 'void' then
    raise exception 'cannot record a payment against a voided invoice';
  end if;
  if p_method = 'stripe_card' then
    raise exception 'stripe_card payments must go through the Stripe payment flow, not manual recording';
  end if;

  select * into v_settings from organization_payment_settings where organization_id = v_invoice.organization_id;
  if coalesce(v_settings.manual_payments_enabled, true) is not true then
    raise exception 'manual payments are disabled for this organization';
  end if;
  if v_settings.organization_id is not null and not (p_method = any(v_settings.accepted_payment_methods)) then
    raise exception 'payment method % is not an accepted method for this organization', p_method;
  end if;

  if p_amount <= 0 then
    raise exception 'payment amount must be positive';
  end if;

  select coalesce(sum(amount), 0) into v_current_paid from payments
  where invoice_id = p_invoice_id and status = 'settled';

  if p_amount > (v_invoice.total - v_current_paid) then
    raise exception 'payment amount % exceeds invoice balance %', p_amount, (v_invoice.total - v_current_paid);
  end if;

  insert into payments (organization_id, customer_id, invoice_id, work_order_id, amount, currency, method, status, provider, reference, received_at, recorded_by, source, notes)
  values (v_invoice.organization_id, v_invoice.customer_id, p_invoice_id, v_invoice.work_order_id, p_amount, v_invoice.currency, p_method, 'settled', 'manual', p_reference, p_received_at, auth.uid(), 'staff', p_notes)
  returning id into v_payment_id;

  perform log_domain_event(v_invoice.organization_id, 'PAYMENT_RECORDED', 'payment', v_payment_id,
    jsonb_build_object('invoice_id', p_invoice_id, 'amount', p_amount, 'method', p_method));
  perform log_audit_event(v_invoice.organization_id, 'payment', v_payment_id, 'manual_payment_recorded',
    null, jsonb_build_object('invoice_id', p_invoice_id, 'amount', p_amount, 'method', p_method, 'reference', p_reference));

  if v_invoice.work_order_id is not null and (v_current_paid + p_amount) >= v_invoice.total then
    if (select current_status from work_orders where id = v_invoice.work_order_id) = 'invoice' then
      perform transition_work_order(v_invoice.work_order_id, 'payment');
    end if;
    perform log_domain_event(v_invoice.organization_id, 'INVOICE_PAID', 'invoice', p_invoice_id, jsonb_build_object('total', v_invoice.total));
  elsif (v_current_paid + p_amount) > 0 then
    perform log_domain_event(v_invoice.organization_id, 'INVOICE_PARTIALLY_PAID', 'invoice', p_invoice_id,
      jsonb_build_object('paid_so_far', v_current_paid + p_amount, 'total', v_invoice.total));
  end if;

  return v_payment_id;
end;
$$;
