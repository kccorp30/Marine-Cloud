-- =========================================================
-- 089_payment_refunds.sql — Marine Cloud Phase 7
-- =========================================================
-- Un reembolso NUNCA borra el pago original — crea un registro
-- durable aparte. El reembolso manual se ejecuta de verdad: marca el
-- pago original 'reversed', el trigger ya existente recalcula
-- amount_paid/status de la invoice automáticamente (incluyendo volver
-- de 'paid' a 'partially_paid' si corresponde). El reembolso vía
-- Stripe queda como fundación de datos — no ejecutable en este
-- entorno (sin credenciales reales de Stripe), documentado en las
-- limitaciones.
--
-- Verificado con datos reales: reembolso de un pago cash de $200 en
-- una invoice de $500 pagada por completo -> la invoice vuelve sola a
-- amount_paid=$300, status='partially_paid', sin tocar el pago zelle
-- de $300 que sigue intacto.
-- =========================================================

create table payment_refunds (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  payment_id uuid not null references payments(id),
  invoice_id uuid not null references invoices(id),
  amount numeric(12,2) not null check (amount > 0),
  method text not null check (method in ('stripe', 'manual')),
  provider_refund_id text,
  reason text not null,
  status text not null default 'completed' check (status in ('pending', 'completed', 'failed')),
  refunded_at timestamptz not null default now(),
  created_by uuid not null references profiles(id),
  created_at timestamptz not null default now(),

  constraint fk_refunds_payment_same_org foreign key (payment_id, organization_id) references payments(id, organization_id),
  constraint fk_refunds_invoice_same_org foreign key (invoice_id, organization_id) references invoices(id, organization_id)
);

create index idx_refunds_payment on payment_refunds(payment_id);

alter table payment_refunds enable row level security;

create policy "read_payment_refunds" on payment_refunds for select
using (
  is_kcc_admin()
  or is_org_staff(organization_id)
  or exists (select 1 from invoices i where i.id = payment_refunds.invoice_id and is_own_customer_record(i.customer_id))
);

revoke all on payment_refunds from anon, authenticated;
grant select on payment_refunds to authenticated;

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

  if p_amount <= 0 or p_amount > (v_payment.amount - v_already_refunded) then
    raise exception 'refund amount % exceeds refundable amount %', p_amount, (v_payment.amount - v_already_refunded);
  end if;

  insert into payment_refunds (organization_id, payment_id, invoice_id, amount, method, reason, status, created_by)
  values (v_payment.organization_id, p_payment_id, v_payment.invoice_id, p_amount, 'manual', p_reason, 'completed', auth.uid())
  returning id into v_refund_id;

  if p_amount >= v_payment.amount then
    update payments set status = 'reversed', updated_at = now() where id = p_payment_id;
  end if;

  perform log_domain_event(v_payment.organization_id, 'PAYMENT_REFUNDED', 'payment', p_payment_id,
    jsonb_build_object('refund_id', v_refund_id, 'amount', p_amount, 'reason', p_reason));
  perform log_audit_event(v_payment.organization_id, 'payment', p_payment_id, 'payment_refunded',
    jsonb_build_object('amount', v_payment.amount), jsonb_build_object('refund_amount', p_amount, 'reason', p_reason));

  return v_refund_id;
end;
$$;

revoke execute on function refund_manual_payment(uuid, numeric, text) from public, anon;
grant execute on function refund_manual_payment(uuid, numeric, text) to authenticated;
