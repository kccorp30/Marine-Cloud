-- =========================================================
-- 045_fix_shares_org_function_anon_grant.sql — Marine Cloud Phase 3B
-- =========================================================
-- El advisor de seguridad detectó que shares_active_organization_with()
-- (migración 044) quedó ejecutable por `anon` directo — revoke de
-- `public` no alcanza para quitar un grant directo a `anon` (mismo
-- patrón de bug ya encontrado y corregido antes en este proyecto,
-- ej. migración 026). Se revoca explícito.
-- =========================================================

revoke execute on function shares_active_organization_with(uuid) from anon;
