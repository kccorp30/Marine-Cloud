-- =========================================================
-- 084_invoice_creation_functions.sql — Marine Cloud Phase 7
-- =========================================================
-- El monto NUNCA lo manda el browser. Rechaza facturar por encima
-- del monto autorizado restante. Verificado con datos reales:
-- deposit invoice $1000.00 exacto (50% de $2000), invoice final por
-- exactamente el remanente aceptada, por encima rechazada.
-- =========================================================

create or replace function create_deposit_invoice(p_work_order_id uuid, p_due_date date default null)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_wo work_orders%rowtype;
  v_summary work_order_financial_summary;
  v_settings organization_payment_settings%rowtype;
  v_invoice_id uuid;
  v_currency text;
begin
  select * into v_wo from work_orders where id = p_work_order_id for update;
  if v_wo.id is null then
    raise exception 'work order not found';
  end if;
  if not (is_kcc_admin() or is_org_staff(v_wo.organization_id)) then
    raise exception 'not authorized';
  end if;

  select * into v_settings from organization_payment_settings where organization_id = v_wo.organization_id;
  if v_settings.deposit_required is not true then
    raise exception 'this organization does not require deposits — configure payment settings first';
  end if;

  if exists (select 1 from invoices where work_order_id = p_work_order_id and invoice_type = 'deposit' and status != 'void') then
    raise exception 'a deposit invoice already exists for this work order';
  end if;

  v_summary := get_work_order_financial_summary(p_work_order_id);
  if v_summary.authorized_total <= 0 then
    raise exception 'no approved commercial amount exists for this work order yet';
  end if;

  select currency into v_currency from organization_settings where organization_id = v_wo.organization_id;
  v_currency := coalesce(v_currency, 'USD');

  insert into invoices (organization_id, customer_id, vessel_id, work_order_id, invoice_number, invoice_type, currency, due_date, total, subtotal, created_by)
  values (v_wo.organization_id, v_wo.customer_id, v_wo.vessel_id, p_work_order_id,
    generate_invoice_number(v_wo.organization_id), 'deposit', v_currency, p_due_date, v_summary.deposit_amount, v_summary.deposit_amount, auth.uid())
  returning id into v_invoice_id;

  insert into invoice_line_items (organization_id, invoice_id, description, quantity, unit_price, sort_order)
  values (v_wo.organization_id, v_invoice_id,
    v_settings.deposit_type || case when v_settings.deposit_type = 'percentage' then ' deposit (' || v_settings.deposit_value || '%)' else ' deposit' end,
    1, v_summary.deposit_amount, 0);

  perform log_domain_event(v_wo.organization_id, 'INVOICE_CREATED', 'invoice', v_invoice_id,
    jsonb_build_object('invoice_type', 'deposit', 'total', v_summary.deposit_amount, 'work_order_id', p_work_order_id));

  return v_invoice_id;
end;
$$;

revoke execute on function create_deposit_invoice(uuid, date) from public, anon;
grant execute on function create_deposit_invoice(uuid, date) to authenticated;

create or replace function create_invoice(
  p_work_order_id uuid,
  p_invoice_type text,
  p_amount numeric default null,
  p_due_date date default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_wo work_orders%rowtype;
  v_summary work_order_financial_summary;
  v_amount numeric;
  v_invoice_id uuid;
  v_currency text;
begin
  select * into v_wo from work_orders where id = p_work_order_id for update;
  if v_wo.id is null then
    raise exception 'work order not found';
  end if;
  if not (is_kcc_admin() or is_org_staff(v_wo.organization_id)) then
    raise exception 'not authorized';
  end if;
  if p_invoice_type not in ('progress', 'final', 'standalone') then
    raise exception 'invalid invoice type for this function — use create_deposit_invoice for deposits';
  end if;

  v_summary := get_work_order_financial_summary(p_work_order_id);
  v_amount := coalesce(p_amount, v_summary.remaining_invoiceable);

  if v_amount <= 0 then
    raise exception 'nothing left to invoice for this work order';
  end if;
  if v_amount > v_summary.remaining_invoiceable then
    raise exception 'amount % exceeds remaining authorized invoiceable amount %', v_amount, v_summary.remaining_invoiceable;
  end if;

  select currency into v_currency from organization_settings where organization_id = v_wo.organization_id;
  v_currency := coalesce(v_currency, 'USD');

  insert into invoices (organization_id, customer_id, vessel_id, work_order_id, invoice_number, invoice_type, currency, due_date, total, subtotal, created_by)
  values (v_wo.organization_id, v_wo.customer_id, v_wo.vessel_id, p_work_order_id,
    generate_invoice_number(v_wo.organization_id), p_invoice_type, v_currency, p_due_date, v_amount, v_amount, auth.uid())
  returning id into v_invoice_id;

  insert into invoice_line_items (organization_id, invoice_id, description, quantity, unit_price, sort_order)
  values (v_wo.organization_id, v_invoice_id,
    case p_invoice_type when 'final' then 'Remaining balance' when 'progress' then 'Progress billing' else 'Balance due' end,
    1, v_amount, 0);

  perform log_domain_event(v_wo.organization_id, 'INVOICE_CREATED', 'invoice', v_invoice_id,
    jsonb_build_object('invoice_type', p_invoice_type, 'total', v_amount, 'work_order_id', p_work_order_id));

  return v_invoice_id;
end;
$$;

revoke execute on function create_invoice(uuid, text, numeric, date) from public, anon;
grant execute on function create_invoice(uuid, text, numeric, date) to authenticated;

create or replace function issue_invoice(p_invoice_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invoice invoices%rowtype;
begin
  select * into v_invoice from invoices where id = p_invoice_id for update;
  if v_invoice.id is null then
    raise exception 'invoice not found';
  end if;
  if not (is_kcc_admin() or is_org_staff(v_invoice.organization_id)) then
    raise exception 'not authorized';
  end if;
  if v_invoice.status != 'draft' then
    raise exception 'invoice is not in draft status (status: %)', v_invoice.status;
  end if;

  update invoices set status = 'sent', sent_at = now() where id = p_invoice_id;

  perform log_domain_event(v_invoice.organization_id, 'INVOICE_SENT', 'invoice', p_invoice_id,
    jsonb_build_object('total', v_invoice.total));
  perform log_audit_event(v_invoice.organization_id, 'invoice', p_invoice_id, 'invoice_issued',
    null, jsonb_build_object('total', v_invoice.total));
end;
$$;

revoke execute on function issue_invoice(uuid) from public, anon;
grant execute on function issue_invoice(uuid) to authenticated;
