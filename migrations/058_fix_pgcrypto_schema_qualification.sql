-- =========================================================
-- 058_fix_pgcrypto_schema_qualification.sql — Marine Cloud Phase 5
-- =========================================================
-- NO-OP (hardening posterior). Esta migración originalmente corregía
-- que digest()/gen_random_bytes() necesitan calificarse con
-- extensions. — la 056 ya se reescribió para incluir esa calificación
-- desde el inicio. Se deja como archivo vacío por la misma razón que
-- 057 (preservar numeración y trazabilidad, no reescribir historia).
-- =========================================================

select 1; -- no-op intencional
