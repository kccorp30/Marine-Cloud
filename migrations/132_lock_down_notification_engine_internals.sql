-- =========================================================
-- 132_lock_down_notification_engine_internals.sql — Marine Cloud Phase 9
-- =========================================================
-- Hallazgo real del advisor: generate_notifications_from_domain_event()
-- (la función del trigger) era callable por anon vía RPC — nunca
-- debería invocarse manualmente, solo Postgres la llama al insertar
-- en domain_events.
-- =========================================================

revoke execute on function generate_notifications_from_domain_event() from public, anon, authenticated;
revoke execute on function render_notification_text(text, jsonb, uuid) from authenticated;
revoke execute on function resolve_notification_recipients(text, uuid, uuid, text, uuid) from authenticated;
