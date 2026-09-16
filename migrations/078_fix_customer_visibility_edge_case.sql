-- =========================================================
-- 078_fix_customer_visibility_edge_case.sql — Phase 6 hardening
-- =========================================================
-- BUG REAL: la policy de 070 usaba estimates.status != 'draft' —
-- pero cancel_estimate() puede cancelar un draft nunca enviado,
-- dejando status='cancelled' (que SÍ pasa el filtro != 'draft')
-- mientras la versión actual sigue en 'draft'. Un documento interno
-- que el customer nunca vio se volvía visible por accidente.
--
-- Fix: la visibilidad ya no se basa en el status mutable del padre,
-- sino en evidencia real e inmutable — si ALGUNA versión de esa
-- estimate tiene sent_at seteado.
--
-- NOTA: esta versión de la policy causó recursión infinita real entre
-- estimates y estimate_versions (cada RLS consultaba la otra tabla) —
-- corregido en la migración 079, aplicada por separado inmediatamente
-- después. Se deja este archivo tal cual se aplicó, reflejando el
-- historial real.
-- =========================================================

drop policy if exists "read_estimates" on estimates;

create policy "read_estimates" on estimates for select
using (
  is_kcc_admin()
  or is_org_staff(organization_id)
  or (
    is_own_customer_record(customer_id)
    and exists (
      select 1 from estimate_versions v
      where v.estimate_id = estimates.id and v.sent_at is not null
    )
  )
);
