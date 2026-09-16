-- =========================================================
-- 149_atomic_kcc_attribution_on_flag_set.sql — Phase 10 final fix
-- =========================================================
-- BUG REAL: la atribución solo se creaba si un kcc_admin recordaba
-- llamar attribute_kcc_work() por separado. Patrón elegido: RPC
-- dedicado atómico — set_work_order_kcc_generated() ahora, al marcar
-- true, crea la atribución EN LA MISMA TRANSACCIÓN. Si no hay
-- acuerdo vigente, la excepción revierte TODA la operación — nunca
-- queda un work order kcc_generated=true sin atribución real.
-- Verificado con datos reales: sin acuerdo, toda la operación falla
-- y kcc_generated queda false; con acuerdo, ambos (flag +
-- atribución) se crean atómicamente juntos.
-- =========================================================

create or replace function set_work_order_kcc_generated(p_work_order_id uuid, p_kcc_generated boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_kcc_admin() then
    raise exception 'only KCC platform staff can change kcc_generated';
  end if;
  update work_orders set kcc_generated = p_kcc_generated, updated_at = now() where id = p_work_order_id;
  if not found then
    raise exception 'work order not found';
  end if;

  if p_kcc_generated then
    perform attribute_kcc_work(p_work_order_id);
  end if;
end;
$$;
