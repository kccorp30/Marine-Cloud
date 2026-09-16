-- =========================================================
-- 014_fix_is_kcc_admin_grant.sql — Marine Cloud Phase 0
-- =========================================================
-- Bug real encontrado durante las pruebas de RLS de Phase 0:
-- is_kcc_admin() nunca tuvo GRANT EXECUTE a `authenticated` — se le
-- revocó de PUBLIC (correcto) pero nunca se le devolvió el permiso al
-- rol que sí debe poder invocarla desde una policy RLS. Sin esto,
-- CUALQUIER política que la usa habría fallado con "permission denied"
-- para todo usuario real logueado, no solo para anon.
grant execute on function is_kcc_admin() to authenticated;
