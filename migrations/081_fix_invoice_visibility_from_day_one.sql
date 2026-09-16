-- =========================================================
-- 081_fix_invoice_visibility_from_day_one.sql — Marine Cloud Phase 7
-- =========================================================
-- Aplicando la lección exacta del hardening final de Phase 6 ANTES
-- de que se repita: visibilidad basada en evidencia real (sent_at),
-- no en status mutable, vía función SECURITY DEFINER para evitar
-- recursión entre invoices/invoice_line_items.
-- =========================================================

create or replace function invoice_has_been_sent(p_invoice_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select sent_at is not null from invoices where id = p_invoice_id;
$$;

revoke execute on function invoice_has_been_sent(uuid) from public, anon;
grant execute on function invoice_has_been_sent(uuid) to authenticated;

drop policy if exists "read_invoices" on invoices;
create policy "read_invoices" on invoices for select
using (
  is_kcc_admin()
  or is_org_staff(organization_id)
  or (is_own_customer_record(customer_id) and sent_at is not null)
);

drop policy if exists "read_invoice_line_items" on invoice_line_items;
create policy "read_invoice_line_items" on invoice_line_items for select
using (
  is_kcc_admin()
  or exists (select 1 from invoices i where i.id = invoice_line_items.invoice_id and is_org_staff(i.organization_id))
  or (customer_visible = true and invoice_has_been_sent(invoice_id))
);
