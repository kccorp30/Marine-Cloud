-- =========================================================
-- 230_fix_subscription_view_security_invoker.sql — Marine Cloud Phase 14
-- =========================================================
-- BUG DE SEGURIDAD REAL: organization_subscription_effective se creó
-- sin security_invoker=true — por default corre con los privilegios
-- del creador, no del usuario que consulta, saltándose la RLS real.
-- Corregido.
-- =========================================================

alter view organization_subscription_effective set (security_invoker = true);
