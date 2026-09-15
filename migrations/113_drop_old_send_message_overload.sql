-- =========================================================
-- 113_drop_old_send_message_overload.sql — Phase 8 hardening
-- =========================================================
-- BUG REAL Y GRAVE encontrado verificando 111: CREATE OR REPLACE con
-- un parámetro insertado en medio de la lista no reemplaza la
-- función — Postgres la trata como un OVERLOAD nuevo, dejando la
-- firma vieja (6 parámetros, sin customer_visible/subject/
-- idempotency real) todavía viva y llamable. Se borra explícitamente.
-- Verificado: solo queda una versión de send_message tras esto.
-- =========================================================

drop function if exists send_message(uuid, text, text, text, text, text);
