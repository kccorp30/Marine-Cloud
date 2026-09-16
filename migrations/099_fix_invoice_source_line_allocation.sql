-- =========================================================
-- 099_fix_invoice_source_line_allocation.sql — Phase 7 hardening (final)
-- =========================================================
-- BUG REAL: al facturar el remanente completo, la migración 097
-- copiaba el monto TOTAL de cada estimate/change order aprobado como
-- línea — sin restar lo ya facturado antes (ej. vía deposit invoice).
-- invoice.total (correcto) no coincidía con la suma de sus líneas.
--
-- Fix: reparto FIFO determinista. Se recorre cada fuente aprobada en
-- orden de creación, restando lo que la facturación previa de este
-- work order ya "consumió", y tomando de cada fuente solo su porción
-- no facturada, hasta cubrir exacto el monto de esta nueva invoice.
--
-- Verificado exacto contra los dos ejemplos del brief:
-- 1. Estimate $2000, deposit $1000 ya facturado, remanente $1000 ->
--    línea "Approved Estimate" = $1000 (no $2000).
-- 2. Estimate $2000 + CO1 $450 + CO2 $200 = $2650, depósito 50% =
--    $1325 ya facturado, remanente $1325 -> líneas $675 + $450 +
--    $200 = $1325 exacto.
--
-- Invariante agregada: se verifica que la suma de líneas coincida
-- exacto con el total antes de retornar — si no, la función misma
-- se rechaza en vez de dejar una invoice inconsistente.
--
-- Deuda de nombres documentada (sin renombrar en caliente):
-- source_change_order_id se usa para ambos, estimates originales y
-- change orders — ambos viven en la tabla estimates, así que es
-- correcto mecánicamente, pero el nombre es confuso. Ver comentario
-- de columna.
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
  v_already_invoiced numeric;
  v_running_covered numeric := 0;
  v_remaining_to_allocate numeric;
  v_source_remaining numeric;
  v_take numeric;
  v_source record;
  v_sort int := 0;
  v_lines_created int := 0;
  v_lines_sum numeric;
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
    select coalesce(sum(total), 0) into v_already_invoiced
    from invoices where work_order_id = p_work_order_id and status != 'void' and id != v_invoice_id;

    v_remaining_to_allocate := v_amount;

    for v_source in
      select e.id, e.type, e.estimate_number, ev.total
      from estimates e
      join estimate_versions ev on ev.id = e.current_version_id
      where e.work_order_id = p_work_order_id and e.status = 'approved'
      order by e.created_at
    loop
      exit when v_remaining_to_allocate <= 0;

      v_source_remaining := v_source.total - greatest(v_already_invoiced - v_running_covered, 0);
      v_running_covered := v_running_covered + v_source.total;

      if v_source_remaining > 0 then
        v_take := least(v_source_remaining, v_remaining_to_allocate);
        insert into invoice_line_items (organization_id, invoice_id, source_change_order_id, description, quantity, unit_price, sort_order)
        values (v_wo.organization_id, v_invoice_id, v_source.id,
          case when v_source.type = 'change_order' then 'Change Order ' || v_source.estimate_number else 'Approved Estimate ' || v_source.estimate_number end,
          1, v_take, v_sort);
        v_sort := v_sort + 1;
        v_lines_created := v_lines_created + 1;
        v_remaining_to_allocate := v_remaining_to_allocate - v_take;
      end if;
    end loop;
  end if;

  if v_lines_created = 0 then
    insert into invoice_line_items (organization_id, invoice_id, description, quantity, unit_price, sort_order)
    values (v_wo.organization_id, v_invoice_id,
      case p_invoice_type when 'final' then 'Remaining balance' when 'progress' then 'Progress billing' else 'Balance due' end,
      1, v_amount, 0);
  end if;

  select coalesce(sum(line_total), 0) into v_lines_sum from invoice_line_items where invoice_id = v_invoice_id;
  if v_lines_sum != v_amount then
    raise exception 'internal error: invoice line items (%) do not sum to invoice total (%)', v_lines_sum, v_amount;
  end if;

  perform log_domain_event(v_wo.organization_id, 'INVOICE_CREATED', 'invoice', v_invoice_id,
    jsonb_build_object('invoice_type', p_invoice_type, 'total', v_amount, 'work_order_id', p_work_order_id));

  return v_invoice_id;
end;
$$;

comment on column invoice_line_items.source_change_order_id is
  'Referencia a estimates.id — pese al nombre, se usa tanto para change orders como para la estimate original aprobada (ambos viven en la tabla estimates). Deuda de nombres documentada; renombrar a source_estimate_id queda pendiente sin afectar corrección financiera.';
