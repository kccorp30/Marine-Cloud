-- =========================================================
-- 097_improve_invoice_source_traceability.sql — Phase 7 hardening
-- =========================================================
-- Antes create_invoice() para 'final'/'progress' generaba una sola
-- línea genérica "Remaining balance" — sin trazar de qué estimates/
-- change orders aprobados salía ese monto. Ahora, cuando se factura
-- exactamente el remanente completo, genera una línea por cada
-- estimate/change order aprobado del work order aún no facturado,
-- referenciando source_change_order_id — nunca duplica ni modifica
-- el historial de la estimate original. Cuando se factura un monto
-- parcial explícito, sigue usando una línea genérica (no hay forma
-- no-ambigua de prorratear automáticamente) — documentado en las
-- limitaciones.
-- =========================================================

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
  v_is_full_remaining boolean;
  v_source record;
  v_sort int := 0;
  v_lines_created int := 0;
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
  v_is_full_remaining := (p_amount is null);

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

  if v_is_full_remaining then
    for v_source in
      select e.id, e.type, e.estimate_number, ev.total
      from estimates e
      join estimate_versions ev on ev.id = e.current_version_id
      where e.work_order_id = p_work_order_id and e.status = 'approved'
        and not exists (select 1 from invoice_line_items ili where ili.source_change_order_id = e.id)
      order by e.created_at
    loop
      insert into invoice_line_items (organization_id, invoice_id, source_change_order_id, description, quantity, unit_price, sort_order)
      values (v_wo.organization_id, v_invoice_id, v_source.id,
        case when v_source.type = 'change_order' then 'Change Order ' || v_source.estimate_number else 'Approved Estimate ' || v_source.estimate_number end,
        1, v_source.total, v_sort);
      v_sort := v_sort + 1;
      v_lines_created := v_lines_created + 1;
    end loop;
  end if;

  if v_lines_created = 0 then
    insert into invoice_line_items (organization_id, invoice_id, description, quantity, unit_price, sort_order)
    values (v_wo.organization_id, v_invoice_id,
      case p_invoice_type when 'final' then 'Remaining balance' when 'progress' then 'Progress billing' else 'Balance due' end,
      1, v_amount, 0);
  end if;

  perform log_domain_event(v_wo.organization_id, 'INVOICE_CREATED', 'invoice', v_invoice_id,
    jsonb_build_object('invoice_type', p_invoice_type, 'total', v_amount, 'work_order_id', p_work_order_id));

  return v_invoice_id;
end;
$$;
