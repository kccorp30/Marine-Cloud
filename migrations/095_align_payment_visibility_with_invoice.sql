-- =========================================================
-- 095_align_payment_visibility_with_invoice.sql — Phase 7 hardening
-- =========================================================
-- BUG REAL: read_payments dejaba ver al customer CUALQUIER pago suyo
-- por customer_id, sin importar si la invoice asociada fue enviada.
-- Reusa el mismo helper que protege invoice_line_items. Verificado:
-- pagos de invoice sin enviar ocultos, pagos de invoice enviada
-- visibles, customer ajeno bloqueado.
-- =========================================================

drop policy if exists "read_payments" on payments;
create policy "read_payments" on payments for select
using (
  is_kcc_admin()
  or is_org_staff(organization_id)
  or invoice_is_own_sent_customer_invoice(invoice_id)
);

drop policy if exists "read_payment_refunds" on payment_refunds;
create policy "read_payment_refunds" on payment_refunds for select
using (
  is_kcc_admin()
  or is_org_staff(organization_id)
  or invoice_is_own_sent_customer_invoice(invoice_id)
);
