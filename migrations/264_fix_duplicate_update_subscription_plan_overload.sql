-- =========================================================
-- 264_fix_duplicate_update_subscription_plan_overload.sql — Marine Cloud Phase 15
-- =========================================================
-- BUG REAL PREEXISTENTE de Phase 14 (259): "create or replace
-- function" con una firma de tipos distinta crea una SEGUNDA
-- sobrecarga en vez de reemplazar — quedaron 2 versiones de
-- update_subscription_plan() simultáneas, causando ambigüedad real.
-- Descubierto al verificar Phase 15. Corregido eliminando la vieja.
-- =========================================================

drop function if exists update_subscription_plan(uuid, text, text, numeric, numeric, numeric, text, boolean);
