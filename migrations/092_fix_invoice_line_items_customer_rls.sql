-- =========================================================
-- 092_fix_invoice_line_items_customer_rls.sql — Phase 7 hardening
-- =========================================================
-- BUG REAL Y GRAVE: la cláusula del customer en read_invoice_line_items
-- era customer_visible=true AND invoice_has_been_sent(invoice_id) —
-- SIN verificar que la invoice le perteneciera al customer que
-- consulta. Cualquier customer autenticado que conociera el UUID de
-- una invoice ENVIADA de OTRO customer (o de otro tenant) podía leer
-- sus líneas. Verificado con 4 tests reales: dueño ve, mismo tenant
-- otro customer bloqueado, otro tenant bloqueado, técnico bloqueado.
-- =========================================================

create or replace function invoice_is_own_sent_customer_invoice(p_invoice_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from invoices i
    where i.id = p_invoice_id
      and i.sent_at is not null
      and is_own_customer_record(i.customer_id)
  );
$$;

revoke execute on function invoice_is_own_sent_customer_invoice(uuid) from public, anon;
grant execute on function invoice_is_own_sent_customer_invoice(uuid) to authenticated;

drop policy if exists "read_invoice_line_items" on invoice_line_items;
create policy "read_invoice_line_items" on invoice_line_items for select
using (
  is_kcc_admin()
  or exists (select 1 from invoices i where i.id = invoice_line_items.invoice_id and is_org_staff(i.organization_id))
  or (customer_visible = true and invoice_is_own_sent_customer_invoice(invoice_id))
);
