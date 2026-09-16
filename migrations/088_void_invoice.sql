-- =========================================================
-- 088_void_invoice.sql — Marine Cloud Phase 7
-- =========================================================
-- Voidar preserva la invoice, registra quién/cuándo/por qué. No se
-- puede voidar una invoice con pagos reales sin resolverlos primero.
-- Verificado: invoice vacía se voida bien, invoice con pago rechaza.
-- =========================================================

create or replace function void_invoice(p_invoice_id uuid, p_reason text)
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
  if v_invoice.status = 'void' then
    raise exception 'invoice is already void';
  end if;
  if v_invoice.amount_paid > 0 then
    raise exception 'cannot void an invoice with recorded payments — reverse or refund the payments first';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'a reason is required to void an invoice';
  end if;

  update invoices set status = 'void', voided_at = now(), voided_by = auth.uid(), void_reason = p_reason where id = p_invoice_id;

  perform log_domain_event(v_invoice.organization_id, 'INVOICE_VOIDED', 'invoice', p_invoice_id,
    jsonb_build_object('reason', p_reason, 'total', v_invoice.total));
  perform log_audit_event(v_invoice.organization_id, 'invoice', p_invoice_id, 'invoice_voided',
    jsonb_build_object('status', v_invoice.status), jsonb_build_object('reason', p_reason));
end;
$$;

revoke execute on function void_invoice(uuid, text) from public, anon;
grant execute on function void_invoice(uuid, text) to authenticated;
