-- =========================================================
-- 120_fix_send_message_public_grant_leak.sql — Phase 8 final fix
-- =========================================================
-- BUG REAL encontrado en el advisor: send_message() era ejecutable
-- por `anon` (sin sesión) — no por un revoke explícito faltante a
-- `anon`, sino porque el rol pseudo `PUBLIC` (que anon hereda
-- automáticamente) tenía el EXECUTE por default de Postgres para
-- funciones nuevas. La migración 111 reemplazó send_message() con
-- una firma genuinamente distinta (mismo patrón de "overload nuevo"
-- ya documentado en la migración 113) — al ser, en los hechos, una
-- función nueva, nunca recibió su propio revoke explícito de
-- public/anon, solo heredó el grant default de Postgres.
-- Verificado: anon/PUBLIC ya no aparecen en los grants.
-- =========================================================

revoke execute on function send_message(uuid, text, text, text, text, text, text, boolean, text) from public, anon;
grant execute on function send_message(uuid, text, text, text, text, text, text, boolean, text) to authenticated;
