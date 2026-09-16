-- =========================================================
-- 109_fix_conversation_customer_visibility.sql — Phase 8 hardening
-- =========================================================
-- BUG REAL: el customer veía la fila padre de conversations apenas
-- existía, aunque solo tuviera material interno/draft — mismo error
-- de clase corregido antes en estimates (Phase 6) e invoices
-- (Phase 7). Visible solo si existe al menos un mensaje
-- customer_visible ya realmente enviado. Verificado: invisible antes
-- de cualquier mensaje, sigue invisible con solo una nota interna,
-- visible tras el primer mensaje de email enviado.
-- =========================================================

create or replace function conversation_has_customer_visible_message(p_conversation_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from messages
    where conversation_id = p_conversation_id
      and customer_visible = true
      and status in ('sent', 'delivered', 'failed')
  );
$$;

revoke execute on function conversation_has_customer_visible_message(uuid) from public, anon;
grant execute on function conversation_has_customer_visible_message(uuid) to authenticated;

drop policy if exists "read_conversations" on conversations;
create policy "read_conversations" on conversations for select
using (
  is_kcc_admin()
  or is_org_staff(organization_id)
  or (is_own_customer_record(customer_id) and conversation_has_customer_visible_message(id))
);
