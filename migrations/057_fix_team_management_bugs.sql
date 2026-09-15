-- =========================================================
-- 057_fix_team_management_bugs.sql — Marine Cloud Phase 5
-- =========================================================
-- NO-OP (hardening posterior). Esta migración originalmente corregía
-- dos bugs de la 056 (nombre de enum, ON CONFLICT sobre una
-- constraint que no existía en esa forma) — la 056 ya se reescribió
-- para incluir esas correcciones desde el inicio, así que esta
-- migración ya no tiene nada que hacer. Se deja como archivo vacío
-- (en vez de borrarla) para no romper la numeración de la cadena ni
-- reescribir historia — cualquiera que revise las migraciones ve
-- exactamente qué pasó y por qué este archivo quedó sin efecto.
-- =========================================================

select 1; -- no-op intencional
