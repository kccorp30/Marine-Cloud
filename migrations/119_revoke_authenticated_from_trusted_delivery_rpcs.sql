-- =========================================================
-- 119_revoke_authenticated_from_trusted_delivery_rpcs.sql — Phase 8 final fix
-- =========================================================
-- BUG REAL: aunque las 4 funciones de delivery ya exigían
-- is_platform_trusted_actor() en el CUERPO (hardening anterior), el
-- GRANT EXECUTE a `authenticated` a nivel de Postgres nunca se
-- revocó — un staff normal podía seguir INVOCANDO el RPC (y recibir
-- el error en runtime), en vez de que Postgres rechazara la llamada
-- de raíz. Defensa en profundidad real: cierra la superficie una
-- capa antes.
--
-- Las llamadas legítimas de Next.js usan el cliente de service role
-- (lib/supabase/service.ts) — autentica con JWT role=service_role,
-- que Postgres mapea a la sesión `service_role` (no `authenticated`),
-- la cual ya tiene EXECUTE — este revoke no rompe el camino real.
--
-- Verificado con datos reales: llamar como `authenticated` ahora
-- falla con insufficient_privilege (rechazo de Postgres, no solo la
-- excepción de la función).
-- =========================================================

revoke execute on function record_provider_send_result(uuid, boolean, text, text) from authenticated;
revoke execute on function mark_message_delivered(uuid, text) from authenticated;
revoke execute on function mark_message_failed(uuid, text) from authenticated;
revoke execute on function process_email_webhook_event(text, text, text) from authenticated;
