-- =========================================================
-- 083_work_order_financial_summary.sql — Marine Cloud Phase 7
-- =========================================================
-- Autorizado/facturado/pagado/remanente/estado del depósito — todo
-- server-side. Misma autorización que get_work_order_authorized_total
-- (Phase 6): staff, customer dueño, kcc_admin — nunca technician.
-- =========================================================

create type work_order_financial_summary as (
  authorized_total numeric,
  invoiced_total numeric,
  paid_total numeric,
  remaining_invoiceable numeric,
  deposit_required boolean,
  deposit_amount numeric,
  deposit_satisfied boolean
);

create or replace function get_work_order_financial_summary(p_work_order_id uuid)
returns work_order_financial_summary
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_wo work_orders%rowtype;
  v_authorized numeric;
  v_invoiced numeric;
  v_paid numeric;
  v_settings organization_payment_settings%rowtype;
  v_deposit_amount numeric := 0;
  v_deposit_satisfied boolean := true;
  v_deposit_invoice_paid numeric := 0;
begin
  select * into v_wo from work_orders where id = p_work_order_id;
  if v_wo.id is null then
    raise exception 'work order not found';
  end if;
  if not (is_kcc_admin() or is_org_staff(v_wo.organization_id) or is_customer_of_work_order(p_work_order_id)) then
    raise exception 'not authorized';
  end if;

  v_authorized := get_work_order_authorized_total(p_work_order_id);

  select coalesce(sum(total), 0) into v_invoiced from invoices
  where work_order_id = p_work_order_id and status != 'void';

  select coalesce(sum(amount_paid), 0) into v_paid from invoices
  where work_order_id = p_work_order_id and status != 'void';

  select * into v_settings from organization_payment_settings where organization_id = v_wo.organization_id;

  if v_settings.deposit_required then
    v_deposit_amount := calculate_deposit_amount(v_authorized, v_settings.deposit_type, v_settings.deposit_value);
    select coalesce(sum(amount_paid), 0) into v_deposit_invoice_paid from invoices
    where work_order_id = p_work_order_id and invoice_type = 'deposit' and status != 'void';
    v_deposit_satisfied := v_deposit_invoice_paid >= v_deposit_amount;
  end if;

  return (
    v_authorized,
    v_invoiced,
    v_paid,
    greatest(v_authorized - v_invoiced, 0),
    coalesce(v_settings.deposit_required, false),
    v_deposit_amount,
    v_deposit_satisfied
  )::work_order_financial_summary;
end;
$$;

revoke execute on function get_work_order_financial_summary(uuid) from public, anon;
grant execute on function get_work_order_financial_summary(uuid) to authenticated;
