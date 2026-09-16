-- =========================================================
-- 093_fix_refund_accounting_and_invoice_status.sql — Phase 7 hardening
-- =========================================================
-- BUGS REALES: (1) amount_paid ignoraba reembolsos parciales; (2)
-- refund_manual_payment() detectaba "reembolso total" comparando solo
-- el monto de ESTA llamada contra el original, no la suma acumulada
-- de varios reembolsos parciales; (3) el trigger dejaba status='paid'
-- con amount_paid=0 tras un reembolso total.
--
-- Diseño: amount_paid = pago NETO (cada pago settled menos sus
-- reembolsos completed) — el pago original nunca se edita. Status
-- determinista completo, paid_at se limpia cuando ya no aplica.
--
-- Verificado exacto contra los escenarios A/B del brief: reembolso
-- total -> amount_paid=0, balance=total, status NOT paid, paid_at
-- limpio, vuelve a 'sent'. Reembolso parcial de $100 sobre $500 ->
-- amount_paid=$400, partially_paid, balance=$100. Múltiples
-- reembolsos parciales acumulativos verificados, sobre-reembolso
-- rechazado.
-- =========================================================

create or replace function recalculate_invoice_paid_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invoice_id uuid;
  v_net_paid numeric;
  v_invoice invoices%rowtype;
begin
  v_invoice_id := coalesce(new.invoice_id, old.invoice_id);
  select * into v_invoice from invoices where id = v_invoice_id for update;

  if v_invoice.status = 'void' then
    return coalesce(new, old);
  end if;

  select coalesce(sum(
    p.amount - coalesce((select sum(r.amount) from payment_refunds r where r.payment_id = p.id and r.status = 'completed'), 0)
  ), 0)
  into v_net_paid
  from payments p
  where p.invoice_id = v_invoice_id and p.status = 'settled';

  update invoices set
    amount_paid = v_net_paid,
    status = case
      when v_net_paid >= total and total > 0 then 'paid'
      when v_net_paid > 0 then 'partially_paid'
      when sent_at is not null then 'sent'
      else status
    end,
    paid_at = case
      when v_net_paid >= total and total > 0 then coalesce(paid_at, now())
      else null
    end,
    updated_at = now()
  where id = v_invoice_id;

  return coalesce(new, old);
end;
$$;

create trigger trg_recalculate_invoice_on_refund
  after insert or update or delete on payment_refunds
  for each row execute function recalculate_invoice_paid_status();

create or replace function refund_manual_payment(p_payment_id uuid, p_amount numeric, p_reason text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment payments%rowtype;
  v_refund_id uuid;
  v_already_refunded numeric;
begin
  select * into v_payment from payments where id = p_payment_id for update;
  if v_payment.id is null then
    raise exception 'payment not found';
  end if;
  if not (is_kcc_admin() or is_org_staff(v_payment.organization_id)) then
    raise exception 'not authorized';
  end if;
  if v_payment.provider = 'stripe' then
    raise exception 'stripe payments must be refunded through the Stripe refund flow, not this manual function';
  end if;
  if v_payment.status != 'settled' then
    raise exception 'only a settled payment can be refunded (status: %)', v_payment.status;
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'a reason is required to refund a payment';
  end if;

  select coalesce(sum(amount), 0) into v_already_refunded from payment_refunds
  where payment_id = p_payment_id and status = 'completed';

  if p_amount <= 0 or (v_already_refunded + p_amount) > v_payment.amount then
    raise exception 'refund amount % exceeds refundable amount % (already refunded %)', p_amount, (v_payment.amount - v_already_refunded), v_already_refunded;
  end if;

  insert into payment_refunds (organization_id, payment_id, invoice_id, amount, method, reason, status, created_by)
  values (v_payment.organization_id, p_payment_id, v_payment.invoice_id, p_amount, 'manual', p_reason, 'completed', auth.uid())
  returning id into v_refund_id;

  if (v_already_refunded + p_amount) >= v_payment.amount then
    update payments set status = 'reversed', updated_at = now() where id = p_payment_id;
  end if;

  perform log_domain_event(v_payment.organization_id, 'PAYMENT_REFUNDED', 'payment', p_payment_id,
    jsonb_build_object('refund_id', v_refund_id, 'amount', p_amount, 'reason', p_reason));
  perform log_audit_event(v_payment.organization_id, 'payment', p_payment_id, 'payment_refunded',
    jsonb_build_object('amount', v_payment.amount), jsonb_build_object('refund_amount', p_amount, 'reason', p_reason));

  return v_refund_id;
end;
$$;
