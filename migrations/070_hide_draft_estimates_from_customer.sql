-- =========================================================
-- 070_hide_draft_estimates_from_customer.sql — Phase 6 hardening
-- =========================================================
-- BUG REAL: read_estimates dejaba al customer ver la fila padre de
-- estimates aunque status='draft' — violaba el requisito explícito de
-- Phase 6 de que los drafts nunca son visibles al customer.
-- Verificado: customer no ve la fila mientras es draft, sí la ve tras
-- send_estimate().
-- =========================================================

drop policy if exists "read_estimates" on estimates;

create policy "read_estimates" on estimates for select
using (
  is_kcc_admin()
  or is_org_staff(organization_id)
  or (is_own_customer_record(customer_id) and status != 'draft')
);
