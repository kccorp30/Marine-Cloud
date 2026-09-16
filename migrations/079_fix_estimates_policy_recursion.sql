-- =========================================================
-- 079_fix_estimates_policy_recursion.sql — Phase 6 hardening
-- =========================================================
-- BUG REAL encontrado probando 078: la policy de estimates consulta
-- estimate_versions, y la policy de estimate_versions consulta
-- estimates de vuelta — recursión infinita real entre ambas RLS. Se
-- rompe el ciclo con una función SECURITY DEFINER (bypasea RLS al
-- evaluar) en vez de una subquery cruda dentro de la policy.
--
-- Verificado con los 4 escenarios exactos del brief, todos PASS:
-- draft nunca enviado invisible, ese mismo draft cancelado sigue
-- invisible, estimate enviada visible, esa estimate cancelada
-- después de enviada sigue visible históricamente.
-- =========================================================

create or replace function estimate_has_sent_version(p_estimate_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (select 1 from estimate_versions where estimate_id = p_estimate_id and sent_at is not null);
$$;

revoke execute on function estimate_has_sent_version(uuid) from public, anon;
grant execute on function estimate_has_sent_version(uuid) to authenticated;

drop policy if exists "read_estimates" on estimates;

create policy "read_estimates" on estimates for select
using (
  is_kcc_admin()
  or is_org_staff(organization_id)
  or (is_own_customer_record(customer_id) and estimate_has_sent_version(id))
);
